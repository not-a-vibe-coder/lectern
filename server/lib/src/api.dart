import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sui_auth/sui_auth.dart';

import 'auth.dart';
import 'claims.dart';
import 'config.dart';
import 'http_utils.dart';
import 'keys.dart';
import 'models.dart';
import 'sniff.dart' show allowedSummary;
import 'store.dart';
import 'validation.dart';

typedef Clock = DateTime Function();

/// Shared state for the API and blob claims.
class AppContext {
  AppContext({
    required this.config,
    required this.store,
    Clock? clock,
    SuiAuth? auth,
  }) : clock = clock ?? (() => DateTime.now().toUtc()) {
    this.auth = auth ?? buildAuth(config, store, clock: this.clock);
  }

  final ServerConfig config;
  final Store store;
  final Clock clock;

  /// Sign in with Sui: nonces, signature checks and session cookies.
  late final SuiAuth auth;

  /// The public origin for links, QR codes and Open Graph tags.
  ///
  /// `PUBLIC_BASE_URL` always wins. Without it the request's `Host` header is
  /// used, or `X-Forwarded-Host`/`X-Forwarded-Proto` when `TRUST_PROXY=true`.
  /// Header values must pass [isSafeHost] and be `http`/`https`; anything else
  /// falls back to `http://localhost:<port>`, so a hostile header can never
  /// reach a link preview, a QR code or a cached page.
  Uri baseUrl(Request request) {
    final configured = config.publicBaseUrl;
    if (configured != null) return configured;
    final fallback = Uri(scheme: 'http', host: 'localhost', port: config.port);

    String? first(String? value) {
      if (value == null) return null;
      final part = value.split(',').first.trim();
      return part.isEmpty ? null : part;
    }

    final host = config.trustProxy
        ? first(request.headers['x-forwarded-host']) ??
              first(request.headers['host'])
        : first(request.headers['host']);
    final proto =
        (config.trustProxy
            ? first(request.headers['x-forwarded-proto'])
            : null) ??
        request.requestedUri.scheme;
    final hostValue = host ?? _requestedHost(request);
    if (!isSafeHost(hostValue) || !{'http', 'https'}.contains(proto)) {
      return fallback;
    }
    final colon = hostValue.indexOf(':');
    final name = colon < 0 ? hostValue : hostValue.substring(0, colon);
    final port = colon < 0 ? null : int.parse(hostValue.substring(colon + 1));
    return Uri(scheme: proto, host: name.toLowerCase(), port: port);
  }

  static String _requestedHost(Request request) {
    final uri = request.requestedUri;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  String origin(Request request) {
    final base = baseUrl(request).toString();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }
}

/// Counts events per key inside a sliding window.
class RateLimiter {
  RateLimiter(this.limit, this.window);
  final int limit;
  final Duration window;
  final _events = <String, List<DateTime>>{};

  bool allow(String key, DateTime now) {
    final cutoff = now.subtract(window);
    final list = _events.putIfAbsent(key, () => [])
      ..removeWhere((t) => t.isBefore(cutoff));
    if (list.length >= limit) return false;
    list.add(now);
    if (_events.length > 10000) {
      _events.removeWhere((_, v) => v.every((t) => t.isBefore(cutoff)));
    }
    return true;
  }
}

final _hostPattern = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?(?::[0-9]{1,5})?$',
);

/// True for `example.org`, `localhost:8091` or `10.0.0.2:80`: letters,
/// digits, dots and hyphens, an optional port, at most 255 characters.
bool isSafeHost(String? host) {
  if (host == null || host.length > 255 || !_hostPattern.hasMatch(host)) {
    return false;
  }
  if (host.contains('..')) return false;
  final colon = host.indexOf(':');
  if (colon >= 0) {
    final port = int.parse(host.substring(colon + 1));
    if (port < 1 || port > 65535) return false;
  }
  return true;
}

String clientAddress(Request request, {bool trustProxy = false}) {
  if (trustProxy) {
    final forwarded = request.headers['x-forwarded-for']
        ?.split(',')
        .first
        .trim();
    if (forwarded != null && forwarded.isNotEmpty && forwarded.length <= 64) {
      return forwarded;
    }
  }
  final info = request.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return 'unknown';
}

/// JSON API under `/api`.
class Api {
  Api(this.ctx, this.claims)
    : _createLimiter = RateLimiter(
        ctx.config.shelfCreateLimitPerHour,
        const Duration(hours: 1),
      );

  final AppContext ctx;

  /// Lists files the rep stored on Walrus with their own wallet.
  final BlobClaims claims;
  final RateLimiter _createLimiter;

  /// Shared networks (a campus Wi-Fi) get more room than one account.
  late final RateLimiter _createLimiterByNetwork = RateLimiter(
    ctx.config.shelfCreateLimitPerHour * 3,
    const Duration(hours: 1),
  );

  Store get _store => ctx.store;

  Router get router {
    final r = Router(notFoundHandler: _notFound);
    r.get('/api/config', _config);
    r.get('/api/health', (Request _) => jsonResponse({'ok': true}));
    r.get('/api/my/shelves', _myShelves);
    r.post('/api/shelves', _createShelf);
    r.get('/api/shelves/<id>', _getShelf);
    r.patch('/api/shelves/<id>', _updateShelf);
    r.get('/api/shelves/<id>/manage', _manageShelf);
    r.post('/api/shelves/<id>/uploads', claims.claim);
    r.post('/api/shelves/<id>/items', _createItem);
    r.get('/api/shelves/<id>/items/<itemId>', _getItem);
    r.patch('/api/shelves/<id>/items/<itemId>', _updateItem);
    return r;
  }

  Handler get handler => (Request request) async {
    try {
      return await router.call(request);
    } on ValidationException catch (e) {
      return errorResponse(400, e.message, field: e.field);
    } on BadRequest catch (e) {
      return errorResponse(400, e.message);
    }
  };

  Response _notFound(Request request) =>
      errorResponse(404, 'There is nothing at this address.');

  /// What the app needs to store and read files. There is no publisher:
  /// the rep's wallet pays on [suiChain], for as many epochs as they choose
  /// (the app suggests `epochs`).
  Response _config(Request request) => jsonResponse({
    'aggregatorUrl': ctx.config.aggregatorUrl.toString(),
    'network': ctx.config.network,
    'epochs': ctx.config.epochs,
    'epochDurationHours': ctx.config.epochDuration.inHours,
    'maxUploadBytes': ctx.config.maxUploadBytes,
    'publicBaseUrl': ctx.origin(request),
    'allowedTypes': FileKind.values.map((k) => k.mimeType).toList(),
    'allowedSummary': allowedSummary,
    'suiChain': ctx.config.suiChain.id,
  });

  /// The signed-in rep's shelves, on any device.
  Response _myShelves(Request request) {
    final address = request.suiAddress;
    if (address == null) {
      return errorResponse(401, 'Sign in to see your shelves.');
    }
    final shelves = _store.shelvesOwnedBy(address);
    return jsonResponse({
      'address': address,
      'shelves': [
        for (final entry in shelves)
          entry.shelf.toJson(itemCount: entry.visibleCount),
      ],
    });
  }

  Future<Response> _createShelf(Request request) async {
    // The owner is always the verified session address, never a value from
    // the request body.
    final owner = request.suiAddress;
    if (owner == null) {
      return errorResponse(
        401,
        'Sign in with your Sui wallet to create a shelf.',
      );
    }
    final now = ctx.clock();
    if (!_createLimiter.allow(owner, now) ||
        !_createLimiterByNetwork.allow(
          clientAddress(request, trustProxy: ctx.config.trustProxy),
          now,
        )) {
      return errorResponse(
        429,
        'Too many shelves created in the last hour. Try again later.',
      );
    }
    final body = await readJsonObject(request);
    final fields = _shelfFields(body);
    final shelf = _store.createShelf(
      school: fields.school,
      department: fields.department,
      level: fields.level,
      session: fields.session,
      ownerAddress: owner,
      now: now,
    );
    final origin = ctx.origin(request);
    return jsonResponse({
      'shelf': shelf.toJson(itemCount: 0),
      'publicUrl': '$origin/s/${Uri.encodeComponent(shelf.id)}',
    }, status: 201);
  }

  ({String school, String department, String level, String session})
  _shelfFields(Map<String, Object?> body) => (
    school: optionalText(body, 'school', label: 'School', max: 40),
    department: requireText(
      body,
      'department',
      label: 'Department or course',
      min: 2,
      max: 80,
    ),
    level: optionalText(body, 'level', label: 'Level', max: 24),
    session: optionalSession(body),
  );

  Response _getShelf(Request request, String id) {
    final shelf = isValidId(id) ? _store.getShelf(id) : null;
    if (shelf == null) return _shelfNotFound();
    final now = ctx.clock();
    final items = _store.listItems(id, includeHidden: false);
    return jsonResponse({
      'shelf': shelf.toJson(itemCount: items.length),
      'items': items.map((i) => i.toJson(now)).toList(),
      'serverTime': now.toIso8601String(),
      'canManage': isOwner(request, shelf),
    });
  }

  Response _manageShelf(Request request, String id) {
    final shelf = isValidId(id) ? _store.getShelf(id) : null;
    if (shelf == null) return _shelfNotFound();
    final denied = requireOwner(request, shelf);
    if (denied != null) return denied;
    final now = ctx.clock();
    final items = _store.listItems(id, includeHidden: true);
    return jsonResponse({
      'shelf': shelf.toJson(itemCount: items.where((i) => !i.hidden).length),
      'items': items.map((i) => i.toJson(now)).toList(),
      'serverTime': now.toIso8601String(),
      'canManage': true,
    });
  }

  Future<Response> _updateShelf(Request request, String id) async {
    final shelf = isValidId(id) ? _store.getShelf(id) : null;
    if (shelf == null) return _shelfNotFound();
    final denied = requireOwner(request, shelf);
    if (denied != null) return denied;
    final fields = _shelfFields(await readJsonObject(request));
    final updated = _store.updateShelf(
      id,
      school: fields.school,
      department: fields.department,
      level: fields.level,
      session: fields.session,
      now: ctx.clock(),
    );
    return jsonResponse({
      'shelf': updated.toJson(itemCount: _store.countVisibleItems(id)),
    });
  }

  Future<Response> _createItem(Request request, String id) async {
    final shelf = isValidId(id) ? _store.getShelf(id) : null;
    if (shelf == null) return _shelfNotFound();
    final denied = requireOwner(request, shelf);
    if (denied != null) return denied;
    final body = await readJsonObject(request);
    // A file stored in a batch is named by its quilt patch ID; a file
    // stored on its own by its blob ID. Either must have been claimed for
    // this shelf, so size, type and expiry come from the server's checks.
    final patchId = cleanText(body['patchId']);
    final blobId = cleanText(body['blobId']);
    if (patchId.isEmpty && blobId.isEmpty) {
      throw ValidationException('blobId', 'Blob ID or patch ID is required.');
    }
    final upload = _store.getUpload(id, patchId.isNotEmpty ? patchId : blobId);
    if (upload == null || (patchId.isEmpty && upload.patchId != null)) {
      return errorResponse(
        409,
        'This file was not added to this shelf. Upload it again.',
        field: patchId.isNotEmpty ? 'patchId' : 'blobId',
      );
    }
    final now = ctx.clock();
    final item = _store.createItem(
      shelfId: id,
      upload: upload,
      fileName: fileNameForKind(cleanFileName(body['fileName']), upload.kind),
      courseCode: requireCourseCode(body),
      title: requireText(body, 'title', label: 'Title', max: 120),
      type: requireItemType(body),
      semester: requireSemester(body),
      session: requireSession(body),
      description: optionalText(
        body,
        'description',
        label: 'Description',
        max: 280,
      ),
      now: now,
    );
    return jsonResponse({'item': item.toJson(now)}, status: 201);
  }

  Response _getItem(Request request, String id, String itemId) {
    final item = isValidId(id) && isValidId(itemId)
        ? _store.getItem(id, itemId)
        : null;
    final shelf = item == null ? null : _store.getShelf(id);
    if (item == null || shelf == null) {
      return errorResponse(404, 'This file is not on the shelf.');
    }
    final owner = isOwner(request, shelf);
    if (item.hidden && !owner) {
      return errorResponse(404, 'This file is not on the shelf.');
    }
    final now = ctx.clock();
    return jsonResponse({
      'shelf': shelf.toJson(),
      'item': item.toJson(now),
      'serverTime': now.toIso8601String(),
      'canManage': owner,
    });
  }

  Future<Response> _updateItem(
    Request request,
    String id,
    String itemId,
  ) async {
    final item = isValidId(id) && isValidId(itemId)
        ? _store.getItem(id, itemId)
        : null;
    if (item == null) {
      return errorResponse(404, 'This file is not on the shelf.');
    }
    final denied = requireOwner(request, _store.getShelf(id)!);
    if (denied != null) return denied;
    final body = await readJsonObject(request);
    final hidden = body['hidden'];
    if (hidden != null && hidden is! bool) {
      throw ValidationException('hidden', 'Hidden must be true or false.');
    }
    final now = ctx.clock();
    final updated = _store.updateItem(
      id,
      itemId,
      courseCode: body.containsKey('courseCode')
          ? requireCourseCode(body)
          : null,
      title: body.containsKey('title')
          ? requireText(body, 'title', label: 'Title', max: 120)
          : null,
      type: body.containsKey('type') ? requireItemType(body) : null,
      semester: body.containsKey('semester') ? requireSemester(body) : null,
      session: body.containsKey('session') ? requireSession(body) : null,
      description: body.containsKey('description')
          ? optionalText(body, 'description', label: 'Description', max: 280)
          : null,
      hidden: hidden as bool?,
      now: now,
    );
    return jsonResponse({'item': updated.toJson(now)});
  }

  Response _shelfNotFound() =>
      errorResponse(404, 'This shelf does not exist. Check the link.');
}
