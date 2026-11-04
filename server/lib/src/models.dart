/// Item types a shelf can hold.
enum ItemType {
  lectureNote('lecture_note', 'Lecture note'),
  pastQuestion('past_question', 'Past question'),
  assignment('assignment', 'Assignment'),
  other('other', 'Other');

  const ItemType(this.wire, this.label);
  final String wire;
  final String label;

  static ItemType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

enum Semester {
  first('first'),
  second('second');

  const Semester(this.wire);
  final String wire;

  static Semester? fromWire(Object? value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// File kinds accepted for upload, detected from the file's bytes.
enum FileKind {
  pdf('pdf', 'application/pdf'),
  png('png', 'image/png'),
  jpeg('jpeg', 'image/jpeg'),
  webp('webp', 'image/webp'),
  gif('gif', 'image/gif'),
  docx(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  pptx(
    'pptx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  );

  const FileKind(this.wire, this.mimeType);
  final String wire;
  final String mimeType;

  static FileKind? fromWire(Object? value) {
    for (final k in values) {
      if (k.wire == value) return k;
    }
    return null;
  }
}

class Shelf {
  Shelf({
    required this.id,
    required this.ownerAddress,
    required this.school,
    required this.department,
    required this.level,
    required this.session,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// The Sui address of the rep who created the shelf. Never sent to
  /// students; uploads to this shelf are owned by this address on chain.
  final String ownerAddress;
  final String school;
  final String department;
  final String level;
  final String session;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// For example "FUTO · Computer Science · 300 Level · 2026/2027".
  String get title => [
    school,
    department,
    level,
    session,
  ].where((p) => p.trim().isNotEmpty).join(' · ');

  Map<String, Object?> toJson({int? itemCount}) => {
    'id': id,
    'school': school,
    'department': department,
    'level': level,
    'session': session,
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'itemCount': ?itemCount,
  };
}

/// A file a shelf's owner stored on Walrus with their own wallet and then
/// claimed for the shelf. Every fact here was read from Sui or the
/// aggregator, not taken from the browser.
class UploadRecord {
  UploadRecord({
    required this.shelfId,
    required this.ownerAddress,
    required this.blobId,
    this.patchId,
    required this.size,
    required this.kind,
    required this.endEpoch,
    required this.startEpoch,
    required this.objectId,
    required this.expiresAt,
    required this.createdAt,
  });

  final String shelfId;

  /// The address that owned the Blob object when it was claimed.
  final String ownerAddress;

  /// The blob ID; for a file in a quilt, the quilt's blob ID.
  final String blobId;

  /// The quilt patch ID of a file stored in a batch; null for a single blob.
  final String? patchId;
  final int size;
  final FileKind kind;
  final int? endEpoch;
  final int? startEpoch;
  final String? objectId;
  final DateTime? expiresAt;
  final DateTime createdAt;

  /// The key items use to point at this file: the patch ID in a quilt,
  /// otherwise the blob ID.
  String get ref => patchId ?? blobId;

  Map<String, Object?> toJson() => {
    'blobId': blobId,
    'patchId': patchId,
    'objectId': objectId,
    'size': size,
    'kind': kind.wire,
    'endEpoch': endEpoch,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
  };
}

class Item {
  Item({
    required this.id,
    required this.shelfId,
    required this.blobId,
    this.patchId,
    required this.fileName,
    required this.kind,
    required this.size,
    required this.courseCode,
    required this.title,
    required this.type,
    required this.semester,
    required this.session,
    required this.description,
    required this.hidden,
    required this.endEpoch,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String shelfId;
  final String blobId;

  /// Set for files stored in a quilt: read them by patch ID.
  final String? patchId;
  final String fileName;
  final FileKind kind;
  final int size;
  final String courseCode;
  final String title;
  final ItemType type;
  final Semester semester;
  final String session;
  final String description;
  final bool hidden;
  final int? endEpoch;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool isExpired(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);

  Map<String, Object?> toJson(DateTime now) => {
    'id': id,
    'shelfId': shelfId,
    'blobId': blobId,
    'patchId': patchId,
    'fileName': fileName,
    'kind': kind.wire,
    'mimeType': kind.mimeType,
    'size': size,
    'courseCode': courseCode,
    'title': title,
    'type': type.wire,
    'semester': semester.wire,
    'session': session,
    'description': description,
    'hidden': hidden,
    'endEpoch': endEpoch,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'expired': isExpired(now),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}
