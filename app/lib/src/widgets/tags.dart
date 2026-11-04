import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'paper.dart';

(Color ink, Color tint, IconData icon) typeStyle(ItemType type) =>
    switch (type) {
      ItemType.lectureNote => (
        LecternColors.lectureInk,
        LecternColors.lectureTint,
        Icons.menu_book_outlined,
      ),
      ItemType.pastQuestion => (
        LecternColors.pastInk,
        LecternColors.pastTint,
        Icons.quiz_outlined,
      ),
      ItemType.assignment => (
        LecternColors.assignmentInk,
        LecternColors.assignmentTint,
        Icons.assignment_outlined,
      ),
      ItemType.other => (
        LecternColors.otherInk,
        LecternColors.otherTint,
        Icons.folder_open_outlined,
      ),
    };

/// "Past question" in its own colour, with an icon so colour is not the only
/// signal.
class TypeTag extends StatelessWidget {
  const TypeTag(this.type, {super.key, this.dense = false});
  final ItemType type;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (ink, tint, icon) = typeStyle(type);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: dense ? 13 : 15, color: ink),
            const SizedBox(width: 4),
            Text(
              type.label,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                color: ink,
                fontSize: dense ? 12 : 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small file badge: PDF, DOC, PPT or IMG.
class KindBadge extends StatelessWidget {
  const KindBadge(this.kind, {super.key, this.muted = false});
  final FileKind kind;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? LecternColors.ink3 : LecternColors.ink;
    return Semantics(
      label: kind.label,
      excludeSemantics: true,
      child: Container(
        width: 44,
        height: 52,
        decoration: BoxDecoration(
          color: LecternColors.surface,
          border: Border.all(
            color: muted ? LecternColors.rule : LecternColors.ruleStrong,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(3),
            bottomLeft: Radius.circular(3),
            bottomRight: Radius.circular(3),
            topRight: Radius.circular(12),
          ),
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          kind.badge,
          style: LecternType.mono.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: color,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// The highlighter "New" mark.
class NewMark extends StatelessWidget {
  const NewMark({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'New since your last visit',
    excludeSemantics: true,
    child: Highlighter(
      child: Text(
        'New',
        style: Theme.of(
          context,
        ).textTheme.labelMedium!.copyWith(color: LecternColors.ink),
      ),
    ),
  );
}

/// A quiet outlined tag such as "Hidden" or "Expired".
class StatusTag extends StatelessWidget {
  const StatusTag(
    this.label, {
    super.key,
    this.icon,
    this.color = LecternColors.ink2,
  });
  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.6)),
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium!.copyWith(color: color, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
