import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';
import 'press.dart';
import 'brand.dart';

/// Centers content with the page gutter and a maximum width.
class Constrained extends StatelessWidget {
  const Constrained({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.contentMax,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = Breakpoints.gutter(width);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// The page shell: a slim top bar, scrolling content and the footer.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.child,
    this.actions = const [],
    this.maxWidth = Breakpoints.contentMax,
    this.scrollController,
    this.floating,
  });

  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  final ScrollController? scrollController;
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: floating,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: TopBar(actions: actions, maxWidth: maxWidth),
            ),
            SliverToBoxAdapter(
              child: Constrained(maxWidth: maxWidth, child: child),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SiteFooter(maxWidth: maxWidth),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    this.actions = const [],
    this.maxWidth = Breakpoints.contentMax,
  });
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Constrained(
      maxWidth: maxWidth,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            FocusRing(
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: () => context.go('/app'),
                child: Semantics(
                  link: true,
                  label: 'Lectern home',
                  excludeSemantics: true,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    child: Wordmark(size: 28),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            // Actions shrink rather than overflow on narrow phones or with
            // large text.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key, this.maxWidth = Breakpoints.contentMax});
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall!;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxl),
      child: Constrained(
        maxWidth: maxWidth,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: Space.lg),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: LecternColors.rule)),
          ),
          child: Wrap(
            spacing: Space.lg,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const LecternMark(size: 18),
              Text(
                'Lectern',
                style: small.copyWith(
                  fontWeight: FontWeight.w700,
                  color: LecternColors.ink2,
                ),
              ),
              Text('Files stored on Walrus', style: small),
              Text('Built with Dartus', style: small),
              Text('MIT licence', style: small),
            ],
          ),
        ),
      ),
    );
  }
}

/// A centered message for empty, error and not-found states.
class MessageState extends StatelessWidget {
  const MessageState({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.actions = const [],
    this.compact = false,
  });

  final String title;
  final String body;
  final IconData? icon;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? Space.lg : Space.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: LecternColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: LecternColors.rule),
                    ),
                    child: Icon(icon, size: 26, color: LecternColors.ink2),
                  ),
                  const SizedBox(height: Space.md),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: compact ? text.titleLarge : text.headlineSmall,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium!.copyWith(color: LecternColors.ink2),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: Space.lg),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    alignment: WrapAlignment.center,
                    children: pressable(actions),
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

/// Grey placeholder rows shaped like item rows.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 5, this.pulse = true});
  final int count;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final rows = Column(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: LecternColors.rule)),
            ),
            child: Row(
              children: [
                const Bone(width: 44, height: 52),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Bone(width: i.isEven ? 220 : 160, height: 16),
                      const SizedBox(height: Space.xs),
                      const Bone(width: 120, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (!pulse) return rows;
    return Semantics(
      label: 'Loading',
      child: Pulse(child: rows),
    );
  }
}

/// A short message at the bottom of the screen.
Future<void> copyText(
  BuildContext context,
  String value, {
  required String message,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) showToast(context, message);
  } catch (_) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy manually'),
        content: SelectableText(value),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        width: MediaQuery.sizeOf(context).width > 600 ? 420 : null,
      ),
    );
}

/// A soft opacity pulse for loading placeholders; still when the system asks
/// for reduced motion.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child});
  final Widget child;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      _c.stop();
      return widget.child;
    }
    return FadeTransition(
      opacity: Tween(begin: 0.55, end: 1.0).animate(_c),
      child: widget.child,
    );
  }
}

/// One grey placeholder block.
class Bone extends StatelessWidget {
  const Bone({
    super.key,
    this.width,
    required this.height,
    this.radius = Radii.sm,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: LecternColors.sunk,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Placeholder shaped like a shelf page: header, search, chips, rows.
class ShelfSkeleton extends StatelessWidget {
  const ShelfSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    return Semantics(
      label: 'Loading',
      child: Pulse(
        child: Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(left: narrow ? Space.lg : Space.xxl),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Bone(width: 110, height: 12),
                    SizedBox(height: Space.sm),
                    Bone(width: 260, height: 40),
                    SizedBox(height: Space.sm),
                    Bone(width: 210, height: 16),
                  ],
                ),
              ),
              const SizedBox(height: Space.xl),
              const Bone(height: 54, radius: Radii.md),
              const SizedBox(height: Space.sm),
              const Row(
                children: [
                  Bone(width: 64, height: 34, radius: Radii.pill),
                  SizedBox(width: Space.xs),
                  Bone(width: 120, height: 34, radius: Radii.pill),
                  SizedBox(width: Space.xs),
                  Bone(width: 120, height: 34, radius: Radii.pill),
                ],
              ),
              const SizedBox(height: Space.lg),
              const Bone(width: 90, height: 18),
              const SizedBox(height: Space.xs),
              const SkeletonRows(count: 4, pulse: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder shaped like an item page: back link, code, title, actions and
/// the catalogue card.
class ItemSkeleton extends StatelessWidget {
  const ItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row() => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: LecternColors.rule)),
      ),
      child: const Row(
        children: [
          Bone(width: 70, height: 12),
          SizedBox(width: Space.lg),
          Expanded(child: Bone(height: 14)),
        ],
      ),
    );
    return Semantics(
      label: 'Loading',
      child: Pulse(
        child: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Bone(width: 170, height: 20),
              const SizedBox(height: Space.lg),
              const Row(
                children: [
                  Bone(width: 84, height: 20),
                  SizedBox(width: Space.sm),
                  Bone(width: 112, height: 24),
                ],
              ),
              const SizedBox(height: Space.md),
              const FractionallySizedBox(
                widthFactor: 0.9,
                child: Bone(height: 34),
              ),
              const SizedBox(height: Space.xs),
              const FractionallySizedBox(
                widthFactor: 0.55,
                child: Bone(height: 34),
              ),
              const SizedBox(height: Space.lg),
              const Row(
                children: [
                  Bone(width: 130, height: 48, radius: Radii.md),
                  SizedBox(width: Space.xs),
                  Bone(width: 160, height: 48, radius: Radii.md),
                ],
              ),
              const SizedBox(height: Space.xl),
              Container(
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(
                  color: LecternColors.surface,
                  border: Border.all(color: LecternColors.rule),
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Bone(width: 120, height: 12),
                    const SizedBox(height: Space.sm),
                    for (var i = 0; i < 5; i++) row(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
