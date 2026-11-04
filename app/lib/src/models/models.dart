/// Data types shared by the screens and services.
library;

enum ItemType {
  lectureNote('lecture_note', 'Lecture note', 'Lecture notes'),
  pastQuestion('past_question', 'Past question', 'Past questions'),
  assignment('assignment', 'Assignment', 'Assignments'),
  other('other', 'Other', 'Other');

  const ItemType(this.wire, this.label, this.plural);
  final String wire;
  final String label;
  final String plural;

  static ItemType fromWire(Object? value) =>
      values.firstWhere((t) => t.wire == value, orElse: () => ItemType.other);
}

enum Semester {
  first('first', 'First semester', 'Harmattan'),
  second('second', 'Second semester', 'Rain');

  const Semester(this.wire, this.label, this.alsoCalled);
  final String wire;
  final String label;

  /// The name many Nigerian universities use for this semester.
  final String alsoCalled;

  static Semester fromWire(Object? value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => Semester.first);
}

/// What the browser can do with a file.
enum FileKind {
  pdf('pdf', 'PDF', 'application/pdf', ['.pdf']),
  png('png', 'PNG image', 'image/png', ['.png']),
  jpeg('jpeg', 'JPEG image', 'image/jpeg', ['.jpg', '.jpeg']),
  webp('webp', 'WebP image', 'image/webp', ['.webp']),
  gif('gif', 'GIF image', 'image/gif', ['.gif']),
  docx(
    'docx',
    'Word document',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ['.docx'],
  ),
  pptx(
    'pptx',
    'PowerPoint deck',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    ['.pptx'],
  );

  const FileKind(this.wire, this.label, this.mimeType, this.extensions);
  final String wire;
  final String label;
  final String mimeType;
  final List<String> extensions;

  bool get isImage =>
      this == png || this == jpeg || this == webp || this == gif;

  /// Three-letter badge shown next to a file.
  String get badge => switch (this) {
    pdf => 'PDF',
    docx => 'DOC',
    pptx => 'PPT',
    _ => 'IMG',
  };

  static FileKind? fromWire(Object? value) {
    for (final k in values) {
      if (k.wire == value) return k;
    }
    return null;
  }

  /// Guesses the kind from a file name's extension.
  static FileKind? fromFileName(String name) {
    final lower = name.toLowerCase();
    for (final k in values) {
      if (k.extensions.any(lower.endsWith)) return k;
    }
    return null;
  }

  static List<String> get allExtensions => [
    for (final k in values) ...k.extensions,
  ];
}

class Shelf {
  const Shelf({
    required this.id,
    required this.school,
    required this.department,
    required this.level,
    required this.session,
    required this.title,
    required this.createdAt,
    this.itemCount,
  });

  final String id;
  final String school;
  final String department;
  final String level;
  final String session;
  final String title;
  final DateTime createdAt;
  final int? itemCount;

  factory Shelf.fromJson(Map<String, Object?> json) => Shelf(
    id: json['id'] as String,
    school: (json['school'] as String?) ?? '',
    department: (json['department'] as String?) ?? '',
    level: (json['level'] as String?) ?? '',
    session: (json['session'] as String?) ?? '',
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    itemCount: json['itemCount'] as int?,
  );

  /// Level and session, for the line under the shelf name.
  String get subtitle =>
      [level, session].where((p) => p.trim().isNotEmpty).join(' · ');
}

class Item {
  const Item({
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
    required this.createdAt,
    required this.updatedAt,
    this.endEpoch,
    this.expiresAt,
    this.expired = false,
  });

  final String id;
  final String shelfId;

  /// The Walrus blob; for a file stored in a batch, the batch's quilt.
  final String blobId;

  /// The quilt patch ID of a file stored in a batch: read it by this.
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
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? endEpoch;
  final DateTime? expiresAt;
  final bool expired;

  factory Item.fromJson(Map<String, Object?> json) => Item(
    id: json['id'] as String,
    shelfId: json['shelfId'] as String,
    blobId: json['blobId'] as String,
    patchId: json['patchId'] as String?,
    fileName: json['fileName'] as String,
    kind: FileKind.fromWire(json['kind']) ?? FileKind.pdf,
    size: json['size'] as int,
    courseCode: json['courseCode'] as String,
    title: json['title'] as String,
    type: ItemType.fromWire(json['type']),
    semester: Semester.fromWire(json['semester']),
    session: json['session'] as String,
    description: (json['description'] as String?) ?? '',
    hidden: json['hidden'] == true,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    endEpoch: json['endEpoch'] as int?,
    expiresAt: json['expiresAt'] == null
        ? null
        : DateTime.parse(json['expiresAt'] as String),
    expired: json['expired'] == true,
  );

  Item copyWith({bool? hidden}) => Item(
    id: id,
    shelfId: shelfId,
    blobId: blobId,
    patchId: patchId,
    fileName: fileName,
    kind: kind,
    size: size,
    courseCode: courseCode,
    title: title,
    type: type,
    semester: semester,
    session: session,
    description: description,
    hidden: hidden ?? this.hidden,
    createdAt: createdAt,
    updatedAt: updatedAt,
    endEpoch: endEpoch,
    expiresAt: expiresAt,
    expired: expired,
  );
}

/// A shelf with its items, as returned by the API.
class ShelfPage {
  const ShelfPage({
    required this.shelf,
    required this.items,
    required this.serverTime,
    this.canManage = false,
  });

  final Shelf shelf;
  final List<Item> items;
  final DateTime serverTime;

  /// True when the signed-in rep owns this shelf.
  final bool canManage;

  ShelfPage copyWith({Shelf? shelf, List<Item>? items}) => ShelfPage(
    shelf: shelf ?? this.shelf,
    items: items ?? this.items,
    serverTime: serverTime,
    canManage: canManage,
  );

  factory ShelfPage.fromJson(Map<String, Object?> json) => ShelfPage(
    shelf: Shelf.fromJson(json['shelf'] as Map<String, Object?>),
    items: (json['items'] as List? ?? const [])
        .map((e) => Item.fromJson(e as Map<String, Object?>))
        .toList(),
    serverTime: json['serverTime'] == null
        ? DateTime.now().toUtc()
        : DateTime.parse(json['serverTime'] as String),
    canManage: json['canManage'] == true,
  );
}

class ItemPage {
  const ItemPage({
    required this.shelf,
    required this.item,
    required this.serverTime,
    this.canManage = false,
  });

  final Shelf shelf;
  final Item item;
  final DateTime serverTime;

  /// True when the signed-in rep owns this shelf.
  final bool canManage;

  ItemPage withItem(Item item) => ItemPage(
    shelf: shelf,
    item: item,
    serverTime: serverTime,
    canManage: canManage,
  );

  factory ItemPage.fromJson(Map<String, Object?> json) => ItemPage(
    shelf: Shelf.fromJson(json['shelf'] as Map<String, Object?>),
    item: Item.fromJson(json['item'] as Map<String, Object?>),
    serverTime: json['serverTime'] == null
        ? DateTime.now().toUtc()
        : DateTime.parse(json['serverTime'] as String),
    canManage: json['canManage'] == true,
  );
}

/// What the create-shelf form sends.
class ShelfDraft {
  const ShelfDraft({
    this.school = '',
    required this.department,
    this.level = '',
    this.session = '',
  });

  final String school;
  final String department;
  final String level;
  final String session;

  String get title => [
    school,
    department,
    level,
    session,
  ].map((p) => p.trim()).where((p) => p.isNotEmpty).join(' · ');

  Map<String, Object?> toJson() => {
    'school': school.trim(),
    'department': department.trim(),
    'level': level.trim(),
    'session': session.trim(),
  };
}

class CreatedShelf {
  const CreatedShelf({required this.shelf, required this.publicUrl});

  final Shelf shelf;
  final String publicUrl;

  factory CreatedShelf.fromJson(Map<String, Object?> json) => CreatedShelf(
    shelf: Shelf.fromJson(json['shelf'] as Map<String, Object?>),
    publicUrl: json['publicUrl'] as String,
  );
}

/// Item metadata entered by a rep.
class ItemDraft {
  const ItemDraft({
    required this.courseCode,
    required this.title,
    required this.type,
    required this.semester,
    required this.session,
    this.description = '',
  });

  final String courseCode;
  final String title;
  final ItemType type;
  final Semester semester;
  final String session;
  final String description;

  Map<String, Object?> toJson() => {
    'courseCode': courseCode,
    'title': title,
    'type': type.wire,
    'semester': semester.wire,
    'session': session,
    'description': description,
  };
}

/// Server configuration from `GET /api/config`.
class AppConfig {
  const AppConfig({
    required this.aggregatorUrl,
    required this.network,
    required this.epochs,
    required this.epochDurationHours,
    required this.maxUploadBytes,
    required this.publicBaseUrl,
    this.suiChain = 'sui:testnet',
  });

  final Uri aggregatorUrl;

  /// `testnet` or `mainnet`: where the rep's wallet pays for storage.
  final String network;

  /// The storage period the app suggests; the rep pays for what they pick.
  final int epochs;
  final int epochDurationHours;
  final int maxUploadBytes;
  final String publicBaseUrl;

  /// The Sui network reps sign in on, as a Wallet Standard chain id.
  final String suiChain;

  factory AppConfig.fromJson(Map<String, Object?> json) => AppConfig(
    aggregatorUrl: Uri.parse(json['aggregatorUrl'] as String),
    network: (json['network'] as String?) ?? 'testnet',
    epochs: (json['epochs'] as int?) ?? 1,
    epochDurationHours: (json['epochDurationHours'] as int?) ?? 24,
    maxUploadBytes: (json['maxUploadBytes'] as int?) ?? 25 * 1024 * 1024,
    publicBaseUrl: json['publicBaseUrl'] as String,
    suiChain: (json['suiChain'] as String?) ?? 'sui:testnet',
  );

  String shelfUrl(String shelfId) => '$publicBaseUrl/s/$shelfId';
  String itemUrl(String shelfId, String itemId) =>
      '$publicBaseUrl/s/$shelfId/i/$itemId';
  String posterUrl(String shelfId) => '$publicBaseUrl/s/$shelfId/print';
}
