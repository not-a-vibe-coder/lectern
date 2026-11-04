import 'package:flutter/widgets.dart';
import 'package:upload_recovery/walrus_recovery.dart';

import 'models/models.dart';
import 'platform/browser.dart';
import 'services/api.dart';
import 'services/local_state.dart';
import 'services/rep_session.dart';
import 'services/upload_queue.dart';
import 'services/upload_recovery.dart';
import 'services/wallet_storage.dart';
import 'services/walrus_service.dart';

/// Services shared by every screen.
class AppServices {
  AppServices({
    required this.config,
    required this.api,
    required this.walrus,
    required this.storage,
    required this.browser,
    required this.session,
    VisitTracker? visits,
    DateTime Function()? clock,
  }) : visits =
           visits ??
           VisitTracker(local: browser.local, session: browser.session),
       clock = clock ?? DateTime.now {
    // Any 401 from the API means the rep's sign-in has ended.
    api.onSignedOut = session.expired;
    session.addListener(_onSessionChanged);
  }

  final AppConfig config;
  final LecternApi api;

  /// Reads files from the aggregator (students and reps).
  final WalrusService walrus;

  /// Stores files on Walrus, paid for by the rep's wallet.
  final WalletStorage storage;
  final BrowserBridge browser;
  final VisitTracker visits;

  /// The course rep's wallet sign-in. Students never need it.
  final RepSession session;
  final DateTime Function() clock;
  late final WalrusUploadRecovery? recovery = storage is DartusWalletStorage
      ? WalrusUploadRecovery(
          app: 'lectern',
          chain: config.suiChain,
          wallet: session.wallet,
          finish: (job, stored) => finishLecternUpload(
            api,
            job,
            stored,
            signedInAddress: () => session.address,
          ),
        )
      : null;

  final _queues = <String, UploadQueue>{};
  String? _queuesOwner;

  /// One upload queue per shelf, kept while the rep stays signed in so
  /// uploads keep going while they look at other pages. A sign-in that ends
  /// by expiry keeps the queue, so failed files can be retried after signing
  /// in again.
  UploadQueue uploadsFor(String shelfId, {required String defaultSession}) {
    final existing = _queues[shelfId];
    if (existing != null) return existing;
    final queue = UploadQueue(
      shelfId: shelfId,
      storage: storage,
      wallet: session.wallet,
      signedInAddress: () => session.address,
      api: api,
      maxBytes: config.maxUploadBytes,
      defaultSession: defaultSession,
      suggestedEpochs: config.epochs,
      onSignedOut: session.expired,
      recovery: recovery,
    );
    _queues[shelfId] = queue;
    return queue;
  }

  void _onSessionChanged() {
    final address = session.address;
    if (address == null) return;
    // Another account signed in on this device: its shelves get fresh
    // queues. (Old ones are left to finish or fail; screens may still
    // listen to them.)
    if (_queuesOwner != null && _queuesOwner != address) _queues.clear();
    _queuesOwner = address;
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}
