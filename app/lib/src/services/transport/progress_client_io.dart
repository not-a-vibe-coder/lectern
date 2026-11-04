import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'progress_client.dart';

/// Dart VM version, used by the live end-to-end test and on desktop.
class IoProgressClient extends ProgressClient {
  IoProgressClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;
  bool _aborted = false;

  @override
  bool get aborted => _aborted;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_aborted) throw http.ClientException('Request cancelled.', request.url);
    final bytes = await request.finalize().toBytes();
    final outgoing = http.StreamedRequest(request.method, request.url)
      ..headers.addAll(request.headers)
      ..contentLength = bytes.length;
    unawaited(_pump(bytes, outgoing));
    final response = await _inner.send(outgoing);
    final total = response.contentLength;
    var received = 0;
    final stream = response.stream.map((chunk) {
      received += chunk.length;
      onReceiveProgress?.call(received, total);
      return chunk;
    });
    return http.StreamedResponse(
      stream,
      response.statusCode,
      contentLength: total,
      request: request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      isRedirect: response.isRedirect,
    );
  }

  Future<void> _pump(Uint8List bytes, http.StreamedRequest outgoing) async {
    const chunk = 64 * 1024;
    var sent = 0;
    while (sent < bytes.length && !_aborted) {
      final end = sent + chunk > bytes.length ? bytes.length : sent + chunk;
      outgoing.sink.add(Uint8List.sublistView(bytes, sent, end));
      sent = end;
      onSendProgress?.call(sent, bytes.length);
      await Future<void>.delayed(Duration.zero);
    }
    await outgoing.sink.close();
  }

  @override
  void abort() {
    _aborted = true;
    _inner.close();
  }

  @override
  void close() => _inner.close();
}

ProgressClient createProgressClient() => IoProgressClient();
