import 'models.dart';

/// A request field that failed validation.
class ValidationException implements Exception {
  ValidationException(this.field, this.message);
  final String field;
  final String message;

  @override
  String toString() => '$field: $message';
}

final _controlChars = RegExp(r'[\x00-\x1F\x7F]');
final _spaces = RegExp(r'\s+');

/// Trims, removes control characters and collapses runs of whitespace.
String cleanText(Object? value) {
  if (value == null) return '';
  if (value is! String) return '';
  return value.replaceAll(_controlChars, ' ').replaceAll(_spaces, ' ').trim();
}

String requireText(
  Map<String, Object?> body,
  String field, {
  required String label,
  int min = 1,
  required int max,
}) {
  final value = cleanText(body[field]);
  if (value.length < min) {
    throw ValidationException(
      field,
      min <= 1
          ? '$label is required.'
          : '$label needs at least $min characters.',
    );
  }
  if (value.length > max) {
    throw ValidationException(field, '$label can be at most $max characters.');
  }
  return value;
}

String optionalText(
  Map<String, Object?> body,
  String field, {
  required String label,
  required int max,
}) {
  final value = cleanText(body[field]);
  if (value.length > max) {
    throw ValidationException(field, '$label can be at most $max characters.');
  }
  return value;
}

final _courseCode = RegExp(r'^([A-Za-z]{2,5})\s*[-/]?\s*(\d{3}[A-Za-z]?)$');

/// Normalises "csc301", "CSC-301" or "csc 301" to "CSC 301". Returns null when
/// the value does not look like a course code.
String? normalizeCourseCode(String raw) {
  final match = _courseCode.firstMatch(raw.trim());
  if (match == null) return null;
  return '${match.group(1)!.toUpperCase()} ${match.group(2)!.toUpperCase()}';
}

String requireCourseCode(Map<String, Object?> body) {
  final raw = cleanText(body['courseCode']);
  if (raw.isEmpty) {
    throw ValidationException('courseCode', 'Course code is required.');
  }
  final code = normalizeCourseCode(raw);
  if (code == null) {
    throw ValidationException('courseCode', 'Use a course code like CSC 301.');
  }
  return code;
}

final _session = RegExp(r'^(\d{4})\s*/\s*(\d{4})$');

/// Returns "2026/2027" for valid sessions, or null.
String? normalizeSession(String raw) {
  final match = _session.firstMatch(raw.trim());
  if (match == null) return null;
  final start = int.parse(match.group(1)!);
  final end = int.parse(match.group(2)!);
  if (end != start + 1 || start < 1960 || start > 2200) return null;
  return '$start/$end';
}

String requireSession(Map<String, Object?> body, {String field = 'session'}) {
  final raw = cleanText(body[field]);
  if (raw.isEmpty) throw ValidationException(field, 'Session is required.');
  final session = normalizeSession(raw);
  if (session == null) {
    throw ValidationException(field, 'Use a session like 2026/2027.');
  }
  return session;
}

String optionalSession(Map<String, Object?> body, {String field = 'session'}) {
  final raw = cleanText(body[field]);
  if (raw.isEmpty) return '';
  final session = normalizeSession(raw);
  if (session == null) {
    throw ValidationException(field, 'Use a session like 2026/2027.');
  }
  return session;
}

ItemType requireItemType(Map<String, Object?> body) {
  final type = ItemType.fromWire(body['type']);
  if (type == null) {
    throw ValidationException(
      'type',
      'Choose a type: lecture note, past question, assignment or other.',
    );
  }
  return type;
}

Semester requireSemester(Map<String, Object?> body) {
  final semester = Semester.fromWire(body['semester']);
  if (semester == null) {
    throw ValidationException('semester', 'Choose first or second semester.');
  }
  return semester;
}

/// Keeps a download name safe: no path parts, no control characters.
String cleanFileName(Object? value) {
  var name = cleanText(value);
  name = name.split(RegExp(r'[\\/]')).last;
  name = name.replaceAll(RegExp(r'[<>:"|?*]'), '_').trim();
  if (name.startsWith('.')) name = name.replaceFirst(RegExp(r'^\.+'), '');
  if (name.length > 160) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && name.length - dot <= 8 ? name.substring(dot) : '';
    name = name.substring(0, 160 - ext.length) + ext;
  }
  return name;
}

/// Makes sure the file name ends with the extension of the detected kind.
String fileNameForKind(String name, FileKind kind) {
  const extensions = {
    FileKind.pdf: ['.pdf'],
    FileKind.png: ['.png'],
    FileKind.jpeg: ['.jpg', '.jpeg'],
    FileKind.webp: ['.webp'],
    FileKind.gif: ['.gif'],
    FileKind.docx: ['.docx'],
    FileKind.pptx: ['.pptx'],
  };
  final allowed = extensions[kind]!;
  final lower = name.toLowerCase();
  if (allowed.any(lower.endsWith)) return name;
  final base = name.isEmpty ? 'file' : name;
  return '$base${allowed.first}';
}
