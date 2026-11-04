import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart';

import 'app_scope.dart';
import 'platform/browser.dart';
import 'router.dart';
import 'services/api.dart';
import 'services/rep_session.dart';
import 'package:dartus/dartus.dart' show WalrusNetwork;
import 'services/wallet_storage.dart';
import 'services/walrus_service.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'widgets/brand.dart';

/// The route to open for the page URL: the path and query, never the
/// fragment, with `/` mapped to the app home.
String initialLocationFor(Uri url) {
  final path = url.path.isEmpty || url.path == '/' ? '/app' : url.path;
  return url.hasQuery ? '$path?${url.query}' : path;
}

/// Loads server config, then starts the app.
class LecternBootstrap extends StatefulWidget {
  const LecternBootstrap({super.key, required this.browser, required this.api});
  final BrowserBridge browser;
  final LecternApi api;

  @override
  State<LecternBootstrap> createState() => _LecternBootstrapState();
}

class _LecternBootstrapState extends State<LecternBootstrap> {
  AppServices? _services;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final config = await widget.api.config();
      if (!mounted) return;
      final origin = Uri.parse(widget.browser.origin);
      final wallet = SuiWalletController(chain: config.suiChain);
      final session = RepSession(
        wallet: wallet,
        client: SuiSignInClient(
          wallet: wallet,
          authBase: origin.resolve('/api/auth/'),
        ),
      );
      setState(() {
        _services = AppServices(
          config: config,
          api: widget.api,
          browser: widget.browser,
          session: session,
          walrus: WalrusService(aggregatorBaseUrl: config.aggregatorUrl),
          // The same network the wallet signs on: config.suiChain.
          storage: DartusWalletStorage(
            network: config.network == 'mainnet'
                ? WalrusNetwork.mainnet
                : WalrusNetwork.testnet,
          ),
        );
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services != null) {
      final path = widget.browser.initialUrl;
      return LecternApp(
        services: services,
        initialLocation: initialLocationFor(path),
      );
    }
    return MaterialApp(
      title: 'Lectern',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LecternMark(size: 56),
                const SizedBox(height: Space.md),
                if (_error == null)
                  const Text('Opening Lectern…')
                else ...[
                  Text(
                    'Lectern could not start',
                    style: buildTheme().textTheme.headlineSmall,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: Space.md),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LecternApp extends StatefulWidget {
  const LecternApp({
    super.key,
    required this.services,
    this.initialLocation = '/app',
  });

  final AppServices services;
  final String initialLocation;

  @override
  State<LecternApp> createState() => _LecternAppState();
}

class _LecternAppState extends State<LecternApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
  );

  // Focus rings appear for keyboard users only, like CSS :focus-visible:
  // a key press turns them on, a pointer press turns them off.
  @override
  void initState() {
    super.initState();
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    }
    return false;
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.services,
    child: MaterialApp.router(
      title: 'Lectern',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
    ),
  );
}
