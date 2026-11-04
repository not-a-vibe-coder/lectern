import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/account.dart';
import '../widgets/layout.dart';
import '../widgets/paper.dart';
import '../widgets/press.dart';
import '../widgets/share.dart';

/// Shown once after a shelf is created: the class link, ready to share.
class CreatedScreen extends StatefulWidget {
  const CreatedScreen({super.key, required this.shelfId});
  final String shelfId;

  @override
  State<CreatedScreen> createState() => _CreatedScreenState();
}

class _CreatedScreenState extends State<CreatedScreen> {
  Shelf? _shelf;
  bool _canManage = false;
  ApiException? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      AppScope.of(context).session.start();
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final page = await AppScope.of(context).api.shelf(widget.shelfId);
      if (!mounted) return;
      setState(() {
        _shelf = page.shelf;
        _canManage = page.canManage;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final shelf = _shelf;

    if (shelf != null && !_canManage) {
      // Someone opened /created for a shelf they do not own.
      return PageFrame(
        maxWidth: Breakpoints.readingMax,
        child: MessageState(
          icon: Icons.lock_outline,
          title: 'Nothing to show here',
          body:
              'This page is for the rep who created the shelf, signed in '
              'with their wallet.',
          actions: [
            FilledButton(
              onPressed: () => context.go('/s/${widget.shelfId}'),
              child: const Text('Open the shelf'),
            ),
          ],
        ),
      );
    }
    if (shelf == null) {
      return PageFrame(
        maxWidth: Breakpoints.readingMax,
        child: _error == null
            ? const Padding(
                padding: EdgeInsets.only(top: Space.xl),
                child: SkeletonRows(count: 2),
              )
            : MessageState(
                icon: Icons.wifi_off_outlined,
                title: 'Could not load the shelf',
                body: _error!.message,
                actions: [
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
      );
    }

    final publicUrl = services.config.shelfUrl(shelf.id);

    return PageFrame(
      maxWidth: Breakpoints.readingMax,
      actions: const [AccountMenu()],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Space.lg),
          const Eyebrow('Shelf created'),
          const SizedBox(height: Space.xs),
          Semantics(
            header: true,
            child: Text('Your shelf is ready', style: text.displaySmall),
          ),
          const SizedBox(height: Space.xs),
          Text(shelf.title, style: LecternType.mono.copyWith(fontSize: 14)),
          const SizedBox(height: Space.xl),
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.groups_outlined,
                      color: LecternColors.blue,
                    ),
                    const SizedBox(width: Space.xs),
                    Text('Class link', style: text.titleMedium),
                  ],
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  'Share this with your classmates. Anyone with it can view and '
                  'download files. They do not need a wallet.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: Space.sm),
                _LinkBox(url: publicUrl),
                const SizedBox(height: Space.md),
                ShareActions(
                  shelfId: shelf.id,
                  title: shelf.title,
                  direction:
                      MediaQuery.sizeOf(context).width < Breakpoints.medium
                      ? Axis.vertical
                      : Axis.horizontal,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          Notice(
            tone: NoticeTone.info,
            icon: Icons.account_balance_wallet_outlined,
            child: Text(
              'Only you can add, edit or hide files. To manage this shelf on '
              'another phone or laptop, open Lectern there and sign in with '
              'the same wallet. There is no secret link to keep.',
              style: text.bodyMedium,
            ),
          ),
          const SizedBox(height: Space.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: PressScale(
              child: FilledButton.icon(
                onPressed: () => context.go('/s/${shelf.id}/manage'),
                icon: const Icon(Icons.upload_file, size: 20),
                label: const Text('Start uploading'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkBox extends StatelessWidget {
  const _LinkBox({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.sm,
      vertical: Space.sm,
    ),
    decoration: BoxDecoration(
      color: LecternColors.surface,
      border: Border.all(color: LecternColors.control),
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: SelectableText(
      url,
      style: LecternType.mono.copyWith(color: LecternColors.ink, fontSize: 13),
      semanticsLabel: 'Class link $url',
    ),
  );
}
