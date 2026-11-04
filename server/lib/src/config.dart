import 'package:sui_auth/sui_auth.dart' show SuiChain;
import 'package:walrus_blob_check/walrus_blob_check.dart' show WalrusChain;

/// Server configuration, read from environment variables only.
///
/// There is no publisher and no server wallet: every upload is paid for by
/// the rep's own wallet in the browser. The server only checks blobs on Sui
/// and lists them.
class ServerConfig {
  ServerConfig({
    this.port = 8091,
    Uri? aggregatorUrl,
    this.epochs = defaultEpochs,
    this.maxUploadMb = 25,
    this.dataDir = 'data',
    this.publicBaseUrl,
    this.webDir = '../app/build/web',
    Duration? epochDuration,
    this.shelfCreateLimitPerHour = 20,
    this.claimLimitPerHour = 120,
    this.trustProxy = false,
    this.suiChain = SuiChain.testnet,
    this.sessionTtl = const Duration(days: 30),
    this.signInLimitPerTenMinutes = 30,
  }) : aggregatorUrl =
           aggregatorUrl ?? Uri.parse(_walrusChainOf(suiChain).aggregator),
       epochDuration =
           epochDuration ??
           (suiChain == SuiChain.mainnet
               ? const Duration(days: 14)
               : const Duration(days: 1));

  static const testnetAggregator =
      'https://aggregator.walrus-testnet.walrus.space';
  static const mainnetAggregator =
      'https://aggregator.walrus-mainnet.walrus.space';

  /// The storage period the app suggests. One epoch is one day on testnet
  /// and two weeks on mainnet, so 26 epochs is about a year on mainnet (one
  /// academic session). The rep's wallet pays for whatever they choose.
  static const defaultEpochs = 26;

  final int port;

  /// Aggregator that students read from and the server reads first bytes
  /// from. Defaults to Mysten's for [suiChain].
  final Uri aggregatorUrl;

  /// Suggested storage epochs (`EPOCHS`), sent to the app.
  final int epochs;

  /// Largest file the site lists (`MAX_UPLOAD_MB`). Reps pay for their own
  /// storage, so this is a policy for phones and students' data, not a cost
  /// control.
  final int maxUploadMb;
  final String dataDir;

  /// The URL people open, for example `https://lectern.example`. Its origin
  /// is the domain in the sign-in message and the only origin allowed to
  /// sign in, and it is used in share links, QR codes and Open Graph tags.
  /// When null, sign-in uses `http://localhost:<port>` and links use the
  /// request's own (validated) host.
  final Uri? publicBaseUrl;
  final String webDir;
  final Duration epochDuration;
  final int shelfCreateLimitPerHour;

  /// Blob claims allowed per account per hour (`CLAIM_LIMIT`): each claim
  /// costs the server a Sui GraphQL call and a few aggregator reads.
  final int claimLimitPerHour;

  /// Trust `X-Forwarded-Host`, `X-Forwarded-Proto` and `X-Forwarded-For`.
  /// Only set this behind a reverse proxy that overwrites those headers.
  final bool trustProxy;

  /// The Sui network (`SUI_CHAIN`, testnet by default): reps sign in, pay
  /// for storage and own their blobs here.
  final SuiChain suiChain;

  /// How long a sign-in lasts before the rep signs in again.
  final Duration sessionTtl;

  /// Sign-in requests (nonce and verify, so two per sign-in) allowed per
  /// client address in ten minutes (`SIGN_IN_LIMIT`).
  final int signInLimitPerTenMinutes;

  /// The origin sign-in messages are bound to.
  Uri get authBaseUrl =>
      publicBaseUrl ?? Uri(scheme: 'http', host: 'localhost', port: port);

  int get maxUploadBytes => maxUploadMb * 1024 * 1024;

  /// `testnet` or `mainnet`.
  String get network => walrusChain.name;

  /// The Walrus deployment blobs are checked against.
  WalrusChain get walrusChain => _walrusChainOf(suiChain);

  static WalrusChain _walrusChainOf(SuiChain chain) =>
      chain == SuiChain.mainnet ? WalrusChain.mainnet : WalrusChain.testnet;

  factory ServerConfig.fromEnvironment(Map<String, String> env) {
    int intVar(String name, int fallback, {int min = 1, int? max}) {
      final raw = env[name];
      if (raw == null || raw.trim().isEmpty) return fallback;
      final value = int.tryParse(raw.trim());
      if (value == null || value < min || (max != null && value > max)) {
        throw FormatException(
          '$name must be a whole number'
          '${max == null ? ' of at least $min' : ' from $min to $max'}',
        );
      }
      return value;
    }

    Uri? urlVar(String name) {
      final raw = env[name]?.trim();
      if (raw == null || raw.isEmpty) return null;
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw FormatException(
          '$name must be an absolute http(s) URL without credentials',
        );
      }
      return uri;
    }

    final aggregator = urlVar('AGGREGATOR_URL');
    final chainRaw = env['SUI_CHAIN']?.trim();
    final chain = chainRaw == null || chainRaw.isEmpty
        ? SuiChain.testnet
        : SuiChain.tryParse(chainRaw);
    if (chain != SuiChain.testnet && chain != SuiChain.mainnet) {
      throw const FormatException('SUI_CHAIN must be testnet or mainnet');
    }
    final publicBase = urlVar('PUBLIC_BASE_URL');
    if (publicBase != null &&
        (!{'http', 'https'}.contains(publicBase.scheme) ||
            (publicBase.path.isNotEmpty && publicBase.path != '/') ||
            publicBase.hasQuery ||
            publicBase.hasFragment)) {
      throw const FormatException(
        'PUBLIC_BASE_URL must be an http(s) origin such as '
        'https://lectern.example, with no path',
      );
    }
    final epochHours = env['EPOCH_DURATION_HOURS'];
    return ServerConfig(
      port: intVar('PORT', 8091, max: 65535),
      aggregatorUrl: aggregator,
      epochs: intVar('EPOCHS', defaultEpochs, max: 53),
      maxUploadMb: intVar('MAX_UPLOAD_MB', 25, max: 1024),
      dataDir: (env['DATA_DIR']?.trim().isNotEmpty ?? false)
          ? env['DATA_DIR']!.trim()
          : 'data',
      publicBaseUrl: publicBase == null ? null : Uri.parse(publicBase.origin),
      webDir: (env['WEB_DIR']?.trim().isNotEmpty ?? false)
          ? env['WEB_DIR']!.trim()
          : '../app/build/web',
      epochDuration: epochHours == null || epochHours.trim().isEmpty
          ? null
          : Duration(hours: intVar('EPOCH_DURATION_HOURS', 24, max: 24 * 60)),
      claimLimitPerHour: intVar('CLAIM_LIMIT', 120, max: 100000),
      trustProxy: const {
        'true',
        '1',
        'yes',
      }.contains(env['TRUST_PROXY']?.trim().toLowerCase()),
      suiChain: chain!,
      sessionTtl: Duration(days: intVar('SESSION_DAYS', 30, max: 365)),
      signInLimitPerTenMinutes: intVar('SIGN_IN_LIMIT', 30, max: 100000),
    );
  }

  /// A short summary for the startup log.
  String describe() =>
      'port=$port suiChain=${suiChain.id} aggregator=${aggregatorUrl.host} '
      'epochs=$epochs maxUploadMb=$maxUploadMb dataDir=$dataDir '
      'webDir=$webDir publicBaseUrl=${publicBaseUrl ?? 'unset'} '
      'trustProxy=$trustProxy signInOrigin=${authBaseUrl.origin} '
      'sessionDays=${sessionTtl.inDays} claimLimit=$claimLimitPerHour/h';
}
