import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart';

import '../widgets/account.dart' show showLecternWalletPicker;

/// The course rep's sign-in with a Sui wallet.
///
/// Only reps sign in. Students never touch this: the class link works with
/// no wallet and no account. The session itself is an `HttpOnly` cookie
/// (`lectern_session`) that the browser sends with every same-origin request,
/// API calls and Dartus uploads alike, so nothing here stores a secret.
class RepSession extends ChangeNotifier {
  RepSession({required this.wallet, required this.client});

  final SuiWalletController wallet;
  final SuiSignInClient client;

  SuiSessionInfo? _info;
  bool _checking = true;
  bool _busy = false;
  SuiSignInStep? _step;
  String? _error;
  String? _notice;
  bool _picking = false;
  bool _walletStarted = false;
  bool _disposed = false;
  StreamSubscription<SuiWalletChange>? _changes;

  /// Who is signed in, or null.
  SuiSessionInfo? get info => _info;
  String? get address => _info?.address;
  bool get signedIn => _info != null;

  /// True until the first check of the session cookie has finished.
  bool get checking => _checking;

  /// True while a sign-in is in progress.
  bool get busy => _busy;
  SuiSignInStep? get step => _step;

  /// Why the last sign-in failed, in plain words.
  String? get error => _error;

  /// Something the rep should know: the sign-in ended, or the wallet
  /// switched to another account.
  String? get notice => _notice;

  Future<void>? _started;

  /// Asks the server whether the session cookie is still good. Cheap, it
  /// does not touch the wallet, and it runs once: rep pages call it when
  /// they open, so students' pages never ask.
  Future<void> start() => _started ??= _check();

  Future<void> _check() async {
    try {
      _info = await client.currentSession();
    } on SuiSignInException {
      _info = null;
    }
    _checking = false;
    if (_info != null) unawaited(ensureWallet());
    _notify();
  }

  /// Starts wallet discovery and silent reconnect the first time a rep
  /// needs it, so students' pages never look for wallets.
  Future<void> ensureWallet() async {
    if (_walletStarted) return;
    _walletStarted = true;
    _changes = wallet.changes.listen(_onWalletChange);
    await wallet.init();
  }

  void _onWalletChange(SuiWalletChange change) {
    final info = _info;
    if (change.type != SuiWalletChangeType.accountChanged || info == null) {
      return;
    }
    final next = change.state.account?.address;
    if (next == null || next == info.address) return;
    _notice =
        'Your wallet switched to ${shortenSuiAddress(next)}. You are still '
        'signed in as ${info.shortAddress}. Sign in again to manage the '
        'other account\'s shelves.';
    _notify();
  }

  /// Signs the rep in: pick a wallet if none is connected, then sign the
  /// server's message. Returns true when signed in.
  Future<bool> signIn(BuildContext context) async {
    if (_busy || _picking) return false;
    _error = null;
    _notice = null;
    _notify();
    try {
      await ensureWallet();
      if (!wallet.isConnected) {
        if (!context.mounted) return false;
        _picking = true;
        final account = await showLecternWalletPicker(context, wallet);
        _picking = false;
        if (account == null) return false;
      }
      _busy = true;
      _step = SuiSignInStep.requestingChallenge;
      _notify();
      _info = await client.signIn(
        onProgress: (step, {message}) {
          _step = step;
          _notify();
        },
      );
      return true;
    } on SuiSignInException catch (e) {
      _error = e.message;
      return false;
    } on SuiWalletException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _picking = false;
      _busy = false;
      _step = null;
      _notify();
    }
  }

  /// Connects a wallet for paying storage, when none is connected (for
  /// example after the wallet was locked). Returns true when one is.
  Future<bool> connectWallet(BuildContext context) async {
    if (_picking) return false;
    await ensureWallet();
    if (wallet.isConnected) return true;
    if (!context.mounted) return false;
    _picking = true;
    try {
      return await showLecternWalletPicker(context, wallet) != null;
    } finally {
      _picking = false;
    }
  }

  /// Signs out on the server. With [forgetWallet], the wallet is
  /// disconnected too, so the next sign-in can pick another account.
  Future<bool> signOut({bool forgetWallet = false}) async {
    try {
      await client.signOut();
    } on SuiSignInException {
      _notice = 'Could not sign out. Check your connection and try again.';
      _notify();
      return false;
    }
    if (forgetWallet && wallet.isConnected) {
      try {
        await wallet.disconnect();
      } on SuiWalletException {
        // Nothing to undo.
      }
    }
    _info = null;
    _notice = null;
    _error = null;
    _notify();
    return true;
  }

  /// The server answered 401: the session expired or ended elsewhere.
  void expired() {
    if (_info == null) return;
    _info = null;
    _notice =
        'Your sign-in has ended. Sign in again to keep managing your shelves.';
    _notify();
  }

  void clearNotice() {
    if (_notice == null && _error == null) return;
    _notice = null;
    _error = null;
    _notify();
  }

  /// Plain words for the current sign-in step.
  static String describe(SuiSignInStep? step) => switch (step) {
    SuiSignInStep.connecting || null => 'Opening your wallet…',
    SuiSignInStep.requestingChallenge => 'Preparing the sign-in message…',
    SuiSignInStep.signing => 'Approve the sign-in message in your wallet',
    SuiSignInStep.verifying => 'Checking the signature…',
    SuiSignInStep.done => 'Signed in',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _changes?.cancel();
    wallet.dispose();
    client.close();
    super.dispose();
  }
}
