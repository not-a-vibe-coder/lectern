import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart' show shortenSuiAddress;
import 'package:upload_recovery/pending_uploads_panel.dart';

import '../app_scope.dart';
import '../models/browse.dart';
import '../models/models.dart';
import '../models/validation.dart';
import '../services/api.dart';
import '../services/rep_session.dart';
import '../services/upload_queue.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/account.dart';
import '../widgets/layout.dart';
import '../widgets/paper.dart';
import '../widgets/share.dart';
import 'edit_item_dialog.dart';
import 'shelf_widgets.dart';
import 'upload_desk.dart';

/// The owner's view of a shelf: upload, edit and hide files.
class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key, required this.shelfId});
  final String shelfId;

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  ShelfPage? _page;
  ApiException? _error;
  bool _started = false;
  late RepSession _session;

  /// The address the page was loaded for; a different sign-in reloads.
  String? _loadedFor;
  UploadQueue? _queue;
  StreamSubscription<Item>? _createdSub;
  StreamSubscription<dynamic>? _dropSub;
  BrowseFilter _filter = const BrowseFilter();
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _session = AppScope.of(context).session..addListener(_sync);
      _session.start();
      _sync();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_sync);
    _detachQueue();
    _search.dispose();
    super.dispose();
  }

  /// Follows the sign-in: load when a rep signs in, clear when they leave.
  void _sync() {
    if (!mounted) return;
    final address = _session.address;
    if (_session.checking || address == _loadedFor) {
      // Nothing to load, but the sign-in state shown may have changed.
      setState(() {});
      return;
    }
    _loadedFor = address;
    _detachQueue();
    setState(() {
      _page = null;
      _error = null;
    });
    if (address != null) _load(initial: true);
  }

  Future<void> _load({bool initial = false}) async {
    final services = AppScope.of(context);
    final address = _loadedFor;
    if (!initial) setState(() => _error = null);
    try {
      final page = await services.api.manage(widget.shelfId);
      if (!mounted || address != _loadedFor) return;
      _attachQueue(services, page);
      setState(() => _page = page);
    } on ApiException catch (e) {
      if (mounted && address == _loadedFor) setState(() => _error = e);
    }
  }

  void _attachQueue(AppServices services, ShelfPage page) {
    if (_queue != null) return;
    final queue = services.uploadsFor(
      widget.shelfId,
      defaultSession: page.shelf.session.isNotEmpty
          ? page.shelf.session
          : currentSession(DateTime.now()),
    );
    _queue = queue;
    _createdSub = queue.created.listen((item) {
      if (!mounted || _page == null) return;
      setState(() {
        _page = _page!.copyWith(
          items: [..._page!.items.where((i) => i.id != item.id), item],
        );
      });
    });
    _dropSub = services.browser.droppedFiles.listen((files) {
      if (mounted) {
        queue.addFiles(files);
        showToast(
          context,
          files.length == 1 ? 'Added 1 file' : 'Added ${files.length} files',
        );
      }
    });
  }

  void _detachQueue() {
    _createdSub?.cancel();
    _dropSub?.cancel();
    _createdSub = null;
    _dropSub = null;
    _queue = null;
  }

  void _replace(Item item) {
    final page = _page!;
    setState(() {
      _page = page.copyWith(
        items: [for (final i in page.items) i.id == item.id ? item : i],
      );
    });
  }

  Future<void> _setHidden(Item item, bool hidden) async {
    final services = AppScope.of(context);
    final address = _loadedFor;
    try {
      final updated = await services.api.updateItem(widget.shelfId, item.id, {
        'hidden': hidden,
      });
      if (!mounted || address != _loadedFor || _page == null) return;
      _replace(updated);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(
              hidden
                  ? 'Hidden from the shelf. The file stays on Walrus until its '
                        'storage period ends.'
                  : 'Back on the shelf.',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _setHidden(updated, !hidden),
            ),
          ),
        );
    } on ApiException catch (e) {
      if (mounted && address == _loadedFor) showToast(context, e.message);
    }
  }

  Future<void> _edit(Item item) async {
    final address = _loadedFor;
    final updated = await showEditItemDialog(context, item: item);
    if (updated != null && mounted && address == _loadedFor && _page != null) {
      _replace(updated);
      showToast(context, 'Details saved');
    }
  }

  Future<void> _editShelf(Shelf shelf) async {
    final services = AppScope.of(context);
    final address = _loadedFor;
    final updated = await showDialog<Shelf>(
      context: context,
      animationStyle: Motion.dialog(context),
      builder: (_) => AppScope(
        services: services,
        child: _EditShelfDialog(shelf: shelf),
      ),
    );
    if (updated != null && mounted && address == _loadedFor && _page != null) {
      setState(() => _page = _page!.copyWith(shelf: updated));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session.checking) return const PageFrame(child: ShelfSkeleton());
    if (!session.signedIn) {
      return PageFrame(
        maxWidth: Breakpoints.readingMax,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Space.lg),
            const PaperCard(
              child: SignInPanel(
                title: 'Sign in to manage this shelf',
                body:
                    'Adding, editing and hiding files needs the Sui wallet '
                    'that created this shelf. Classmates can use the class '
                    'view without signing in.',
              ),
            ),
            const SizedBox(height: Space.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go('/s/${widget.shelfId}'),
                icon: const Icon(Icons.visibility_outlined, size: 20),
                label: const Text('Open the class view'),
              ),
            ),
          ],
        ),
      );
    }
    final page = _page;
    final error = _error;
    if (page == null) {
      if (error != null) {
        if (error.isOtherOwner) {
          return PageFrame(
            maxWidth: Breakpoints.readingMax,
            actions: const [AccountMenu()],
            child: MessageState(
              icon: Icons.no_accounts_outlined,
              title: 'This shelf belongs to another account',
              body:
                  'You are signed in as ${session.info!.shortAddress}. Only '
                  'the wallet that created this shelf can manage it.',
              actions: [
                FilledButton(
                  onPressed: session.busy
                      ? null
                      : () async {
                          final signedOut = await session.signOut(
                            forgetWallet: true,
                          );
                          if (!context.mounted) return;
                          if (signedOut) {
                            await session.signIn(context);
                          } else {
                            showToast(context, session.notice!);
                          }
                        },
                  child: const Text('Use another wallet'),
                ),
                OutlinedButton(
                  onPressed: () => context.go('/s/${widget.shelfId}'),
                  child: const Text('Open the class view'),
                ),
              ],
            ),
          );
        }
        return PageFrame(
          actions: const [AccountMenu()],
          child: error.isNotFound
              ? MessageState(
                  icon: Icons.menu_book_outlined,
                  title: 'This shelf does not exist',
                  body: 'Check the link, or pick a shelf from your list.',
                  actions: [
                    FilledButton(
                      onPressed: () => context.go('/app'),
                      child: const Text('Your shelves'),
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

    final recoveryOwner = session.address!;
    final shelf = page.shelf;
    final items = page.items;
    final visible = items.where((i) => !i.hidden).length;
    final width = MediaQuery.sizeOf(context).width;
    final twoColumns = width >= 1100;

    final desk = UploadDesk(
      queue: _queue!,
      onOpenItem: (item) => context.go('/s/${shelf.id}/i/${item.id}'),
    );
    final contents = _Contents(
      items: items,
      filter: _filter,
      search: _search,
      onFilter: (f) => setState(() => _filter = f),
      onOpen: (item) => context.go('/s/${shelf.id}/i/${item.id}'),
      onEdit: _edit,
      onToggleHidden: (item) => _setHidden(item, !item.hidden),
    );

    return PageFrame(
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/s/${shelf.id}'),
          icon: const Icon(Icons.visibility_outlined, size: 20),
          label: const Text('Student view'),
        ),
        const SizedBox(width: Space.xs),
        const AccountMenu(),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SessionNotice(),
          ShelfHeader(
            shelf: shelf,
            visibleCount: visible,
            eyebrow: 'Manage',
            actions: [
              FilledButton.icon(
                onPressed: () => showShareSheet(
                  context,
                  shelfId: shelf.id,
                  title: shelf.title,
                ),
                icon: const Icon(Icons.qr_code_2, size: 20),
                label: const Text('Share shelf'),
              ),
              OutlinedButton.icon(
                onPressed: () => _editShelf(shelf),
                icon: const Icon(Icons.edit_outlined, size: 20),
                label: const Text('Rename'),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          _OwnerLine(address: session.info!.address),
          if (AppScope.of(context).recovery case final recovery?)
            PendingUploadsPanel(
              recovery: recovery,
              owner: recoveryOwner,
              filter: (job) => job.metadata['shelfId'] == shelf.id,
              canContinue: () => mounted && _session.address == recoveryOwner,
              beforeResume: () async {
                if (!session.wallet.isConnected) {
                  await showLecternWalletPicker(context, session.wallet);
                }
                return mounted && session.address == recoveryOwner;
              },
              onCompleted: (job, _) async {
                _queue?.recovered(job.id);
                await _load();
              },
            ),
          const SizedBox(height: Space.lg),
          if (twoColumns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 480, child: desk),
                const SizedBox(width: Space.xl),
                Expanded(child: contents),
              ],
            )
          else ...[
            desk,
            const SizedBox(height: Space.xl),
            contents,
          ],
        ],
      ),
    );
  }
}

class _Contents extends StatelessWidget {
  const _Contents({
    required this.items,
    required this.filter,
    required this.search,
    required this.onFilter,
    required this.onOpen,
    required this.onEdit,
    required this.onToggleHidden,
  });

  final List<Item> items;
  final BrowseFilter filter;
  final TextEditingController search;
  final ValueChanged<BrowseFilter> onFilter;
  final ValueChanged<Item> onOpen;
  final ValueChanged<Item> onEdit;
  final ValueChanged<Item> onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final groups = groupItems(items, filter: filter);
    final shown = groups.fold<int>(0, (n, g) => n + g.items.length);
    final hidden = items.where((i) => i.hidden).length;
    void clear() {
      search.clear();
      onFilter(const BrowseFilter());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('On this shelf', style: text.headlineSmall),
        const SizedBox(height: Space.xxs),
        Text(
          hidden == 0
              ? 'Everything here is visible to students.'
              : '$hidden hidden from students. Hidden files stay on Walrus '
                    'until their storage period ends. Each one is owned by '
                    'your address, so you can delete it early with Walrus '
                    'tools.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Space.md),
        if (items.isEmpty)
          const MessageState(
            icon: Icons.inventory_2_outlined,
            title: 'No files yet',
            body: 'Add your first lecture note or past question.',
            compact: true,
          )
        else ...[
          BrowseControls(
            filter: filter,
            onChanged: onFilter,
            counts: countByType(items),
            newCount: 0,
            searchController: search,
          ),
          const SizedBox(height: Space.xs),
          ResultsLine(
            shown: shown,
            total: items.length,
            filtered: filter.isActive,
            onClear: clear,
          ),
          if (groups.isEmpty)
            noMatches(context, clear)
          else
            ItemList(
              groups: groups,
              query: filter.query,
              baseline: null,
              onOpen: onOpen,
              trailingBuilder: (item) => PopupMenuButton<String>(
                popUpAnimationStyle: Motion.menu(context),
                tooltip: 'Actions for ${item.title}',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'edit') onEdit(item);
                  if (value == 'hide') onToggleHidden(item);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit details'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'hide',
                    child: ListTile(
                      leading: Icon(
                        item.hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      title: Text(
                        item.hidden ? 'Show on shelf' : 'Hide from shelf',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Who owns the shelf and the files on it, in one quiet line.
class _OwnerLine extends StatelessWidget {
  const _OwnerLine({required this.address});
  final String address;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: LecternColors.ink2,
          ),
        ),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text:
                      'Only your wallet can manage this shelf. Files you '
                      'upload are owned on Sui by ',
                ),
                TextSpan(
                  text: shortenSuiAddress(address),
                  style: LecternType.mono.copyWith(color: LecternColors.ink),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _EditShelfDialog extends StatefulWidget {
  const _EditShelfDialog({required this.shelf});
  final Shelf shelf;

  @override
  State<_EditShelfDialog> createState() => _EditShelfDialogState();
}

class _EditShelfDialogState extends State<_EditShelfDialog> {
  final _form = GlobalKey<FormState>();
  late final _school = TextEditingController(text: widget.shelf.school);
  late final _department = TextEditingController(text: widget.shelf.department);
  late final _level = TextEditingController(text: widget.shelf.level);
  late final _session = TextEditingController(text: widget.shelf.session);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_school, _department, _level, _session]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await AppScope.of(context).api.updateShelf(
        widget.shelf.id,
        ShelfDraft(
          school: _school.text,
          department: _department.text,
          level: _level.text,
          session: normalizeSession(_session.text) ?? _session.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.lg),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Rename shelf', style: text.headlineSmall),
                const SizedBox(height: Space.lg),
                TextFormField(
                  controller: _school,
                  decoration: const InputDecoration(labelText: 'School'),
                  validator: (v) => validateShortText(v ?? '', label: 'School'),
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _department,
                  decoration: const InputDecoration(
                    labelText: 'Department or course',
                  ),
                  validator: (v) => validateDepartment(v ?? ''),
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _level,
                  decoration: const InputDecoration(labelText: 'Level'),
                  validator: (v) =>
                      validateShortText(v ?? '', label: 'Level', max: 24),
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _session,
                  decoration: const InputDecoration(labelText: 'Session'),
                  validator: (v) => validateSession(v ?? '', required: false),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.md),
                  Notice(tone: NoticeTone.error, child: Text(_error!)),
                ],
                const SizedBox(height: Space.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: Space.xs),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
