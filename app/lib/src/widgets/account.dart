import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart';

import '../app_scope.dart';
import '../services/rep_session.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'layout.dart';
import 'paper.dart';
import 'press.dart';

/// Asks a course rep to sign in with a Sui wallet.
///
/// Used on the app home and on a shelf's manage page. It says plainly that
/// students do not need a wallet.
class SignInPanel extends StatefulWidget {
  const SignInPanel({
    super.key,
    this.title = 'Sign in to manage your shelves',
    this.body =
        'Course reps sign in with a Sui wallet, such as Slush. Your shelves '
        'follow your wallet to any phone or laptop, and the files you upload '
        'are owned by your address.',
    this.onSignedIn,
  });

  final String title;
  final String body;
  final VoidCallback? onSignedIn;

  @override
  State<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends State<SignInPanel> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Look for wallets while the rep reads, so the picker opens ready.
    AppScope.of(context).session.ensureWallet();
  }

  Future<void> _signIn() async {
    final session = AppScope.of(context).session;
    final ok = await session.signIn(context);
    if (ok) widget.onSignedIn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final busy = session.busy;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(widget.title, style: text.headlineSmall),
            ),
            const SizedBox(height: Space.xs),
            Text(
              widget.body,
              style: text.bodyMedium!.copyWith(color: LecternColors.ink2),
            ),
            if (session.notice != null) ...[
              const SizedBox(height: Space.md),
              Notice(tone: NoticeTone.warning, child: Text(session.notice!)),
            ],
            const SizedBox(height: Space.lg),
            PressScale(
              child: FilledButton.icon(
                onPressed: busy ? null : _signIn,
                icon: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 20,
                ),
                label: Text(busy ? 'Signing in…' : 'Sign in with Sui wallet'),
              ),
            ),
            if (busy) ...[
              const SizedBox(height: Space.sm),
              _StepLine(text: RepSession.describe(session.step)),
            ],
            if (session.error != null) ...[
              const SizedBox(height: Space.md),
              Notice(tone: NoticeTone.error, child: Text(session.error!)),
            ],
            const SizedBox(height: Space.md),
            Text(
              'Signing in is free: it does not send a transaction. Students '
              'never need a wallet. They open the class link you share.',
              style: text.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: LecternColors.ink2),
          ),
        ),
      ],
    ),
  );
}

/// The signed-in rep's address in the top bar, with a small menu.
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final info = session.info;
        if (info == null) return const SizedBox.shrink();
        return PopupMenuButton<String>(
          popUpAnimationStyle: Motion.menu(context),
          tooltip: 'Signed in as ${info.shortAddress}',
          position: PopupMenuPosition.under,
          onSelected: (value) async {
            switch (value) {
              case 'shelves':
                context.go('/app');
              case 'copy':
                await copyText(
                  context,
                  info.address,
                  message: 'Address copied',
                );
              case 'out':
                final signedOut = await session.signOut();
                if (context.mounted) {
                  if (!signedOut) {
                    showToast(context, session.notice!);
                    return;
                  }
                  showToast(context, 'Signed out');
                  context.go('/app');
                }
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(
                info.address,
                style: LecternType.mono.copyWith(fontSize: 11),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'shelves',
              child: ListTile(
                leading: Icon(Icons.collections_bookmark_outlined),
                title: Text('Your shelves'),
              ),
            ),
            const PopupMenuItem(
              value: 'copy',
              child: ListTile(
                leading: Icon(Icons.copy),
                title: Text('Copy address'),
              ),
            ),
            const PopupMenuItem(
              value: 'out',
              child: ListTile(
                leading: Icon(Icons.logout),
                title: Text('Sign out'),
              ),
            ),
          ],
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            decoration: BoxDecoration(
              color: LecternColors.surface,
              border: Border.all(color: LecternColors.control),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  size: 20,
                  color: LecternColors.blue,
                ),
                const SizedBox(width: 6),
                Text(
                  info.shortAddress,
                  style: LecternType.mono.copyWith(color: LecternColors.ink),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: LecternColors.ink2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A warning when the sign-in ended or the wallet switched accounts, with a
/// way to sign in again.
class SessionNotice extends StatelessWidget {
  const SessionNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final notice = session.notice;
        if (notice == null || !session.signedIn) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Notice(
            tone: NoticeTone.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notice),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.xs,
                  children: [
                    TextButton(
                      onPressed: session.busy
                          ? null
                          : () async {
                              final signedOut = await session.signOut();
                              if (context.mounted && signedOut) {
                                await session.signIn(context);
                              }
                            },
                      child: const Text('Sign in again'),
                    ),
                    TextButton(
                      onPressed: session.clearNotice,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The wallet list in a Lectern dialog: the shared [SuiWalletPicker] (wallet
/// discovery, the "Install Slush" state, errors) with Lectern's own tiles,
/// which give the wallet name the whole row on a phone.
Future<SuiWalletAccount?> showLecternWalletPicker(
  BuildContext context,
  SuiWalletController wallet,
) => showDialog<SuiWalletAccount>(
  context: context,
  animationStyle: Motion.dialog(context),
  builder: (dialogContext) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.lg,
          Space.lg,
          Space.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SuiWalletPicker(
              controller: wallet,
              strings: const SuiWalletPickerStrings(
                title: 'Sign in with your Sui wallet',
                searching: 'Looking for wallets in this browser…',
                installHint:
                    'Then reload this page. Students do not need a wallet.',
                approveIn: 'Approve in',
              ),
              tileBuilder: (context, info, state, onPressed) =>
                  _WalletTile(wallet: info, state: state, onPressed: onPressed),
              onConnected: (account) =>
                  Navigator.of(dialogContext).pop(account),
            ),
            const SizedBox(height: Space.xxs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

class _WalletTile extends StatelessWidget {
  const _WalletTile({
    required this.wallet,
    required this.state,
    required this.onPressed,
  });

  final SuiWalletInfo wallet;
  final SuiWalletTileState state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final connecting = state == SuiWalletTileState.connecting;
    final connected = state == SuiWalletTileState.connected;
    final status = connecting
        ? 'Approve in ${wallet.name}…'
        : connected
        ? 'Connected'
        : null;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: connected
          ? '${wallet.name}, connected'
          : 'Connect with ${wallet.name}',
      excludeSemantics: true,
      child: PressScale(
        child: Opacity(
          opacity: state == SuiWalletTileState.disabled ? 0.55 : 1,
          child: Material(
            color: LecternColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              side: BorderSide(
                color: connected ? LecternColors.blue : LecternColors.control,
                width: connected ? 2 : 1,
              ),
            ),
            child: InkWell(
              onTap: onPressed,
              hoverColor: LecternColors.blueTint,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  child: Row(
                    children: [
                      SuiWalletIcon(
                        wallet: wallet,
                        size: 32,
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              wallet.name,
                              style: text.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (status != null)
                              Text(
                                status,
                                style: text.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      if (connecting)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          connected ? Icons.check : Icons.chevron_right,
                          color: connected
                              ? LecternColors.blue
                              : LecternColors.ink2,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
