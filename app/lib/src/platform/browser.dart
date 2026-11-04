import 'dart:async';
import 'dart:typed_data';

import 'browser_stub.dart'
    if (dart.library.js_interop) 'browser_web.dart'
    as impl;

/// A file the user picked or dropped. Bytes are read only when needed, so a
/// queue of large files does not sit in memory.
class PickedFile {
  PickedFile({
    required this.name,
    required this.size,
    required this.mimeType,
    required this.read,
  });

  final String name;
  final int size;
  final String mimeType;

  /// Reads the file's bytes. Prefer [readBytes].
  final Future<Uint8List> Function() read;

  Future<Uint8List> readBytes() => read();
}

/// Simple string storage (localStorage or sessionStorage on the web).
abstract class KeyValueStore {
  String? get(String key);
  void set(String key, String value);
  void remove(String key);
}

class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  String? get(String key) => values[key];
  @override
  void set(String key, String value) => values[key] = value;
  @override
  void remove(String key) => values.remove(key);
}

/// Everything the app needs from the browser, behind one interface so
/// widget tests can run on the Dart VM with a fake.
abstract class BrowserBridge {
  /// Origin of the page, such as "https://lectern.example".
  String get origin;

  /// The URL the page was opened with (including any #fragment).
  Uri get initialUrl;

  KeyValueStore get local;
  KeyValueStore get session;

  /// Opens the system file picker.
  Future<List<PickedFile>> pickFiles({
    required List<String> accept,
    bool multiple = true,
  });

  /// Files dropped anywhere on the page (desktop).
  Stream<List<PickedFile>> get droppedFiles;

  /// Saves bytes as a download with [fileName].
  void download(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  });

  /// Opens bytes in a new tab from a blob URL. Returns false when the browser
  /// blocked the new tab.
  bool openInNewTab(Uint8List bytes, {required String mimeType});

  /// Opens a URL, in a new tab when [newTab].
  void openUrl(String url, {bool newTab = true});

  /// Whether the Web Share API is available (mostly phones).
  bool get canShare;
  Future<bool> share({
    required String title,
    required String text,
    required String url,
  });

  /// Replaces the address bar URL without navigating.
  void replaceUrl(String url);
}

BrowserBridge createBrowserBridge() => impl.createBridge();
