import 'models.dart';

final _courseCode = RegExp(r'^([A-Za-z]{2,5})\s*[-/_]?\s*(\d{3}[A-Za-z]?)$');

/// Normalises "csc301" or "CSC-301" to "CSC 301". Null if it is not a code.
String? normalizeCourseCode(String raw) {
  final match = _courseCode.firstMatch(raw.trim());
  if (match == null) return null;
  return '${match.group(1)!.toUpperCase()} ${match.group(2)!.toUpperCase()}';
}

String? validateCourseCode(String raw) {
  if (raw.trim().isEmpty) return 'Enter a course code.';
  if (normalizeCourseCode(raw) == null) {
    return 'Use a course code like CSC 301.';
  }
  return null;
}

final _session = RegExp(r'^(\d{4})\s*/\s*(\d{4})$');

String? normalizeSession(String raw) {
  final match = _session.firstMatch(raw.trim());
  if (match == null) return null;
  final start = int.parse(match.group(1)!);
  final end = int.parse(match.group(2)!);
  if (end != start + 1 || start < 1960 || start > 2200) return null;
  return '$start/$end';
}

String? validateSession(String raw, {bool required = true}) {
  if (raw.trim().isEmpty) return required ? 'Enter a session.' : null;
  if (normalizeSession(raw) == null) return 'Use a session like 2026/2027.';
  return null;
}

String? validateTitle(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'Enter a title.';
  if (value.length > 120) return 'Keep the title under 120 characters.';
  return null;
}

String? validateDescription(String raw) =>
    raw.trim().length > 280 ? 'Keep the note under 280 characters.' : null;

String? validateDepartment(String raw) {
  final value = raw.trim();
  if (value.length < 2) return 'Enter the department or course.';
  if (value.length > 80) return 'Keep this under 80 characters.';
  return null;
}

String? validateShortText(String raw, {required String label, int max = 40}) =>
    raw.trim().length > max ? '$label can be at most $max characters.' : null;

/// The academic session that is running on [now]. Nigerian sessions usually
/// start around September or October.
String currentSession(DateTime now) {
  final start = now.month >= 9 ? now.year : now.year - 1;
  return '$start/${start + 1}';
}

/// Checks a picked file before upload. Returns an error message or null.
String? validatePickedFile({
  required String name,
  required int size,
  required int maxBytes,
}) {
  if (FileKind.fromFileName(name) == null) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.doc') || lower.endsWith('.ppt')) {
      return 'Older .doc and .ppt files are not supported. Save as .docx or '
          '.pptx, or export to PDF.';
    }
    return 'This file type is not supported. Use PDF, PNG, JPEG, WebP, GIF, '
        '.docx or .pptx.';
  }
  if (size <= 0) return 'This file is empty.';
  if (size > maxBytes) {
    return 'This file is ${formatBytes(size)}. The limit is '
        '${formatBytes(maxBytes)}.';
  }
  return null;
}

/// Suggests a title from a file name: "CSC301_week-3 (1).pdf" -> "CSC301 week 3".
String titleFromFileName(String name) {
  var base = name;
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
  base = base.replaceAll(RegExp(r'[_\-]+'), ' ');
  base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (base.length > 120) base = base.substring(0, 120).trim();
  return base;
}

final _codeInName = RegExp(
  r'(?:^|[^A-Za-z])([A-Za-z]{3})[\s_\-]?(\d{3})(?!\d)',
);

/// Finds a course code inside a file name, such as "csc_301 notes.pdf".
String? courseCodeFromFileName(String name) {
  final match = _codeInName.firstMatch(name);
  if (match == null) return null;
  return '${match.group(1)!.toUpperCase()} ${match.group(2)}';
}

/// Guesses the type from words in a file name.
ItemType typeFromFileName(String name) {
  final lower = name.toLowerCase();
  if (RegExp(r'past|\bpq\b|exam|question|test').hasMatch(lower)) {
    return ItemType.pastQuestion;
  }
  if (RegExp(r'assign|homework|\bhw\b|tutorial').hasMatch(lower)) {
    return ItemType.assignment;
  }
  return ItemType.lectureNote;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    final kb = bytes / 1024;
    return '${kb < 10 ? kb.toStringAsFixed(1) : kb.round()} KB';
  }
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "14 Oct 2026", in the viewer's local time.
String formatDate(DateTime time) {
  final t = time.toLocal();
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// "Tue 14 Oct".
String formatShortDay(DateTime time) {
  final t = time.toLocal();
  return '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
}

/// "today", "yesterday", "3 days ago" or a date.
String formatRelativeDay(DateTime time, DateTime now) {
  final a = time.toLocal();
  final b = now.toLocal();
  final days = DateTime(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime(a.year, a.month, a.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  return formatDate(time);
}

/// Pulls a shelf id out of a pasted link or a bare id.
String? shelfIdFromInput(String raw) {
  final value = raw.trim();
  final match = RegExp(r'/s/([2-9a-hj-km-np-z]{6,24})').firstMatch(value);
  if (match != null) return match.group(1);
  if (RegExp(r'^[2-9a-hj-km-np-z]{6,24}$').hasMatch(value)) return value;
  return null;
}
