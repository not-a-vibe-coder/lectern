import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:sui_auth/sui_auth.dart';
import 'package:walrus_blob_check/walrus_blob_check.dart';

import 'api.dart';
import 'claims.dart';
import 'http_utils.dart';
import 'poster.dart';
import 'static_site.dart';

/// Builds the full request handler: sign-in, API (with blob claims), poster
/// and web app.
///
/// [walrusClient] carries Sui GraphQL and aggregator reads for blob checks;
/// tests pass a fake.
Handler buildHandler(
  AppContext ctx, {
  http.Client? walrusClient,
  void Function(String message) log = print,
  bool logRequests = false,
}) {
  final checker = WalrusBlobChecker(
    chain: ctx.config.walrusChain,
    client: walrusClient,
    aggregatorUrl: ctx.config.aggregatorUrl,
  );
  final api = Api(ctx, BlobClaims(ctx, checker, client: walrusClient));
  final poster = PosterPage(ctx);
  final site = StaticSite(ctx);
  final authHandlers = SuiAuthHandlers(ctx.auth, log: log);
  final signInLimiter = RateLimiter(
    ctx.config.signInLimitPerTenMinutes,
    const Duration(minutes: 10),
  );

  Future<Response> route(Request request) async {
    final path = request.url.path;
    if ((path == 'api' || path.startsWith('api/')) &&
        !{'GET', 'HEAD', 'OPTIONS'}.contains(request.method)) {
      final origin = request.headers['origin'];
      if ((origin != null &&
              !ctx.auth.config.allowedOrigins.contains(origin)) ||
          (origin == null &&
              request.headers['sec-fetch-site'] == 'cross-site')) {
        return errorResponse(
          403,
          'Open Lectern on its own site to continue.',
          code: 'ORIGIN_NOT_ALLOWED',
        );
      }
    }
    if (path.startsWith('api/auth/')) {
      // nonce and verify do real work (a GraphQL call for zkLogin), so they
      // are rate limited; reading the session and signing out are not.
      if (request.method == 'POST' &&
          (path == 'api/auth/nonce' || path == 'api/auth/verify') &&
          !signInLimiter.allow(
            clientAddress(request, trustProxy: ctx.config.trustProxy),
            ctx.clock(),
          )) {
        return errorResponse(
          429,
          'Too many sign-in attempts. Wait a few minutes and try again.',
        );
      }
      return authHandlers.handler(request.change(path: 'api/auth'));
    }
    if (path == 'api' || path.startsWith('api/')) return api.handler(request);
    final segments = request.url.pathSegments;
    if (segments.length == 3 && segments[0] == 's' && segments[2] == 'print') {
      return poster.handle(request, segments[1]);
    }
    return site.handle(request);
  }

  Middleware catchErrors() =>
      (inner) => (request) async {
        try {
          return await inner(request);
        } catch (error, stack) {
          log(
            'error on ${request.method} /${request.url.path}: $error\n$stack',
          );
          return errorResponse(500, 'Something went wrong on the server.');
        }
      };

  var pipeline = const Pipeline().addMiddleware(securityHeaders());
  if (logRequests) pipeline = pipeline.addMiddleware(quietLogger(log));
  return pipeline
      .addMiddleware(catchErrors())
      // Puts the signed-in address (from the lectern_session cookie) on the
      // request: `request.suiAddress`.
      .addMiddleware(suiAuthMiddleware(ctx.auth))
      .addHandler(route);
}
