import 'dart:async';
import 'dart:typed_data';

import 'package:dartus/dartus.dart';
import 'package:http/http.dart' as http;

import 'transport/progress_client.dart';

/// A failed Walrus operation, with a message fit to show a student or rep.
class WalrusFailure implements Exception {
  const WalrusFailure(
    this.message, {
    this.retryable = true,
    this.notFound = false,
    this.status,
  });

  final String message;
  final bool retryable;
  final bool notFound;
  final int? status;

  @override
  String toString() => message;
}

/// Reads files with Dartus (`getBlob`, and `getQuiltPatch` for files stored
/// in a batch), straight from the aggregator named in the server config.
/// Students need no wallet for this. Writes are paid by the rep's wallet:
/// see `WalletStorage`.
class WalrusService {
  WalrusService({
    required this.aggregatorBaseUrl,
    ProgressClientFactory? clientFactory,
    this.readTimeout = const Duration(minutes: 10),
    int readCacheEntries = 6,
  }) : _factory = clientFactory ?? createProgressClient {
    _readTransport = _ReadTransport(_factory);
    _reader = WalrusClient(
      // Nothing is ever published through this client.
      publisherBaseUrl: aggregatorBaseUrl,
      aggregatorBaseUrl: aggregatorBaseUrl,
      httpClient: _readTransport,
      timeout: readTimeout,
      // Blobs can be 25 MB, so keep only a few in memory.
      cacheMaxSize: readCacheEntries,
    );
  }

  final Uri aggregatorBaseUrl;
  final Duration readTimeout;
  final ProgressClientFactory _factory;
  late final _ReadTransport _readTransport;
  late final WalrusClient _reader;

  /// Reads a file: by [patchId] (`getQuiltPatch`) when it was stored in a
  /// batch, otherwise by [blobId] (`getBlob`). Repeat reads in a session
  /// come from Dartus' cache.
  Future<Uint8List> read(
    String blobId, {
    String? patchId,
    ProgressCallback? onProgress,
  }) async {
    final key = _reader.aggregatorBaseUrl
        .resolve(
          patchId != null
              ? 'v1/blobs/by-quilt-patch-id/$patchId'
              : 'v1/blobs/$blobId',
        )
        .toString();
    if (onProgress != null) _readTransport.listeners[key] = onProgress;
    try {
      return patchId != null
          ? await _reader.getQuiltPatch(patchId)
          : await _reader.getBlob(blobId);
    } catch (error) {
      throw _readFailure(error);
    } finally {
      _readTransport.listeners.remove(key);
    }
  }

  Future<void> dispose() => _reader.close();

  static WalrusFailure _readFailure(Object error) {
    if (error is WalrusApiError) {
      if (error.code == 404) {
        return const WalrusFailure(
          'Walrus no longer has this file. Its storage period may have ended.',
          retryable: false,
          notFound: true,
          status: 404,
        );
      }
      return WalrusFailure(
        'Could not fetch the file from Walrus (HTTP ${error.code}). Try again.',
        status: error.code,
      );
    }
    if (error is TimeoutException) {
      return const WalrusFailure(
        'Fetching the file took too long. Check your connection and retry.',
      );
    }
    if (error is http.ClientException) {
      return const WalrusFailure(
        'Could not reach Walrus. Check your data or Wi-Fi and retry.',
      );
    }
    return WalrusFailure('Could not fetch the file: $error');
  }
}

/// Gives each read its own transport so progress can be reported per blob,
/// while the Dartus client (and its cache) is shared.
class _ReadTransport extends http.BaseClient {
  _ReadTransport(this._factory);
  final ProgressClientFactory _factory;
  final listeners = <String, ProgressCallback>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final client = _factory()
      ..onReceiveProgress = listeners[request.url.toString()];
    try {
      final response = await client.send(request);
      final bytes = await response.stream.toBytes();
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: request,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
      );
    } finally {
      client.close();
    }
  }
}
