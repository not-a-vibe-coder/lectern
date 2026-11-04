import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:sui_auth/sui_auth.dart' hide normalizeSuiAddress;
import 'package:walrus_blob_check/walrus_blob_check.dart';

import 'api.dart';
import 'auth.dart';
import 'http_utils.dart';
import 'keys.dart';
import 'models.dart';
import 'sniff.dart';

/// `POST /api/shelves/<id>/uploads`: list files a rep stored on Walrus with
/// their own wallet.
///
/// The browser stores the file itself (Dartus's `WalrusWriter`: the rep's
/// wallet pays and owns the Blob object), then posts only the Blob object
/// ID, plus the quilt patch IDs when several files went up together. None
/// of it is trusted. Before anything is listed, [WalrusBlobChecker] reads
/// the object on Sui: it must be a certified Walrus blob owned by the
/// signed-in rep. Size, blob ID and storage epochs come from the chain, and
/// the file type from the file's first bytes on the aggregator.
///
/// ```json
/// {"objectId": "0x…"}                          // one file, one blob
/// {"objectId": "0x…", "patchIds": ["…", "…"]}  // a batch, one quilt
/// ```
///
/// Answers 201 with `{"uploads": [...]}`. Items are then created with the
/// blob ID (single blob) or the patch ID (file in a quilt).
class BlobClaims {
  BlobClaims(this.ctx, this.checker, {http.Client? client})
    : _client = client ?? http.Client(),
      _limiter = RateLimiter(
        ctx.config.claimLimitPerHour,
        const Duration(hours: 1),
      );

  final AppContext ctx;
  final WalrusBlobChecker checker;
  final http.Client _client;
  final RateLimiter _limiter;

  /// Files in one batch. A quilt holds a few hundred at most; a shelf's
  /// upload desk sends far fewer.
  static const maxPatches = 100;

  /// How much of each file is read to tell its type. Enough for every
  /// signature, and for the first entries of a DOCX or PPTX ZIP.
  static const sniffBytes = 64 * 1024;

  Future<Response> claim(Request request, String shelfId) async {
    final owner = request.suiAddress;
    if (owner == null) {
      return errorResponse(
        401,
        'Sign in with your Sui wallet to add files. Your sign-in may have '
        'ended.',
      );
    }
    final shelf = isValidId(shelfId) ? ctx.store.getShelf(shelfId) : null;
    if (shelf == null) {
      return errorResponse(404, 'This shelf does not exist.');
    }
    final denied = requireOwner(request, shelf);
    if (denied != null) return denied;

    final body = await readJsonObject(request);
    final objectId = body['objectId'];
    if (objectId is! String || !_objectId.hasMatch(objectId)) {
      return errorResponse(400, 'objectId must be a Sui object ID.');
    }
    final patches = body['patchIds'];
    final patchIds = <String>[];
    if (patches != null) {
      if (patches is! List ||
          patches.isEmpty ||
          patches.length > maxPatches ||
          patches.any((p) => p is! String || p.length > 64)) {
        return errorResponse(
          400,
          'patchIds must list 1 to $maxPatches quilt patch IDs.',
        );
      }
      patchIds.addAll(patches.cast<String>());
      if (patchIds.toSet().length != patchIds.length) {
        return errorResponse(400, 'patchIds lists a file twice.');
      }
      for (final patchId in patchIds) {
        try {
          quiltBlobIdOf(patchId);
        } on FormatException {
          return errorResponse(400, '$patchId is not a quilt patch ID.');
        }
      }
    }

    final id = normalizeSuiAddress(objectId);
    final repeated = _existingClaim(id, shelfId, patchIds);
    if (repeated != null) return repeated;

    // Abuse limit: each claim costs a GraphQL call and aggregator reads.
    if (!_limiter.allow(owner, ctx.clock())) {
      return errorResponse(
        429,
        'Too many files added in the last hour. Try again later.',
      );
    }

    if (ctx.store.isObjectClaimed(id) ||
        patchIds.any(ctx.store.isPatchClaimed)) {
      return _alreadyClaimed();
    }

    try {
      final blob = await checker.check(id, owner: owner);
      final files = patchIds.isEmpty
          ? [await _single(blob)]
          : [for (final patchId in patchIds) await _patch(blob, patchId)];
      final problem = files.whereType<Response>().firstOrNull;
      if (problem != null) return problem;

      final now = ctx.clock();
      final expiresAt = blob.epochInfo?.estimateExpiry(blob.endEpoch);
      final uploads = [
        for (final file in files.cast<_File>())
          UploadRecord(
            shelfId: shelf.id,
            ownerAddress: blob.owner,
            blobId: blob.blobId,
            patchId: file.patchId,
            size: file.size,
            kind: file.kind,
            endEpoch: blob.endEpoch,
            startEpoch: blob.startEpoch,
            objectId: blob.objectId,
            expiresAt: expiresAt,
            createdAt: now,
          ),
      ];
      if (!ctx.store.recordClaim(uploads)) {
        return _existingClaim(id, shelfId, patchIds) ?? _alreadyClaimed();
      }
      return jsonResponse({
        'uploads': [for (final u in uploads) u.toJson()],
      }, status: 201);
    } on BlobCheckException catch (e) {
      return _checkProblem(e);
    }
  }

  Response? _existingClaim(
    String objectId,
    String shelfId,
    List<String> patches,
  ) {
    final uploads = ctx.store.uploadsForObject(objectId);
    if (uploads.isEmpty) return null;
    if (uploads.any((u) => u.shelfId != shelfId) ||
        (patches.isEmpty
            ? uploads.length != 1 || uploads.single.patchId != null
            : uploads.length != patches.length ||
                  uploads.any((u) => !patches.contains(u.patchId)))) {
      return _alreadyClaimed();
    }
    final ordered = patches.isEmpty
        ? uploads
        : [
            for (final patch in patches)
              uploads.singleWhere((u) => u.patchId == patch),
          ];
    return jsonResponse({
      'uploads': [for (final u in ordered) u.toJson()],
    }, status: 201);
  }

  /// A whole blob holding one file.
  Future<Object> _single(StoredBlob blob) async {
    if (blob.size > ctx.config.maxUploadBytes) return _tooLarge();
    final kind = await _kindOf(
      (length) => checker.readStart(blob.blobId, length: length),
      blob.size,
    );
    return kind is FileKind
        ? _File(patchId: null, size: blob.size, kind: kind)
        : kind;
  }

  /// One file of a quilt: it must point into the blob that was checked.
  Future<Object> _patch(StoredBlob blob, String patchId) async {
    if (quiltBlobIdOf(patchId) != blob.blobId) {
      return errorResponse(
        400,
        'A file in this batch is not part of the stored blob.',
        code: 'PATCH_NOT_IN_QUILT',
      );
    }
    final size = await _patchSize(patchId);
    if (size > ctx.config.maxUploadBytes) return _tooLarge();
    final kind = await _kindOf(
      (length) => checker.readPatchStart(patchId, length: length),
      size,
    );
    return kind is FileKind
        ? _File(patchId: patchId, size: size, kind: kind)
        : kind;
  }

  /// The file's type from its first bytes, or an error response. A DOCX or
  /// PPTX is a ZIP whose entry names give it away; when the first 64 KB do
  /// not show them, the whole file (within the size limit) is read.
  Future<Object> _kindOf(
    Future<Uint8List> Function(int length) read,
    int size,
  ) async {
    if (size == 0) {
      return errorResponse(400, 'The file is empty.', code: 'EMPTY_FILE');
    }
    var bytes = await read(size < sniffBytes ? size : sniffBytes);
    var sniff = sniffFile(bytes);
    if (!sniff.isAllowed && _isZip(bytes) && size > bytes.length) {
      bytes = await read(size);
      sniff = sniffFile(bytes);
    }
    if (!sniff.isAllowed) {
      return errorResponse(415, sniff.problem!, code: 'WRONG_FILE_TYPE');
    }
    return sniff.kind!;
  }

  static bool _isZip(Uint8List b) =>
      b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 3 && b[3] == 4;

  /// The size of one file in a quilt. Sui records the quilt's size, not each
  /// file's, so the aggregator is asked: a one-byte range answer names the
  /// total. An aggregator that ignores ranges sends the file, which is
  /// counted up to the size limit.
  Future<int> _patchSize(String patchId) async {
    final base = checker.aggregatorUrl;
    final uri = base.replace(
      path:
          '${base.path.replaceFirst(RegExp(r'/$'), '')}'
          '/v1/blobs/by-quilt-patch-id/${Uri.encodeComponent(patchId)}',
    );
    final request = http.Request('GET', uri)..headers['range'] = 'bytes=0-0';
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(checker.timeout);
    } on Object catch (e) {
      throw BlobCheckException(
        BlobCheckProblem.unavailable,
        'Aggregator unreachable: $e',
      );
    }
    if (response.statusCode == 404) {
      await response.stream.listen(null).cancel();
      throw BlobCheckException(
        BlobCheckProblem.notFound,
        'The aggregator does not have file $patchId yet.',
      );
    }
    if (response.statusCode == 206) {
      await response.stream.listen(null).cancel();
      final range = RegExp(
        r'^bytes 0-0/(\d+)$',
      ).firstMatch(response.headers['content-range'] ?? '');
      final total = int.tryParse(range?.group(1) ?? '');
      if (total != null && total > 0) return total;
      throw BlobCheckException(
        BlobCheckProblem.unavailable,
        'The aggregator did not say how large file $patchId is.',
      );
    }
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw BlobCheckException(
        BlobCheckProblem.unavailable,
        'Aggregator answered ${response.statusCode} for file $patchId.',
      );
    }
    final limit = ctx.config.maxUploadBytes;
    var counted = 0;
    try {
      await for (final chunk in response.stream.timeout(checker.timeout)) {
        counted += chunk.length;
        if (counted > limit) break;
      }
    } on Object catch (e) {
      throw BlobCheckException(
        BlobCheckProblem.unavailable,
        'Reading file $patchId failed: $e',
      );
    }
    return counted;
  }

  Response _tooLarge() => errorResponse(
    413,
    'Files can be at most ${ctx.config.maxUploadMb} MB here.',
    code: 'FILE_TOO_LARGE',
  );

  static Response _alreadyClaimed() => errorResponse(
    409,
    'These files are already on a shelf.',
    code: 'ALREADY_CLAIMED',
  );

  static Response _checkProblem(BlobCheckException e) => switch (e.problem) {
    // A full node can trail the wallet by a moment; the app retries.
    BlobCheckProblem.notFound => errorResponse(
      404,
      'Walrus or Sui does not show this file yet. Try again in a moment.',
      code: 'BLOB_NOT_FOUND',
    ),
    BlobCheckProblem.notCertified => errorResponse(
      409,
      'This file is not certified on Walrus yet. Finish storing it first.',
      code: 'BLOB_NOT_CERTIFIED',
    ),
    BlobCheckProblem.expired => errorResponse(
      410,
      'This file’s storage period has ended. Store it again before adding it.',
      code: 'BLOB_EXPIRED',
    ),
    BlobCheckProblem.notWalrusBlob ||
    BlobCheckProblem.wrongOwner => errorResponse(
      403,
      'This Walrus blob does not belong to your signed-in account.',
      code: 'NOT_YOUR_BLOB',
    ),
    BlobCheckProblem.unavailable => errorResponse(
      502,
      'Could not check the file on Sui. Try again.',
      code: 'SUI_UNAVAILABLE',
    ),
  };

  static final _objectId = RegExp(r'^0x[0-9a-fA-F]{1,64}$');
}

class _File {
  const _File({required this.patchId, required this.size, required this.kind});
  final String? patchId;
  final int size;
  final FileKind kind;
}
