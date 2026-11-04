import 'dart:async';
import 'dart:io';

import 'package:lectern_server/lectern_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final ServerConfig config;
  try {
    config = ServerConfig.fromEnvironment(Platform.environment);
  } on FormatException catch (e) {
    stderr.writeln('Configuration error: ${e.message}');
    exitCode = 64;
    return;
  }

  final store = Store.open(config.dataDir);
  final ctx = AppContext(config: config, store: store);
  final handler = buildHandler(ctx, logRequests: true);

  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    config.port,
  );
  server.autoCompress = false;
  server.idleTimeout = const Duration(minutes: 2);
  stdout.writeln('Lectern listening on http://localhost:${server.port}');
  stdout.writeln(config.describe());
  if (config.publicBaseUrl == null) {
    stdout.writeln(
      'WARNING: PUBLIC_BASE_URL is not set. Sign-in only works when people '
      'open ${config.authBaseUrl.origin} exactly. Share links, QR codes and '
      'link previews will use the request Host header (validated; '
      '${config.trustProxy ? 'X-Forwarded-Host is trusted' : 'X-Forwarded-* ignored'}). '
      'Set PUBLIC_BASE_URL to the URL people open.',
    );
  }

  // Expired nonces and sessions are also dropped when looked up; this keeps
  // the tables small.
  await ctx.auth.purgeExpired();
  final purge = Timer.periodic(
    const Duration(hours: 1),
    (_) => ctx.auth.purgeExpired(),
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Stopping ($signal)');
    purge.cancel();
    await server.close(force: false);
    store.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}
