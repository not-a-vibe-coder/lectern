import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser.dart';

extension type _ShareData._(JSObject _) implements JSObject {
  external factory _ShareData({String title, String text, String url});
}

extension on web.Navigator {
  @JS('share')
  external JSPromise<JSAny?> _share(_ShareData data);
}

class _WebStore implements KeyValueStore {
  _WebStore(this._storage);
  final web.Storage? Function() _storage;

  // Storage can throw in private modes or when disabled; treat it as empty.
  @override
  String? get(String key) {
    try {
      return _storage()?.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  void set(String key, String value) {
    try {
      _storage()?.setItem(key, value);
    } catch (_) {}
  }

  @override
  void remove(String key) {
    try {
      _storage()?.removeItem(key);
    } catch (_) {}
  }
}

PickedFile _picked(web.File file) => PickedFile(
  name: file.name,
  size: file.size,
  mimeType: file.type,
  read: () async {
    final buffer = await file.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  },
);

List<PickedFile> _fromList(web.FileList? list) {
  if (list == null) return const [];
  return [
    for (var i = 0; i < list.length; i++)
      if (list.item(i) case final web.File file) _picked(file),
  ];
}

class WebBrowser implements BrowserBridge {
  WebBrowser() {
    // Allow dropping files anywhere on the page.
    web.document.addEventListener(
      'dragover',
      (web.Event e) {
        e.preventDefault();
      }.toJS,
    );
    web.document.addEventListener(
      'drop',
      (web.Event e) {
        e.preventDefault();
        final files = _fromList((e as web.DragEvent).dataTransfer?.files);
        if (files.isNotEmpty) _drops.add(files);
      }.toJS,
    );
  }

  final _drops = StreamController<List<PickedFile>>.broadcast();

  @override
  late final String origin = web.window.location.origin;

  @override
  // Read when the bridge is created in main(), before any route is shown:
  // the loading screen's navigator rewrites the address bar to `/`, so a
  // lazy read would turn every deep link into the home page.
  final Uri initialUrl = Uri.parse(web.window.location.href);

  @override
  late final KeyValueStore local = _WebStore(() => web.window.localStorage);

  @override
  late final KeyValueStore session = _WebStore(() => web.window.sessionStorage);

  @override
  Stream<List<PickedFile>> get droppedFiles => _drops.stream;

  @override
  Future<List<PickedFile>> pickFiles({
    required List<String> accept,
    bool multiple = true,
  }) {
    final completer = Completer<List<PickedFile>>();
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'file'
      ..multiple = multiple
      ..accept = accept.join(',');
    input.style.display = 'none';
    web.document.body?.append(input);
    void finish(List<PickedFile> files) {
      if (!completer.isCompleted) completer.complete(files);
      input.remove();
    }

    input.addEventListener(
      'change',
      (web.Event _) {
        finish(_fromList(input.files));
      }.toJS,
    );
    input.addEventListener(
      'cancel',
      (web.Event _) {
        finish(const []);
      }.toJS,
    );
    input.click();
    return completer.future;
  }

  String _blobUrl(Uint8List bytes, String mimeType) {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    // Give the browser time to start the download or render the tab.
    Timer(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
    return url;
  }

  @override
  void download(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) {
    final url = _blobUrl(bytes, mimeType);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = fileName
      ..rel = 'noopener';
    anchor.style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }

  @override
  bool openInNewTab(Uint8List bytes, {required String mimeType}) {
    final url = _blobUrl(bytes, mimeType);
    final opened = web.window.open(url, '_blank');
    return opened != null;
  }

  @override
  void openUrl(String url, {bool newTab = true}) {
    if (newTab) {
      web.window.open(url, '_blank', 'noopener');
    } else {
      web.window.location.assign(url);
    }
  }

  @override
  bool get canShare => web.window.navigator.has('share');

  @override
  Future<bool> share({
    required String title,
    required String text,
    required String url,
  }) async {
    try {
      await web.window.navigator
          ._share(_ShareData(title: title, text: text, url: url))
          .toDart;
      return true;
    } catch (_) {
      // Dismissed or not allowed.
      return false;
    }
  }

  @override
  void replaceUrl(String url) {
    web.window.history.replaceState(null, '', url);
  }
}

BrowserBridge createBridge() => WebBrowser();
