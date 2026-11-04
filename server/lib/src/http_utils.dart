import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

const jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};

Response jsonResponse(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: jsonHeaders);

/// Errors use the same shape as Walrus publisher errors, so the Dartus client
/// parses proxy errors and API errors the same way.
Response errorResponse(
  int status,
  String message, {
  String? code,
  String? field,
}) => jsonResponse({
  'error': {
    'code': status,
    'status': code ?? _statusName(status),
    'message': message,
    'field': ?field,
  },
}, status: status);

String _statusName(int status) => switch (status) {
  400 => 'INVALID_ARGUMENT',
  401 => 'UNAUTHENTICATED',
  403 => 'PERMISSION_DENIED',
  404 => 'NOT_FOUND',
  405 => 'METHOD_NOT_ALLOWED',
  409 => 'CONFLICT',
  413 => 'PAYLOAD_TOO_LARGE',
  415 => 'UNSUPPORTED_MEDIA_TYPE',
  429 => 'RESOURCE_EXHAUSTED',
  502 => 'BAD_GATEWAY',
  503 => 'UNAVAILABLE',
  504 => 'GATEWAY_TIMEOUT',
  _ => status >= 500 ? 'INTERNAL' : 'FAILED_PRECONDITION',
};

class BadRequest implements Exception {
  BadRequest(this.message);
  final String message;
}

/// Reads a JSON object body of at most [maxBytes].
Future<Map<String, Object?>> readJsonObject(
  Request request, {
  int maxBytes = 64 * 1024,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final length = request.contentLength;
  if (length != null && length > maxBytes) {
    throw BadRequest('Request body is too large.');
  }
  final bytes = <int>[];
  final chunks = StreamIterator(request.read());
  try {
    await (() async {
      while (await chunks.moveNext()) {
        final chunk = chunks.current;
        if (bytes.length + chunk.length > maxBytes) {
          throw BadRequest('Request body is too large.');
        }
        bytes.addAll(chunk);
      }
    })().timeout(timeout);
  } on TimeoutException {
    throw BadRequest('The request took too long. Try again.');
  } finally {
    await chunks.cancel();
  }
  if (bytes.isEmpty) return {};
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // Fall through.
  }
  throw BadRequest('Request body must be a JSON object.');
}

/// Adds security headers to every response.
Middleware securityHeaders() =>
    (inner) => (request) async {
      final response = await inner(request);
      return response.change(
        headers: {
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'no-referrer',
          'x-frame-options': 'DENY',
          'permissions-policy': 'camera=(), microphone=(), geolocation=()',
          ...response.headers.containsKey('cache-control')
              ? const {}
              : const {'cache-control': 'no-cache'},
        },
      );
    };

/// Logs method, path (never the query or fragment) and status.
Middleware quietLogger(void Function(String) log) =>
    (inner) => (request) async {
      final watch = Stopwatch()..start();
      final response = await inner(request);
      log(
        '${request.method} /${request.url.path} ${response.statusCode} '
        '${watch.elapsedMilliseconds}ms',
      );
      return response;
    };
