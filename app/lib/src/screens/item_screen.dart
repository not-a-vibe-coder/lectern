import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../models/models.dart';
import '../models/validation.dart';
import '../services/api.dart';
import '../services/walrus_service.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/layout.dart';
import '../widgets/paper.dart';
import '../widgets/tags.dart';
import '../widgets/press.dart';
import 'edit_item_dialog.dart';

/// Images up to this size load their preview without asking.
const autoPreviewBytes = 3 * 1024 * 1024;

enum _Want { preview, open, download }

class ItemScreen extends StatefulWidget {
  const ItemScreen({super.key, required this.shelfId, required this.itemId});
  final String shelfId;
  final String itemId;

  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  ItemPage? _page;
  ApiException? _error;
  bool _started = false;

  // Fetching the file through Dartus.
  bool _fetching = false;
  int _received = 0;
  int? _expected;
  Uint8List? _bytes;
  WalrusFailure? _fetchError;
  _Want? _pending;
  bool _tabBlocked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load(initial: true);
    }
  }

  Future<void> _load({bool initial = false}) async {
    final services = AppScope.of(context);
    if (!initial) setState(() => _error = null);
    try {
      final page = await services.api.item(widget.shelfId, widget.itemId);
      if (!mounted) return;
      setState(() => _page = page);
      final item = page.item;
      if (item.kind.isImage && !item.expired && item.size <= autoPreviewBytes) {
        _fetch(_Want.preview);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _fetch(_Want want) async {
    final page = _page;
    if (page == null || _fetching) return;
    if (_bytes != null) {
      _deliver(want, _bytes!);
      return;
    }
    final services = AppScope.of(context);
    setState(() {
      _fetching = true;
      _fetchError = null;
      _received = 0;
      _expected = page.item.size;
      _pending = want;
      _tabBlocked = false;
    });
    try {
      final bytes = await services.walrus.read(
        page.item.blobId,
        patchId: page.item.patchId,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _received = done;
            if (total != null && total > 0) _expected = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _fetching = false;
      });
      _deliver(want, bytes);
    } on WalrusFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _fetchError = e;
      });
    }
  }

  void _deliver(_Want want, Uint8List bytes) {
    final item = _page!.item;
    final browser = AppScope.of(context).browser;
    switch (want) {
      case _Want.preview:
        break;
      case _Want.open:
        final ok = browser.openInNewTab(bytes, mimeType: item.kind.mimeType);
        setState(() => _tabBlocked = !ok);
      case _Want.download:
        browser.download(
          bytes,
          fileName: item.fileName,
          mimeType: item.kind.mimeType,
        );
        showToast(context, 'Saved ${item.fileName}');
    }
  }

  Future<void> _edit(Item item) async {
    final updated = await showEditItemDialog(context, item: item);
    if (updated != null && mounted) {
      setState(() => _page = _page!.withItem(updated));
      showToast(context, 'Details saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final error = _error;
    if (page == null) {
      if (error != null) {
        return PageFrame(
          maxWidth: Breakpoints.readingMax,
          child: error.isNotFound
              ? MessageState(
                  icon: Icons.find_in_page_outlined,
                  title: 'This file is not on the shelf',
                  body:
                      'It may have been removed by the course rep, or the '
                      'link is incomplete.',
                  actions: [
                    FilledButton(
                      onPressed: () => context.go('/s/${widget.shelfId}'),
                      child: const Text('Open the shelf'),
                    ),
                  ],
                )
              : MessageState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Could not load this file',
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
      return const PageFrame(
        maxWidth: Breakpoints.readingMax,
        child: ItemSkeleton(),
      );
    }

    final item = page.item;
    final shelf = page.shelf;
    final text = Theme.of(context).textTheme;
    final narrow = MediaQuery.sizeOf(context).width < Breakpoints.medium;

    return PageFrame(
      maxWidth: Breakpoints.readingMax,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go('/s/${shelf.id}'),
              icon: const Icon(Icons.arrow_back, size: 20),
              label: Text(
                shelf.department.isNotEmpty ? shelf.department : shelf.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                item.courseCode,
                style: LecternType.code.copyWith(fontSize: 17),
              ),
              TypeTag(item.type),
              if (item.hidden)
                const StatusTag('Hidden', icon: Icons.visibility_off_outlined),
            ],
          ),
          const SizedBox(height: Space.sm),
          Semantics(
            header: true,
            child: Text(
              item.title,
              style: narrow ? text.displaySmall : text.displayMedium,
            ),
          ),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Text(
              item.description,
              style: text.bodyLarge!.copyWith(color: LecternColors.ink2),
            ),
          ],
          const SizedBox(height: Space.lg),
          if (item.expired)
            Notice(
              tone: NoticeTone.warning,
              title: 'Storage period ended',
              icon: Icons.hourglass_disabled_outlined,
              child: Text(
                item.expiresAt == null
                    ? 'This file is no longer stored on Walrus. Ask your '
                          'course rep to upload it again.'
                    : 'This file was stored on Walrus until about '
                          '${formatDate(item.expiresAt!)}. Ask your course rep '
                          'to upload it again.',
              ),
            )
          else
            _Actions(
              item: item,
              fetching: _fetching,
              pending: _pending,
              received: _received,
              expected: _expected,
              tabBlocked: _tabBlocked,
              fetchError: _fetchError,
              hasPreview: _bytes != null && item.kind.isImage,
              onOpen: () => _fetch(_Want.open),
              onDownload: () => _fetch(_Want.download),
              onPreview: () => _fetch(_Want.preview),
              onRetry: () => _fetch(_pending ?? _Want.download),
            ),
          if (item.kind.isImage && _bytes != null && !item.expired) ...[
            const SizedBox(height: Space.lg),
            _ImagePreview(bytes: _bytes!, title: item.title),
          ],
          const SizedBox(height: Space.xl),
          _DetailsCard(item: item),
          if (page.canManage) ...[
            const SizedBox(height: Space.lg),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _edit(item),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: const Text('Edit details'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/s/${shelf.id}/manage'),
                  icon: const Icon(Icons.tune, size: 20),
                  label: const Text('Manage shelf'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.item,
    required this.fetching,
    required this.pending,
    required this.received,
    required this.expected,
    required this.tabBlocked,
    required this.fetchError,
    required this.hasPreview,
    required this.onOpen,
    required this.onDownload,
    required this.onPreview,
    required this.onRetry,
  });

  final Item item;
  final bool fetching;
  final _Want? pending;
  final int received;
  final int? expected;
  final bool tabBlocked;
  final WalrusFailure? fetchError;
  final bool hasPreview;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onPreview;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final size = formatBytes(item.size);
    final buttons = <Widget>[
      if (item.kind == FileKind.pdf)
        FilledButton.icon(
          onPressed: fetching ? null : onOpen,
          icon: const Icon(Icons.open_in_new, size: 20),
          label: const Text('Open PDF'),
        ),
      if (item.kind.isImage && !hasPreview)
        FilledButton.icon(
          onPressed: fetching ? null : onPreview,
          icon: const Icon(Icons.image_outlined, size: 20),
          label: Text('Show image ($size)'),
        ),
      if (item.kind == FileKind.pdf || item.kind.isImage)
        OutlinedButton.icon(
          onPressed: fetching ? null : onDownload,
          icon: const Icon(Icons.download, size: 20),
          label: Text('Download ($size)'),
        )
      else
        FilledButton.icon(
          onPressed: fetching ? null : onDownload,
          icon: const Icon(Icons.download, size: 20),
          label: Text('Download ($size)'),
        ),
    ];

    final total = expected ?? item.size;
    final fraction = total > 0 ? (received / total).clamp(0.0, 1.0) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            ...pressable(buttons),
            TextButton.icon(
              onPressed: () async {
                final url = AppScope.of(
                  context,
                ).config.itemUrl(item.shelfId, item.id);
                await copyText(
                  context,
                  url,
                  message: 'Link to this file copied',
                );
              },
              icon: const Icon(Icons.link, size: 20),
              label: const Text('Copy link'),
            ),
          ],
        ),
        if (item.kind == FileKind.docx || item.kind == FileKind.pptx) ...[
          const SizedBox(height: Space.xs),
          Text(
            'Opens in Word, PowerPoint, Google Docs or WPS Office.',
            style: text.bodySmall,
          ),
        ],
        if (fetching) ...[
          const SizedBox(height: Space.md),
          Semantics(
            liveRegion: true,
            label: 'Fetching from Walrus',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: LinearProgressIndicator(
                    value: received > 0 ? fraction : null,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  received > 0
                      ? 'Fetching from Walrus: ${formatBytes(received)} of '
                            '${formatBytes(total)}'
                      : 'Fetching from Walrus…',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
        if (tabBlocked) ...[
          const SizedBox(height: Space.md),
          Notice(
            tone: NoticeTone.info,
            title: 'Your browser blocked the new tab',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The PDF is ready. Tap below to open it.'),
                const SizedBox(height: Space.xs),
                FilledButton(
                  onPressed: onOpen,
                  child: const Text('Open PDF now'),
                ),
              ],
            ),
          ),
        ],
        if (fetchError != null) ...[
          const SizedBox(height: Space.md),
          Notice(
            tone: NoticeTone.error,
            title: fetchError!.notFound
                ? 'File not available'
                : 'Could not fetch the file',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fetchError!.message),
                if (fetchError!.retryable) ...[
                  const SizedBox(height: Space.xs),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.bytes, required this.title});
  final Uint8List bytes;
  final String title;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: LecternColors.surface,
      border: Border.all(color: LecternColors.rule),
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Padding(
      padding: const EdgeInsets.all(Space.xs),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            semanticLabel: 'Preview of $title',
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => const Padding(
              padding: EdgeInsets.all(Space.lg),
              child: Text(
                'This image could not be shown. Download it instead.',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A catalogue card of facts about the file.
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = <(String, Widget)>[
      ('File', SelectableText(item.fileName, style: text.bodyMedium)),
      ('Format', Text(item.kind.label, style: text.bodyMedium)),
      (
        'Size',
        Text(
          formatBytes(item.size),
          style: LecternType.mono.copyWith(color: LecternColors.ink),
        ),
      ),
      (
        'Semester',
        Text(
          '${item.semester.label} (${item.semester.alsoCalled})',
          style: text.bodyMedium,
        ),
      ),
      (
        'Session',
        Text(
          item.session,
          style: LecternType.mono.copyWith(color: LecternColors.ink),
        ),
      ),
      (
        'Added',
        Text(
          '${formatDate(item.createdAt)}, '
          '${formatRelativeDay(item.createdAt, DateTime.now())}',
          style: text.bodyMedium,
        ),
      ),
      (
        'Stored until',
        Text(
          item.expiresAt == null
              ? (item.endEpoch == null
                    ? 'Unknown'
                    : 'Walrus epoch ${item.endEpoch}')
              : 'About ${formatDate(item.expiresAt!)}'
                    '${item.endEpoch == null ? '' : ' (epoch ${item.endEpoch})'}',
          style: text.bodyMedium!.copyWith(
            color: item.expired ? LecternColors.danger : null,
          ),
        ),
      ),
      _idRow(
        context,
        item.patchId == null ? 'Blob ID' : 'Batch blob ID',
        item.blobId,
        what: 'Blob ID',
      ),
      if (item.patchId != null)
        _idRow(context, 'File ID in batch', item.patchId!, what: 'File ID'),
    ];

    return PaperCard(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.md,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: Space.md,
            runSpacing: Space.xxs,
            children: [
              const Eyebrow('Catalogue card'),
              Text('Stored on Walrus', style: text.bodySmall),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final (label, value) in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: LecternColors.rule)),
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final stacked = c.maxWidth < 240;
                  final labelWidget = Text(
                    label,
                    style: text.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [labelWidget, const SizedBox(height: 2), value],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: c.maxWidth < 420 ? 96 : 120,
                        child: labelWidget,
                      ),
                      Expanded(child: value),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: Space.xs),
          Text(
            'The file stays available until its storage period ends, or until '
            'the rep who owns it deletes it.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// A catalogue row with a Walrus ID in mono and a copy button.
(String, Widget) _idRow(
  BuildContext context,
  String label,
  String value, {
  required String what,
}) => (
  label,
  Row(
    children: [
      Expanded(
        child: SelectableText(
          value,
          style: LecternType.mono.copyWith(fontSize: 12),
          maxLines: 2,
        ),
      ),
      IconButton(
        tooltip: 'Copy ${what[0].toLowerCase()}${what.substring(1)}',
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () => copyText(context, value, message: '$what copied'),
      ),
    ],
  ),
);
