import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'keys.dart';
import 'models.dart';

/// SQLite-backed metadata store.
class Store {
  Store._(this._db) {
    _migrate();
  }

  /// Opens (and creates if needed) `lectern.db` inside [dataDir].
  factory Store.open(String dataDir) {
    Directory(dataDir).createSync(recursive: true);
    final db = sqlite3.open(p.join(dataDir, 'lectern.db'));
    try {
      db.execute('PRAGMA journal_mode = WAL;');
      return Store._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  factory Store.inMemory() {
    final db = sqlite3.openInMemory();
    try {
      return Store._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  final Database _db;

  /// Version 4 records which Blob object supplied each item, so saving a
  /// claimed file is safe to retry after a lost response. Versions 2 and 3
  /// migrate in place; version 1 used obsolete secret admin links.
  static const schemaVersion = 4;

  static const _uploadsV3 = '''
    CREATE TABLE IF NOT EXISTS uploads (
      shelf_id TEXT NOT NULL REFERENCES shelves(id),
      ref TEXT NOT NULL,
      blob_id TEXT NOT NULL,
      patch_id TEXT,
      owner_address TEXT NOT NULL,
      size INTEGER NOT NULL,
      kind TEXT NOT NULL,
      end_epoch INTEGER,
      start_epoch INTEGER,
      object_id TEXT,
      expires_at INTEGER,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (shelf_id, ref)
    );
    CREATE INDEX IF NOT EXISTS uploads_by_object ON uploads(object_id);
    CREATE UNIQUE INDEX IF NOT EXISTS uploads_by_patch ON uploads(patch_id)
      WHERE patch_id IS NOT NULL;
  ''';

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON;');
    var version = _db.select('PRAGMA user_version;').first.values.first as int;
    if (version > schemaVersion) {
      throw StateError('This database needs a newer version of Lectern.');
    }
    if (version == 1) {
      throw StateError(
        'This database was made by an older Lectern that used admin links. '
        'Delete it (the lectern.db files in DATA_DIR) and start again.',
      );
    }
    if (version == 2) {
      _db.execute('''
        BEGIN;
        ALTER TABLE uploads RENAME TO uploads_v2;
        $_uploadsV3
        INSERT INTO uploads (shelf_id, ref, blob_id, patch_id, owner_address,
          size, kind, end_epoch, start_epoch, object_id, expires_at,
          created_at)
          SELECT shelf_id, blob_id, blob_id, NULL, owner_address, size, kind,
            end_epoch, start_epoch, object_id, expires_at, created_at
          FROM uploads_v2;
        DROP TABLE uploads_v2;
        CREATE INDEX IF NOT EXISTS uploads_by_object ON uploads(object_id);
        CREATE UNIQUE INDEX IF NOT EXISTS uploads_by_patch ON uploads(patch_id)
          WHERE patch_id IS NOT NULL;
        ALTER TABLE items ADD COLUMN patch_id TEXT;
        PRAGMA user_version = 3;
        COMMIT;
      ''');
      version = 3;
    }
    if (version < 3) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS shelves (
          id TEXT PRIMARY KEY,
          owner_address TEXT NOT NULL,
          school TEXT NOT NULL DEFAULT '',
          department TEXT NOT NULL,
          level TEXT NOT NULL DEFAULT '',
          session TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS shelves_by_owner
          ON shelves(owner_address, created_at);
        $_uploadsV3
        CREATE TABLE IF NOT EXISTS items (
          id TEXT PRIMARY KEY,
          shelf_id TEXT NOT NULL REFERENCES shelves(id),
          blob_id TEXT NOT NULL,
          patch_id TEXT,
          file_name TEXT NOT NULL,
          kind TEXT NOT NULL,
          size INTEGER NOT NULL,
          course_code TEXT NOT NULL,
          title TEXT NOT NULL,
          type TEXT NOT NULL,
          semester TEXT NOT NULL,
          session TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          hidden INTEGER NOT NULL DEFAULT 0,
          end_epoch INTEGER,
          expires_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS items_by_shelf ON items(shelf_id, created_at);
        CREATE TABLE IF NOT EXISTS meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        PRAGMA user_version = 3;
      ''');
    }
    if (version < 4) {
      _db.execute('''
        BEGIN;
        ALTER TABLE items ADD COLUMN upload_object_id TEXT;
        -- Previous dates assumed a blob had just been certified at claim time.
        -- Keep the authoritative end epochs, but discard those estimates.
        UPDATE items SET expires_at = NULL;
        UPDATE uploads SET expires_at = NULL;
        DELETE FROM meta WHERE key = 'epoch_anchor';
        UPDATE items SET upload_object_id = (
          SELECT u.object_id FROM uploads u
          WHERE u.shelf_id = items.shelf_id
            AND u.ref = COALESCE(items.patch_id, items.blob_id)
        ) WHERE id = (
          SELECT i.id FROM items i WHERE i.shelf_id = items.shelf_id
            AND COALESCE(i.patch_id, i.blob_id) =
                COALESCE(items.patch_id, items.blob_id)
          ORDER BY i.created_at, i.id LIMIT 1
        );
        CREATE UNIQUE INDEX items_by_upload ON items(
          shelf_id, upload_object_id, COALESCE(patch_id, blob_id)
        ) WHERE upload_object_id IS NOT NULL;
        PRAGMA user_version = 4;
        COMMIT;
      ''');
    }
  }

  /// The open database, shared with the sign-in store (its tables are
  /// prefixed `sui_auth_`).
  Database get db => _db;

  void close() => _db.close();

  // Shelves ---------------------------------------------------------------

  Shelf createShelf({
    required String school,
    required String department,
    required String level,
    required String session,
    required String ownerAddress,
    required DateTime now,
  }) {
    for (var attempt = 0; attempt < 5; attempt++) {
      final id = newId();
      try {
        _db.execute(
          'INSERT INTO shelves (id, owner_address, school, department, level, '
          'session, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            id,
            ownerAddress,
            school,
            department,
            level,
            session,
            now.millisecondsSinceEpoch,
            now.millisecondsSinceEpoch,
          ],
        );
        return getShelf(id)!;
      } on SqliteException catch (e) {
        if (!e.toString().contains('UNIQUE')) rethrow;
      }
    }
    throw StateError('Could not allocate a shelf id');
  }

  Shelf? getShelf(String id) {
    final rows = _db.select('SELECT * FROM shelves WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _shelf(rows.first);
  }

  /// The shelves [ownerAddress] created, newest first, with the number of
  /// files students can see on each.
  List<({Shelf shelf, int visibleCount})> shelvesOwnedBy(String ownerAddress) {
    final rows = _db.select(
      'SELECT s.*, (SELECT COUNT(*) FROM items i WHERE i.shelf_id = s.id '
      'AND i.hidden = 0) AS visible_count FROM shelves s '
      'WHERE s.owner_address = ? ORDER BY s.created_at DESC, s.id ASC',
      [ownerAddress],
    );
    return [
      for (final row in rows)
        (shelf: _shelf(row), visibleCount: row['visible_count'] as int),
    ];
  }

  Shelf updateShelf(
    String id, {
    required String school,
    required String department,
    required String level,
    required String session,
    required DateTime now,
  }) {
    _db.execute(
      'UPDATE shelves SET school = ?, department = ?, level = ?, session = ?, '
      'updated_at = ? WHERE id = ?',
      [school, department, level, session, now.millisecondsSinceEpoch, id],
    );
    return getShelf(id)!;
  }

  Shelf _shelf(Row row) => Shelf(
    id: row['id'] as String,
    ownerAddress: row['owner_address'] as String,
    school: row['school'] as String,
    department: row['department'] as String,
    level: row['level'] as String,
    session: row['session'] as String,
    createdAt: _time(row['created_at'] as int),
    updatedAt: _time(row['updated_at'] as int),
  );

  // Uploads ---------------------------------------------------------------

  /// True when Blob object [objectId] was already claimed, by any shelf.
  bool isObjectClaimed(String objectId) => _db.select(
    'SELECT 1 FROM uploads WHERE object_id = ? LIMIT 1',
    [objectId],
  ).isNotEmpty;

  /// True when quilt patch [patchId] was already claimed, by any shelf.
  bool isPatchClaimed(String patchId) => _db.select(
    'SELECT 1 FROM uploads WHERE patch_id = ? LIMIT 1',
    [patchId],
  ).isNotEmpty;

  /// Records the files of one claimed Blob object, all or none. Returns
  /// false (and records nothing) when the object or one of the patches was
  /// claimed in the meantime.
  bool recordClaim(List<UploadRecord> uploads) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final objects = {for (final u in uploads) u.objectId}.whereType<String>();
      if (objects.any(isObjectClaimed) ||
          uploads.any((u) => u.patchId != null && isPatchClaimed(u.patchId!))) {
        _db.execute('ROLLBACK');
        return false;
      }
      for (final upload in uploads) {
        // The same bytes stored twice give the same blob ID; the newer
        // object (and its storage period) replaces the older record.
        _db.execute(
          'INSERT INTO uploads (shelf_id, ref, blob_id, patch_id, '
          'owner_address, size, kind, end_epoch, start_epoch, object_id, '
          'expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(shelf_id, ref) DO UPDATE SET '
          'blob_id = excluded.blob_id, patch_id = excluded.patch_id, '
          'owner_address = excluded.owner_address, size = excluded.size, '
          'kind = excluded.kind, end_epoch = excluded.end_epoch, '
          'start_epoch = excluded.start_epoch, object_id = excluded.object_id, '
          'expires_at = excluded.expires_at, created_at = excluded.created_at',
          [
            upload.shelfId,
            upload.ref,
            upload.blobId,
            upload.patchId,
            upload.ownerAddress,
            upload.size,
            upload.kind.wire,
            upload.endEpoch,
            upload.startEpoch,
            upload.objectId,
            upload.expiresAt?.millisecondsSinceEpoch,
            upload.createdAt.millisecondsSinceEpoch,
          ],
        );
      }
      _db.execute('COMMIT');
      return true;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// The upload [ref] (a patch ID or a blob ID) of [shelfId], or null.
  UploadRecord? getUpload(String shelfId, String ref) {
    final rows = _db.select(
      'SELECT * FROM uploads WHERE shelf_id = ? AND ref = ?',
      [shelfId, ref],
    );
    if (rows.isEmpty) return null;
    return _upload(rows.first);
  }

  List<UploadRecord> uploadsForObject(String objectId) => _db
      .select('SELECT * FROM uploads WHERE object_id = ?', [objectId])
      .map(_upload)
      .toList();

  UploadRecord _upload(Row row) => UploadRecord(
    shelfId: row['shelf_id'] as String,
    ownerAddress: row['owner_address'] as String,
    blobId: row['blob_id'] as String,
    patchId: row['patch_id'] as String?,
    size: row['size'] as int,
    kind: FileKind.fromWire(row['kind'])!,
    endEpoch: row['end_epoch'] as int?,
    startEpoch: row['start_epoch'] as int?,
    objectId: row['object_id'] as String?,
    expiresAt: _maybeTime(row['expires_at'] as int?),
    createdAt: _time(row['created_at'] as int),
  );

  // Items -----------------------------------------------------------------

  Item createItem({
    required String shelfId,
    required UploadRecord upload,
    required String fileName,
    required String courseCode,
    required String title,
    required ItemType type,
    required Semester semester,
    required String session,
    required String description,
    required DateTime now,
  }) {
    // Retrying a save after its response was lost must not duplicate the file
    // or undo any edits made since it was first saved.
    if (upload.objectId != null) {
      final existing = _db.select(
        'SELECT * FROM items WHERE shelf_id = ? AND upload_object_id = ? '
        'AND COALESCE(patch_id, blob_id) = ?',
        [shelfId, upload.objectId, upload.ref],
      );
      if (existing.isNotEmpty) return _item(existing.first);
    }
    final id = newId(12);
    _db.execute(
      'INSERT INTO items (id, shelf_id, blob_id, patch_id, file_name, kind, '
      'size, course_code, title, type, semester, session, description, '
      'hidden, end_epoch, expires_at, created_at, updated_at, upload_object_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?)',
      [
        id,
        shelfId,
        upload.blobId,
        upload.patchId,
        fileName,
        upload.kind.wire,
        upload.size,
        courseCode,
        title,
        type.wire,
        semester.wire,
        session,
        description,
        upload.endEpoch,
        upload.expiresAt?.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        upload.objectId,
      ],
    );
    return getItem(shelfId, id)!;
  }

  Item? getItem(String shelfId, String itemId) {
    final rows = _db.select(
      'SELECT * FROM items WHERE shelf_id = ? AND id = ?',
      [shelfId, itemId],
    );
    return rows.isEmpty ? null : _item(rows.first);
  }

  List<Item> listItems(String shelfId, {required bool includeHidden}) {
    final rows = _db.select(
      'SELECT * FROM items WHERE shelf_id = ? '
      '${includeHidden ? '' : 'AND hidden = 0 '}'
      'ORDER BY course_code ASC, created_at DESC',
      [shelfId],
    );
    return rows.map(_item).toList();
  }

  int countVisibleItems(String shelfId) =>
      _db.select(
            'SELECT COUNT(*) AS n FROM items WHERE shelf_id = ? AND hidden = 0',
            [shelfId],
          ).first['n']
          as int;

  Item updateItem(
    String shelfId,
    String itemId, {
    String? courseCode,
    String? title,
    ItemType? type,
    Semester? semester,
    String? session,
    String? description,
    bool? hidden,
    required DateTime now,
  }) {
    final current = getItem(shelfId, itemId)!;
    _db.execute(
      'UPDATE items SET course_code = ?, title = ?, type = ?, semester = ?, '
      'session = ?, description = ?, hidden = ?, updated_at = ? '
      'WHERE shelf_id = ? AND id = ?',
      [
        courseCode ?? current.courseCode,
        title ?? current.title,
        (type ?? current.type).wire,
        (semester ?? current.semester).wire,
        session ?? current.session,
        description ?? current.description,
        (hidden ?? current.hidden) ? 1 : 0,
        now.millisecondsSinceEpoch,
        shelfId,
        itemId,
      ],
    );
    return getItem(shelfId, itemId)!;
  }

  Item _item(Row row) => Item(
    id: row['id'] as String,
    shelfId: row['shelf_id'] as String,
    blobId: row['blob_id'] as String,
    patchId: row['patch_id'] as String?,
    fileName: row['file_name'] as String,
    kind: FileKind.fromWire(row['kind'])!,
    size: row['size'] as int,
    courseCode: row['course_code'] as String,
    title: row['title'] as String,
    type: ItemType.fromWire(row['type']) ?? ItemType.other,
    semester: Semester.fromWire(row['semester']) ?? Semester.first,
    session: row['session'] as String,
    description: row['description'] as String,
    hidden: (row['hidden'] as int) != 0,
    endEpoch: row['end_epoch'] as int?,
    expiresAt: _maybeTime(row['expires_at'] as int?),
    createdAt: _time(row['created_at'] as int),
    updatedAt: _time(row['updated_at'] as int),
  );

  // Meta ------------------------------------------------------------------

  String? getMeta(String key) {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setMeta(String key, String value) {
    _db.execute(
      'INSERT INTO meta (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  static DateTime _time(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  static DateTime? _maybeTime(int? ms) => ms == null ? null : _time(ms);
}
