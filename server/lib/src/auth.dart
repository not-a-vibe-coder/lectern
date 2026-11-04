import 'package:shelf/shelf.dart';
import 'package:sui_auth/sqlite.dart';
import 'package:sui_auth/sui_auth.dart';

import 'config.dart';
import 'http_utils.dart';
import 'models.dart';
import 'store.dart';

/// Sign in with Sui for course reps. Nonces and sessions live in Lectern's
/// own SQLite file (tables prefixed `sui_auth_`).
///
/// Tests pass a [verifier] without GraphQL and a [clock] they control.
SuiAuth buildAuth(
  ServerConfig config,
  Store store, {
  SuiSignatureVerifier? verifier,
  DateTime Function()? clock,
}) {
  final sqlite = SqliteSuiAuthStore(store.db);
  return SuiAuth(
    config: SuiAuthConfig.fromBaseUrl(
      config.authBaseUrl.toString(),
      chain: config.suiChain,
      statement:
          'Sign in to Lectern to manage your shelves. This does not send a '
          'transaction or cost gas.',
      sessionTtl: config.sessionTtl,
      cookieName: 'lectern_session',
    ),
    nonces: sqlite,
    sessions: sqlite,
    verifier: verifier,
    clock: clock,
  );
}

/// 401 when nobody is signed in, 403 when the shelf belongs to someone else,
/// null when the signed-in rep owns [shelf].
Response? requireOwner(Request request, Shelf shelf) {
  final address = request.suiAddress;
  if (address == null) {
    return errorResponse(401, 'Sign in with your Sui wallet to continue.');
  }
  if (address != shelf.ownerAddress) {
    return errorResponse(
      403,
      'This shelf belongs to another account. Sign in with the wallet that '
      'created it.',
    );
  }
  return null;
}

/// True when the signed-in rep owns [shelf].
bool isOwner(Request request, Shelf shelf) =>
    request.suiAddress != null && request.suiAddress == shelf.ownerAddress;
