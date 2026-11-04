import 'dart:async';
import 'dart:typed_data';

import 'package:dartus/dartus.dart';
import 'package:http/http.dart' as http;
import 'package:upload_recovery/walrus_recovery.dart';

import 'transport/progress_client.dart';

/// What a paid write stored: one Blob object owned by the rep's wallet.
class StoredUpload {
  const StoredUpload({
    required this.objectId,
    required this.blobId,
    required this.endEpoch,
    this.patchIds = const [],
  });

  /// The Sui `Blob` object; the server checks it before listing anything.
  final String objectId;
  final String blobId;
  final int endEpoch;

  /// For a batch (one quilt): the quilt patch ID of each file, in the order
  /// the files were given. Empty for a single blob.
  final List<String> patchIds;
}

/// What storing a batch would cost, from the chain, before any approval.
class StorageEstimate {
  const StorageEstimate({required this.wal, required this.relayTipMist});

  /// WAL for storage and registration, in FROST (10^9 per WAL).
  final BigInt wal;

  /// SUI tip for the upload relay, in MIST. Gas comes on top.
  final BigInt relayTipMist;

  StorageEstimate operator +(StorageEstimate other) => StorageEstimate(
    wal: wal + other.wal,
    relayTipMist: relayTipMist + other.relayTipMist,
  );
}

/// One write the rep's wallet pays for. Keep it after a failure: [run]
/// continues where it stopped, so nothing is registered or paid twice.
abstract class StorageWrite {
  int get epochs;

  /// True once the payment (register transaction) went through.
  bool get paid;

  Future<StoredUpload> run(
    WalrusTransactionSigner signer, {
    required void Function(WalrusWriteStage stage) onStage,
    ProgressCallback? onProgress,
  });
}

/// Stores files on Walrus, paid for by the person's wallet. A small seam so
/// widget tests can run without Sui, the relay or WebAssembly.
abstract class WalletStorage {
  Future<StorageEstimate> estimate({required int size, required int epochs});

  /// One file as one blob: two approvals.
  StorageWrite single(Uint8List data, {required int epochs});

  /// Several files as one quilt: still two approvals and one storage fee.
  StorageWrite batch(List<QuiltBlob> files, {required int epochs});

  void close();
}

/// [WalletStorage] with Dartus's [WalrusWriter]: the blob ID is computed in
/// the browser (walrus-wasm in a Web Worker), the wallet registers and pays,
/// the bytes go to the upload relay, and the wallet certifies.
class DartusWalletStorage implements WalletStorage {
  DartusWalletStorage({
    required WalrusNetwork network,
    ProgressClientFactory? clientFactory,
    Duration relayTimeout = const Duration(minutes: 15),
  }) : _transport = _RelayTransport(clientFactory ?? createProgressClient) {
    _writer = WalrusWriter(
      network: network,
      // Dartus's relay client waits 2 minutes by default; a 25 MB file on
      // mobile data can take longer to send.
      relay: UploadRelayClient(
        host: network.defaultUploadRelayUrl,
        httpClient: _transport,
        timeout: relayTimeout,
      ),
    );
  }

  final _RelayTransport _transport;
  late final WalrusWriter _writer;

  @override
  Future<StorageEstimate> estimate({
    required int size,
    required int epochs,
  }) async {
    final estimate = await _writer.estimate(size: size, epochs: epochs);
    return StorageEstimate(
      wal: estimate.cost.total,
      relayTipMist: estimate.relayTip,
    );
  }

  @override
  StorageWrite single(Uint8List data, {required int epochs}) =>
      _SingleWrite(_writer, data, epochs, _transport);

  @override
  StorageWrite batch(List<QuiltBlob> files, {required int epochs}) =>
      _BatchWrite(_writer, files, epochs, _transport);

  @override
  void close() {
    _writer.close();
    _transport.close();
  }
}

class _SingleWrite implements StorageWrite, RecoveryCheckpointSource {
  _SingleWrite(
    WalrusWriter writer,
    Uint8List data,
    int epochs,
    this.transport,
  ) {
    flow = writer.writeFlow(
      data,
      epochs: epochs,
      onCheckpoint: (value) async => await onCheckpoint?.call(value),
    );
  }
  late final WalrusWriteFlow flow;
  @override
  CheckpointHandler? onCheckpoint;
  @override
  WalrusWriteCheckpoint get checkpoint => flow.checkpoint;
  final _RelayTransport transport;

  @override
  int get epochs => flow.epochs;

  @override
  bool get paid => flow.registerDigest != null;

  @override
  Future<StoredUpload> run(
    WalrusTransactionSigner signer, {
    required void Function(WalrusWriteStage stage) onStage,
    ProgressCallback? onProgress,
  }) async {
    try {
      final result = await flow.run(
        signer,
        onStage: (stage) {
          if (stage == WalrusWriteStage.uploading) {
            transport.listen(flow.blobId, onProgress);
          }
          onStage(stage);
        },
      );
      return StoredUpload(
        objectId: result.blobObjectId,
        blobId: result.blobId,
        endEpoch: result.endEpoch,
      );
    } finally {
      transport.listen(flow.blobId, null);
    }
  }
}

class _BatchWrite implements StorageWrite, RecoveryCheckpointSource {
  _BatchWrite(
    WalrusWriter writer,
    List<QuiltBlob> files,
    int epochs,
    this.transport,
  ) {
    flow = writer.writeFilesFlow(
      files,
      epochs: epochs,
      onCheckpoint: (value) async => await onCheckpoint?.call(value),
    );
  }
  late final WalrusWriteFilesFlow flow;
  @override
  CheckpointHandler? onCheckpoint;
  @override
  WalrusWriteCheckpoint get checkpoint => flow.checkpoint;
  final _RelayTransport transport;

  @override
  int get epochs => flow.epochs;

  @override
  bool get paid => flow.blobFlow?.registerDigest != null;

  @override
  Future<StoredUpload> run(
    WalrusTransactionSigner signer, {
    required void Function(WalrusWriteStage stage) onStage,
    ProgressCallback? onProgress,
  }) async {
    try {
      final result = await flow.run(
        signer,
        onStage: (stage) {
          if (stage == WalrusWriteStage.uploading) {
            transport.listen(flow.blobFlow?.blobId, onProgress);
          }
          onStage(stage);
        },
      );
      final byName = {for (final f in result.files) f.identifier: f.patchId};
      return StoredUpload(
        objectId: result.quilt.blobObjectId,
        blobId: result.quilt.blobId,
        endEpoch: result.quilt.endEpoch,
        patchIds: [for (final f in flow.files) byName[f.identifier]!],
      );
    } finally {
      transport.listen(flow.blobFlow?.blobId, null);
    }
  }
}

/// The relay's HTTP client: each request gets its own XHR, and an upload
/// reports progress to whoever is storing that blob (matched by the
/// `blob_id` query parameter the relay requires).
class _RelayTransport extends http.BaseClient {
  _RelayTransport(this._factory);
  final ProgressClientFactory _factory;
  final _listeners = <String, ProgressCallback>{};

  void listen(String? blobId, ProgressCallback? onProgress) {
    if (blobId == null) return;
    if (onProgress == null) {
      _listeners.remove(blobId);
    } else {
      _listeners[blobId] = onProgress;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final client = _factory()
      ..onSendProgress = _listeners[request.url.queryParameters['blob_id']];
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
