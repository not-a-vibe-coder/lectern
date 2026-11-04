import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

/// Exercise-book paper: faint blue rules and a red margin line.
class RuledPaper extends StatelessWidget {
  const RuledPaper({
    super.key,
    required this.child,
    this.lineGap = 32,
    this.showMargin = true,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double lineGap;
  final bool showMargin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RulesPainter(lineGap: lineGap, showMargin: showMargin),
    child: Padding(padding: padding, child: child),
  );
}

class _RulesPainter extends CustomPainter {
  _RulesPainter({required this.lineGap, required this.showMargin});
  final double lineGap;
  final bool showMargin;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = LecternColors.rule.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var y = lineGap; y < size.height; y += lineGap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
    if (showMargin) {
      final x = size.width < 600 ? 8.0 : 20.0;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = LecternColors.margin
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_RulesPainter old) =>
      old.lineGap != lineGap || old.showMargin != showMargin;
}

/// A highlighter swipe behind [child]: a slightly slanted yellow band.
class Highlighter extends StatelessWidget {
  const Highlighter({
    super.key,
    required this.child,
    this.color = LecternColors.highlighter,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SwipePainter(color),
    child: Padding(padding: padding, child: child),
  );
}

class _SwipePainter extends CustomPainter {
  _SwipePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height * 0.18;
    final bottom = size.height * 0.96;
    final slant = math.min(6.0, size.height * 0.2);
    final path = Path()
      ..moveTo(slant, top)
      ..lineTo(size.width, top + 1)
      ..lineTo(size.width - slant, bottom)
      ..lineTo(0, bottom - 1)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwipePainter old) => old.color != color;
}

/// Text with every match of [query] marked in highlighter yellow.
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    super.key,
    required this.query,
    this.style,
    this.maxLines,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );
    }
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    var start = 0;
    while (true) {
      final index = lower.indexOf(q, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + q.length),
          style: const TextStyle(backgroundColor: LecternColors.highlighter),
        ),
      );
      start = index + q.length;
    }
    return Text.rich(
      TextSpan(children: spans, style: style),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// Upper-case mono label used above headings, for example "SHELF".
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: LecternType.eyebrow.copyWith(color: color),
  );
}

/// A numbered section heading in the index style: "01  Course materials".
class IndexHeading extends StatelessWidget {
  const IndexHeading({
    super.key,
    required this.number,
    required this.title,
    this.trailing,
  });

  final String number;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          number,
          style: LecternType.mono.copyWith(color: LecternColors.ink3),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A white card with a hairline border. Paper-like: no shadow.
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.color = LecternColors.surface,
    this.borderColor = LecternColors.rule,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(Radii.lg),
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// A tinted notice box: info, warning, success or error.
enum NoticeTone { info, warning, success, error }

class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.tone,
    required this.child,
    this.icon,
    this.title,
  });

  final NoticeTone tone;
  final Widget child;
  final IconData? icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, defaultIcon) = switch (tone) {
      NoticeTone.info => (
        LecternColors.blueTint,
        LecternColors.blue,
        Icons.info_outline,
      ),
      NoticeTone.warning => (
        LecternColors.warnTint,
        LecternColors.warn,
        Icons.warning_amber_rounded,
      ),
      NoticeTone.success => (
        LecternColors.successTint,
        LecternColors.success,
        Icons.check_circle_outline,
      ),
      NoticeTone.error => (
        LecternColors.dangerTint,
        LecternColors.danger,
        Icons.error_outline,
      ),
    };
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: tone == NoticeTone.error,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border(left: BorderSide(color: fg, width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.md,
            Space.sm,
            Space.md,
            Space.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon ?? defaultIcon, size: 20, color: fg),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(title!, style: text.titleSmall!.copyWith(color: fg)),
                      const SizedBox(height: 2),
                    ],
                    DefaultTextStyle.merge(
                      style: text.bodyMedium!.copyWith(
                        color: LecternColors.ink,
                      ),
                      child: child,
                    ),
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
