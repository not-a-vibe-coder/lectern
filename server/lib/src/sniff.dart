import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

/// Result of looking at a file's first bytes.
class SniffResult {
  const SniffResult.ok(FileKind this.kind) : problem = null;
  const SniffResult.rejected(String this.problem) : kind = null;

  final FileKind? kind;
  final String? problem;

  bool get isAllowed => kind != null;
}

const allowedSummary =
    'Upload a PDF, an image (PNG, JPEG, WebP or GIF), a Word document (.docx) '
    'or a PowerPoint deck (.pptx).';

/// Detects the file kind from magic bytes. The upload client always sends
/// `application/octet-stream`, so the bytes are the only reliable signal.
SniffResult sniffFile(Uint8List bytes) {
  if (bytes.isEmpty) return const SniffResult.rejected('The file is empty.');

  bool startsWith(List<int> sig, [int offset = 0]) {
    if (bytes.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[offset + i] != sig[i]) return false;
    }
    return true;
  }

  // PDF: "%PDF-" near the start (some writers put a few bytes first).
  final head = bytes.length > 1024 ? bytes.sublist(0, 1024) : bytes;
  if (_indexOf(head, ascii.encode('%PDF-')) >= 0) {
    return const SniffResult.ok(FileKind.pdf);
  }
  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return const SniffResult.ok(FileKind.png);
  }
  if (startsWith(const [0xFF, 0xD8, 0xFF])) {
    return const SniffResult.ok(FileKind.jpeg);
  }
  if (startsWith(ascii.encode('GIF87a')) ||
      startsWith(ascii.encode('GIF89a'))) {
    return const SniffResult.ok(FileKind.gif);
  }
  if (startsWith(ascii.encode('RIFF')) && startsWith(ascii.encode('WEBP'), 8)) {
    return const SniffResult.ok(FileKind.webp);
  }
  if (startsWith(const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
    return const SniffResult.rejected(
      'Older .doc and .ppt files are not supported. Save the file as .docx or '
      '.pptx, or export it to PDF.',
    );
  }
  if (startsWith(const [0x50, 0x4B, 0x03, 0x04])) {
    final names = zipEntryNames(bytes);
    if (names.any((n) => n.startsWith('word/'))) {
      return const SniffResult.ok(FileKind.docx);
    }
    if (names.any((n) => n.startsWith('ppt/'))) {
      return const SniffResult.ok(FileKind.pptx);
    }
    return const SniffResult.rejected(
      'This ZIP file is not a Word or PowerPoint document. $allowedSummary',
    );
  }
  return const SniffResult.rejected(
    'This file type is not supported. $allowedSummary',
  );
}

/// Lists entry names from a ZIP file's central directory. Falls back to
/// walking local file headers when the central directory cannot be read.
List<String> zipEntryNames(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final names = <String>[];
  // End of central directory record: at least 22 bytes, comment up to 64 KB.
  final minStart = bytes.length - 22 - 0xFFFF;
  for (var i = bytes.length - 22; i >= 0 && i >= minStart; i--) {
    if (data.getUint32(i, Endian.little) != 0x06054b50) continue;
    final count = data.getUint16(i + 10, Endian.little);
    var offset = data.getUint32(i + 16, Endian.little);
    for (var n = 0; n < count; n++) {
      if (offset + 46 > bytes.length) break;
      if (data.getUint32(offset, Endian.little) != 0x02014b50) break;
      final nameLength = data.getUint16(offset + 28, Endian.little);
      final extraLength = data.getUint16(offset + 30, Endian.little);
      final commentLength = data.getUint16(offset + 32, Endian.little);
      final start = offset + 46;
      if (start + nameLength > bytes.length) break;
      names.add(
        utf8.decode(
          bytes.sublist(start, start + nameLength),
          allowMalformed: true,
        ),
      );
      offset = start + nameLength + extraLength + commentLength;
    }
    if (names.isNotEmpty) return names;
    break;
  }
  // Fallback: local file headers in order.
  var offset = 0;
  while (offset + 30 <= bytes.length &&
      data.getUint32(offset, Endian.little) == 0x04034b50) {
    final compressed = data.getUint32(offset + 18, Endian.little);
    final nameLength = data.getUint16(offset + 26, Endian.little);
    final extraLength = data.getUint16(offset + 28, Endian.little);
    final start = offset + 30;
    if (start + nameLength > bytes.length) break;
    names.add(
      utf8.decode(
        bytes.sublist(start, start + nameLength),
        allowMalformed: true,
      ),
    );
    offset = start + nameLength + extraLength + compressed;
    if (compressed == 0) break; // Streamed entry; sizes live after the data.
  }
  return names;
}

int _indexOf(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
