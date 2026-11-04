import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// An API call that failed, with a message fit to show.
class ApiException implements Exception {
  const ApiException(this.status, this.message, {this.field, this.code});

  /// HTTP status, or 0 when the server could not be reached.
  final int status;
  final String message;

  /// The request field the server rejected, if any.
  final String? field;

  /// The server's error code, such as `ALREADY_CLAIMED`.
  final String? code;

  bool get isNotFound => status == 404;

  /// Nobody is signed in, or the sign-in has ended.
  bool get isSignedOut => status == 401;

  /// Signed in, but the shelf belongs to another account.
  bool get isOtherOwner => status == 403;
  bool get isForbidden => status == 401 || status == 403;
  bool get isOffline => status == 0;

  @override
  String toString() => message;
}

/// Client for the Lectern metadata API.
///
/// Requests go to the app's own origin, so the browser attaches the rep's
/// `HttpOnly` session cookie by itself; this class never sees it.
class LecternApi {
  LecternApi({
    required this.baseUrl,
    http.Client? client,
    this.onSignedOut,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

  /// Called when the server answers 401: the sign-in has ended.
  void Function()? onSignedOut;

  final Duration timeout;

  Map<String, String> _headers({bool json = false}) => {
    'accept': 'application/json',
    if (json) 'content-type': 'application/json',
  };

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(method, baseUrl.resolve(path))
      ..headers.addAll(_headers(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        0,
        'The server took too long to answer. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        0,
        'You seem to be offline. Check your connection and try again.',
      );
    }
    Map<String, Object?>? json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) json = decoded;
    } catch (_) {
      json = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (json == null) {
        throw ApiException(
          response.statusCode,
          'The server sent an unreadable reply.',
        );
      }
      return json;
    }
    if (response.statusCode == 401) onSignedOut?.call();
    final error = json?['error'];
    if (error is Map) {
      throw ApiException(
        response.statusCode,
        error['message'] is String
            ? error['message'] as String
            : 'Request failed.',
        field: error['field'] is String ? error['field'] as String : null,
        code: error['status'] is String ? error['status'] as String : null,
      );
    }
    throw ApiException(
      response.statusCode,
      response.statusCode >= 500
          ? 'The server had a problem. Try again in a moment.'
          : 'Request failed (HTTP ${response.statusCode}).',
    );
  }

  Future<AppConfig> config() async =>
      AppConfig.fromJson(await _send('GET', '/api/config'));

  Future<CreatedShelf> createShelf(ShelfDraft draft) async =>
      CreatedShelf.fromJson(
        await _send('POST', '/api/shelves', body: draft.toJson()),
      );

  /// The signed-in rep's shelves, newest first.
  Future<List<Shelf>> myShelves() async {
    final json = await _send('GET', '/api/my/shelves');
    return (json['shelves'] as List? ?? const [])
        .map((e) => Shelf.fromJson(e as Map<String, Object?>))
        .toList();
  }

  Future<ShelfPage> shelf(String shelfId) async =>
      ShelfPage.fromJson(await _send('GET', '/api/shelves/$shelfId'));

  /// Every file on the shelf, hidden ones too. Needs the owner's sign-in.
  Future<ShelfPage> manage(String shelfId) async =>
      ShelfPage.fromJson(await _send('GET', '/api/shelves/$shelfId/manage'));

  Future<Shelf> updateShelf(String shelfId, ShelfDraft draft) async {
    final json = await _send(
      'PATCH',
      '/api/shelves/$shelfId',
      body: draft.toJson(),
    );
    return Shelf.fromJson(json['shelf'] as Map<String, Object?>);
  }

  /// Asks the server to list a Blob object the rep's wallet just stored
  /// (and, for a batch, the quilt patch of each file). The server checks it
  /// on Sui first.
  Future<void> claimUpload(
    String shelfId, {
    required String objectId,
    List<String> patchIds = const [],
  }) => _send(
    'POST',
    '/api/shelves/$shelfId/uploads',
    body: {'objectId': objectId, if (patchIds.isNotEmpty) 'patchIds': patchIds},
  );

  Future<Item> createItem(
    String shelfId, {
    required String blobId,
    String? patchId,
    required String fileName,
    required ItemDraft draft,
  }) async {
    final json = await _send(
      'POST',
      '/api/shelves/$shelfId/items',
      body: {
        if (patchId != null) 'patchId': patchId else 'blobId': blobId,
        'fileName': fileName,
        ...draft.toJson(),
      },
    );
    return Item.fromJson(json['item'] as Map<String, Object?>);
  }

  Future<ItemPage> item(String shelfId, String itemId) async =>
      ItemPage.fromJson(
        await _send('GET', '/api/shelves/$shelfId/items/$itemId'),
      );

  Future<Item> updateItem(
    String shelfId,
    String itemId,
    Map<String, Object?> changes,
  ) async {
    final json = await _send(
      'PATCH',
      '/api/shelves/$shelfId/items/$itemId',
      body: changes,
    );
    return Item.fromJson(json['item'] as Map<String, Object?>);
  }
}
