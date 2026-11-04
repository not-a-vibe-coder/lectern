import 'dart:async';
import 'dart:typed_data';

import 'browser.dart';

/// Used on the Dart VM (tests). Records what the app asked for.
class StubBrowser implements BrowserBridge {
  StubBrowser({
    this.origin = 'http://localhost:8091',
    Uri? initialUrl,
    KeyValueStore? local,
    KeyValueStore? session,
    this.canShare = false,
    this.allowNewTabs = true,
  }) : initialUrl = initialUrl ?? Uri.parse('http://localhost:8091/'),
       local = local ?? MemoryStore(),
       session = session ?? MemoryStore();

  @override
  final String origin;
  @override
  final Uri initialUrl;
  @override
  final KeyValueStore local;
  @override
  final KeyValueStore session;
  @override
  bool canShare;
  bool allowNewTabs;

  final downloads = <({String fileName, int size, String mimeType})>[];
  final opened = <String>[];
  final openedBytes = <String>[];
  final shared = <String>[];
  final replaced = <String>[];
  List<PickedFile> nextPick = [];
  final _drops = StreamController<List<PickedFile>>.broadcast();

  void drop(List<PickedFile> files) => _drops.add(files);

  @override
  Future<List<PickedFile>> pickFiles({
    required List<String> accept,
    bool multiple = true,
  }) async {
    final picked = nextPick;
    nextPick = [];
    return picked;
  }

  @override
  Stream<List<PickedFile>> get droppedFiles => _drops.stream;

  @override
  void download(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) => downloads.add((
    fileName: fileName,
    size: bytes.length,
    mimeType: mimeType,
  ));

  @override
  bool openInNewTab(Uint8List bytes, {required String mimeType}) {
    if (!allowNewTabs) return false;
    openedBytes.add(mimeType);
    return true;
  }

  @override
  void openUrl(String url, {bool newTab = true}) => opened.add(url);

  @override
  Future<bool> share({
    required String title,
    required String text,
    required String url,
  }) async {
    shared.add(url);
    return true;
  }

  @override
  void replaceUrl(String url) => replaced.add(url);
}

BrowserBridge createBridge() => StubBrowser();
