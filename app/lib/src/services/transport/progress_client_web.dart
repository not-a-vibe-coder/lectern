import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'progress_client.dart';

/// Browser version built on XMLHttpRequest, which (unlike fetch) reports
/// upload progress.
class XhrProgressClient extends ProgressClient {
  web.XMLHttpRequest? _current;
  bool _aborted = false;

  @override
  bool get aborted => _aborted;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    if (_aborted) throw http.ClientException('Request cancelled.', request.url);

    final xhr = web.XMLHttpRequest();
    _current = xhr;
    xhr.open(request.method, request.url.toString(), true);
    xhr.responseType = 'arraybuffer';
    request.headers.forEach((name, value) {
      // The browser sets these itself and refuses to let scripts set them.
      final lower = name.toLowerCase();
      if (lower == 'content-length' || lower == 'host') return;
      xhr.setRequestHeader(name, value);
    });

    final completer = Completer<http.StreamedResponse>();
    void fail(String message) {
      if (!completer.isCompleted) {
        completer.completeError(http.ClientException(message, request.url));
      }
    }

    xhr.upload.addEventListener(
      'progress',
      (web.ProgressEvent e) {
        if (e.lengthComputable) onSendProgress?.call(e.loaded, e.total);
      }.toJS,
    );
    xhr.addEventListener(
      'progress',
      (web.ProgressEvent e) {
        onReceiveProgress?.call(e.loaded, e.lengthComputable ? e.total : null);
      }.toJS,
    );
    xhr.addEventListener(
      'load',
      (web.Event _) {
        final response = xhr.response;
        final body = response != null && response.isA<JSArrayBuffer>()
            ? (response as JSArrayBuffer).toDart.asUint8List()
            : Uint8List(0);
        if (!completer.isCompleted) {
          completer.complete(
            http.StreamedResponse(
              Stream.value(body),
              xhr.status,
              contentLength: body.length,
              request: request,
              headers: _parseHeaders(xhr.getAllResponseHeaders()),
              reasonPhrase: xhr.statusText,
            ),
          );
        }
      }.toJS,
    );
    xhr.addEventListener(
      'error',
      (web.Event _) {
        fail('Network error.');
      }.toJS,
    );
    xhr.addEventListener(
      'abort',
      (web.Event _) {
        fail('Request cancelled.');
      }.toJS,
    );
    xhr.addEventListener(
      'timeout',
      (web.Event _) {
        fail('Request timed out.');
      }.toJS,
    );

    if (bytes.isEmpty) {
      xhr.send();
    } else {
      xhr.send(bytes.toJS);
    }
    return completer.future;
  }

  static Map<String, String> _parseHeaders(String raw) {
    final headers = <String, String>{};
    for (final line in raw.split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      headers[name] = headers.containsKey(name)
          ? '${headers[name]}, $value'
          : value;
    }
    return headers;
  }

  @override
  void abort() {
    _aborted = true;
    _current?.abort();
  }

  @override
  void close() {}
}

ProgressClient createProgressClient() => XhrProgressClient();
