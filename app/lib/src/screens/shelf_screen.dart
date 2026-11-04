import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../models/browse.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../theme/tokens.dart';
import '../widgets/layout.dart';
import '../widgets/paper.dart';
import '../widgets/share.dart';
import 'shelf_widgets.dart';

/// The public shelf: what students see when they open the class link.
class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key, required this.shelfId});
  final String shelfId;

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  ShelfPage? _page;
  ApiException? _error;
  DateTime? _baseline;
  BrowseFilter _filter = const BrowseFilter();
  bool _bannerDismissed = false;
  final _search = TextEditingController();

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load(initial: true);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    final services = AppScope.of(context);
    if (!initial) {
      setState(() => _error = null);
    }
    try {
      final page = await services.api.shelf(widget.shelfId);
      if (!mounted) return;
      final baseline = services.visits.beginVisit(
        widget.shelfId,
        page.serverTime,
      );
      setState(() {
        _page = page;
        _baseline = baseline;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _clearFilters() {
    _search.clear();
    setState(() => _filter = const BrowseFilter());
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final page = _page;
    final error = _error;

    if (page == null) {
      if (error != null) {
        return PageFrame(
          child: error.isNotFound
              ? MessageState(
                  icon: Icons.menu_book_outlined,
                  title: 'This shelf does not exist',
                  body:
                      'The link may be mistyped or cut short. Ask your course '
                      'rep to share it again.',
                  actions: [
                    FilledButton(
                      onPressed: () => context.go('/app'),
                      child: const Text('Go to Lectern'),
                    ),
                  ],
                )
              : MessageState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Could not load this shelf',
                  body: error.message,
                  actions: [
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
        );
      }
      return const PageFrame(child: ShelfSkeleton());
    }

    final shelf = page.shelf;
    final items = page.items;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= Breakpoints.expanded;
    final newCount = countNew(items, _baseline);
    final groups = groupItems(items, filter: _filter, baseline: _baseline);
    final shown = groups.fold<int>(0, (n, g) => n + g.items.length);

    final browse = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (newCount > 0 && !_bannerDismissed && _baseline != null) ...[
          NewSinceBanner(
            count: newCount,
            since: _baseline!,
            onShow: () =>
                setState(() => _filter = _filter.copyWith(onlyNew: true)),
            onDismiss: () {
              services.visits.markAllSeen(shelf.id, page.serverTime);
              setState(() {
                _bannerDismissed = true;
                _baseline = page.serverTime;
                _filter = _filter.copyWith(onlyNew: false);
              });
            },
          ),
          const SizedBox(height: Space.lg),
        ],
        if (items.isEmpty)
          const MessageState(
            icon: Icons.inventory_2_outlined,
            title: 'Nothing on this shelf yet',
            body:
                'Your course rep has not added any files. Check back after '
                'the next lecture.',
          )
        else ...[
          BrowseControls(
            filter: _filter,
            onChanged: (f) => setState(() => _filter = f),
            counts: countByType(items),
            newCount: newCount,
            searchController: _search,
          ),
          const SizedBox(height: Space.xs),
          ResultsLine(
            shown: shown,
            total: items.length,
            filtered: _filter.isActive,
            onClear: _clearFilters,
          ),
          if (groups.isEmpty)
            noMatches(context, _clearFilters)
          else
            ItemList(
              groups: groups,
              query: _filter.query,
              baseline: _baseline,
              onOpen: (item) => context.go('/s/${shelf.id}/i/${item.id}'),
            ),
        ],
        const SizedBox(height: Space.xl),
        Text(
          'Files are stored on Walrus, a decentralised storage network. Each '
          'file stays available until its storage period ends.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );

    return PageFrame(
      actions: [
        if (page.canManage)
          TextButton.icon(
            onPressed: () => context.go('/s/${shelf.id}/manage'),
            icon: const Icon(Icons.tune, size: 20),
            label: const Text('Manage'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShelfHeader(
            shelf: shelf,
            visibleCount: items.length,
            actions: [
              if (!wide)
                FilledButton.icon(
                  onPressed: () => showShareSheet(
                    context,
                    shelfId: shelf.id,
                    title: shelf.title,
                  ),
                  icon: const Icon(Icons.qr_code_2, size: 20),
                  label: const Text('Share shelf'),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: browse),
                const SizedBox(width: Space.xl),
                SizedBox(
                  width: 340,
                  child: PaperCard(
                    child: SharePanel(shelfId: shelf.id, title: shelf.title),
                  ),
                ),
              ],
            )
          else
            browse,
        ],
      ),
    );
  }
}
