import 'package:flutter/material.dart';

import '../models/browse.dart';
import '../models/models.dart';
import '../models/validation.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/layout.dart';
import '../widgets/paper.dart';
import '../widgets/press.dart';
import '../widgets/tags.dart';

/// The ruled-paper block at the top of a shelf.
class ShelfHeader extends StatelessWidget {
  const ShelfHeader({
    super.key,
    required this.shelf,
    required this.visibleCount,
    this.eyebrow = 'Shelf',
    this.actions = const [],
  });

  final Shelf shelf;
  final int visibleCount;
  final String eyebrow;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final schoolLine = [
      eyebrow,
      if (shelf.school.isNotEmpty) shelf.school,
    ].join(' · ');
    final meta = [
      if (shelf.level.isNotEmpty) shelf.level,
      if (shelf.session.isNotEmpty) shelf.session,
      '$visibleCount ${visibleCount == 1 ? 'file' : 'files'}',
    ].join('  ·  ');

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(schoolLine),
        const SizedBox(height: Space.xs),
        Semantics(
          header: true,
          child: Text(
            shelf.department.isNotEmpty ? shelf.department : shelf.title,
            style: width < Breakpoints.medium
                ? text.displaySmall
                : text.displayMedium,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(meta, style: LecternType.mono.copyWith(fontSize: 14)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: pressable(actions),
          ),
        ],
      ],
    );

    return RuledPaper(
      padding: EdgeInsets.fromLTRB(
        width < Breakpoints.medium ? Space.lg : Space.xxl,
        Space.lg,
        0,
        Space.xl,
      ),
      child: main,
    );
  }
}

/// Search box and type chips.
class BrowseControls extends StatelessWidget {
  const BrowseControls({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.counts,
    required this.newCount,
    required this.searchController,
  });

  final BrowseFilter filter;
  final ValueChanged<BrowseFilter> onChanged;
  final Map<ItemType, int> counts;
  final int newCount;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      Widget? avatar,
    }) => Padding(
      padding: const EdgeInsets.only(right: Space.xs),
      child: ChoiceChip(
        // Filters change tens of times a visit: select near-instantly.
        chipAnimationStyle: ChipAnimationStyle(
          selectAnimation: AnimationStyle(
            duration: const Duration(milliseconds: 80),
            reverseDuration: const Duration(milliseconds: 80),
          ),
        ),
        label: Text(label),
        avatar: avatar,
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: Theme.of(context).textTheme.labelMedium!.copyWith(
          color: selected ? LecternColors.paper : LecternColors.ink,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchController,
          onChanged: (value) => onChanged(filter.copyWith(query: value)),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search titles or course codes',
            prefixIcon: const Icon(Icons.search, color: LecternColors.ink2),
            suffixIcon: filter.query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      searchController.clear();
                      onChanged(filter.copyWith(query: ''));
                    },
                  ),
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
        ),
        const SizedBox(height: Space.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip(
                label: 'All  $total',
                selected: filter.type == null && !filter.onlyNew,
                onTap: () =>
                    onChanged(filter.copyWith(clearType: true, onlyNew: false)),
              ),
              if (newCount > 0)
                chip(
                  label: 'New  $newCount',
                  selected: filter.onlyNew,
                  onTap: () =>
                      onChanged(filter.copyWith(onlyNew: !filter.onlyNew)),
                ),
              for (final type in ItemType.values)
                if (counts[type]! > 0 || filter.type == type)
                  chip(
                    label: '${type.plural}  ${counts[type]}',
                    selected: filter.type == type,
                    onTap: () => onChanged(
                      filter.type == type
                          ? filter.copyWith(clearType: true)
                          : filter.copyWith(type: type),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Items grouped under course-code headings.
class ItemList extends StatelessWidget {
  const ItemList({
    super.key,
    required this.groups,
    required this.query,
    required this.baseline,
    required this.onOpen,
    this.trailingBuilder,
    this.now,
  });

  final List<CourseGroup> groups;
  final String query;
  final DateTime? baseline;
  final ValueChanged<Item> onOpen;
  final Widget Function(Item item)? trailingBuilder;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: Space.xl, bottom: Space.xs),
            child: Semantics(
              header: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  HighlightedText(
                    group.courseCode,
                    query: query,
                    style: LecternType.code.copyWith(fontSize: 18),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    '${group.items.length} ${group.items.length == 1 ? 'file' : 'files'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: LecternColors.ink, thickness: 1.5, height: 1.5),
          for (final item in group.items)
            ItemRow(
              item: item,
              query: query,
              isNew: baseline != null && item.createdAt.isAfter(baseline!),
              onOpen: () => onOpen(item),
              trailing: trailingBuilder?.call(item),
            ),
        ],
      ],
    );
  }
}

class ItemRow extends StatelessWidget {
  const ItemRow({
    super.key,
    required this.item,
    required this.onOpen,
    this.query = '',
    this.isNew = false,
    this.trailing,
  });

  final Item item;
  final VoidCallback onOpen;
  final String query;
  final bool isNew;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = item.hidden || item.expired;
    final meta = [
      item.semester.label,
      item.session,
      formatBytes(item.size),
    ].join(' · ');
    final semanticsLabel = [
      item.title,
      item.type.label,
      item.courseCode,
      meta,
      if (isNew) 'new',
      if (item.hidden) 'hidden',
      if (item.expired) 'storage ended',
    ].join(', ');

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LecternColors.rule)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: semanticsLabel,
              excludeSemantics: true,
              child: FocusRing(
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: Space.md,
                      horizontal: Space.xxs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KindBadge(item.kind, muted: muted),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: Space.xs,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  HighlightedText(
                                    item.title,
                                    query: query,
                                    style: text.titleMedium!.copyWith(
                                      color: muted
                                          ? LecternColors.ink2
                                          : LecternColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: Space.xs,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (isNew) const NewMark(),
                                  TypeTag(item.type, dense: true),
                                  Text(meta, style: text.bodySmall),
                                  if (item.hidden)
                                    const StatusTag(
                                      'Hidden',
                                      icon: Icons.visibility_off_outlined,
                                    ),
                                  if (item.expired)
                                    const StatusTag(
                                      'Storage ended',
                                      icon: Icons.hourglass_disabled_outlined,
                                      color: LecternColors.danger,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.xs),
                        const Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: Icon(
                            Icons.chevron_right,
                            color: LecternColors.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// "3 new since Tue 14 Oct" with a highlighter mark.
class NewSinceBanner extends StatelessWidget {
  const NewSinceBanner({
    super.key,
    required this.count,
    required this.since,
    required this.onShow,
    required this.onDismiss,
  });

  final int count;
  final DateTime since;
  final VoidCallback onShow;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.xs,
          Space.xs,
          Space.xs,
        ),
        decoration: BoxDecoration(
          color: LecternColors.highlighterSoft,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_outlined,
              size: 20,
              color: LecternColors.ink,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$count new ${count == 1 ? 'file' : 'files'}',
                      style: text.titleSmall,
                    ),
                    TextSpan(
                      text:
                          ' since your last visit on ${formatShortDay(since)}',
                    ),
                  ],
                ),
                style: text.bodyMedium,
              ),
            ),
            TextButton(onPressed: onShow, child: const Text('Show')),
            IconButton(
              tooltip: 'Mark all as seen',
              onPressed: onDismiss,
              icon: const Icon(Icons.done_all, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// Results line under the controls: "12 files" or "2 of 30 files match".
class ResultsLine extends StatelessWidget {
  const ResultsLine({
    super.key,
    required this.shown,
    required this.total,
    required this.onClear,
    required this.filtered,
  });

  final int shown;
  final int total;
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Expanded(
            child: Text(
              filtered
                  ? '$shown of $total ${total == 1 ? 'file' : 'files'} match'
                  : '$total ${total == 1 ? 'file' : 'files'}',
              style: text.bodySmall,
            ),
          ),
          if (filtered)
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
        ],
      ),
    );
  }
}

/// Small helper to build the empty state for no matches.
Widget noMatches(BuildContext context, VoidCallback onClear) => MessageState(
  icon: Icons.search_off,
  title: 'No files match',
  body: 'Try a shorter search, or a course code like CSC 301.',
  compact: true,
  actions: [
    OutlinedButton(onPressed: onClear, child: const Text('Clear filters')),
  ],
);
