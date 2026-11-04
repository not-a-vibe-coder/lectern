import 'package:http/http.dart' as http;

import 'progress_client_io.dart'
    if (dart.library.js_interop) 'progress_client_web.dart'
    as impl;

typedef ProgressCallback = void Function(int done, int? total);

/// An HTTP client that reports upload and download progress and can be
/// cancelled. Dartus accepts any `http.Client`, so uploads and reads still go
/// through Dartus while the app shows progress.
abstract class ProgressClient extends http.BaseClient {
  ProgressCallback? onSendProgress;
  ProgressCallback? onReceiveProgress;

  /// Cancels the request in flight. The pending call fails with
  /// [http.ClientException].
  void abort();

  bool get aborted;
}

ProgressClient createProgressClient() => impl.createProgressClient();

typedef ProgressClientFactory = ProgressClient Function();
