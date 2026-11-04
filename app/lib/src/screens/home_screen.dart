import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../models/models.dart';
import '../models/validation.dart';
import '../services/api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/account.dart';
import '../widgets/layout.dart';
import '../widgets/press.dart';
import '../widgets/paper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// `/app`. Signed out, it explains Lectern and offers sign-in. Signed in, a
/// returning rep sees their shelves first, on any device; a rep with no
/// shelves yet sees the create form first.
class _HomeScreenState extends State<HomeScreen> {
  bool _started = false;
  late AppServices _services;

  /// The rep whose shelves are loaded (or loading).
  String? _loadedFor;
  List<Shelf>? _shelves;
  ApiException? _error;
  bool _creating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _services = AppScope.of(context);
      // Runs once; only rep pages check the sign-in.
      _services.session
        ..addListener(_sync)
        ..start();
      _sync();
    }
  }

  @override
  void dispose() {
    _services.session.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final session = _services.session;
    final address = session.checking ? null : session.address;
    if (address != _loadedFor) {
      _loadedFor = address;
      _shelves = null;
      _error = null;
      _creating = false;
      if (address != null) _load();
    }
    setState(() {});
  }

  Future<void> _load() async {
    final address = _loadedFor;
    setState(() => _error = null);
    try {
      final shelves = await _services.api.myShelves();
      if (mounted && address == _loadedFor) {
        setState(() => _shelves = shelves);
      }
    } on ApiException catch (e) {
      if (mounted && address == _loadedFor) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _services.session;
    final Widget body;
    if (session.checking) {
      // No hero yet: a returning rep should not see the pitch flash by.
      body = const Padding(
        padding: EdgeInsets.only(top: Space.xl),
        child: SkeletonRows(count: 3),
      );
    } else if (!session.signedIn) {
      body = const _SignedOutHome();
    } else {
      body = _signedInHome(context);
    }
    return PageFrame(
      actions: [if (session.signedIn) const AccountMenu()],
      child: body,
    );
  }

  Widget _signedInHome(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < Breakpoints.medium;
    final shelves = _shelves;
    final error = _error;
    final firstShelf = shelves != null && shelves.isEmpty;

    final newShelf = PressScale(
      child: FilledButton.icon(
        onPressed: () => setState(() => _creating = true),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('New shelf'),
      ),
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrows are set in capitals, which would mangle a hex address;
        // the address is in the account pill.
        const Eyebrow('Signed in'),
        const SizedBox(height: Space.xs),
        Semantics(
          header: true,
          child: Text(
            firstShelf ? 'Create your first shelf' : 'Your shelves',
            style: narrow ? text.displaySmall : text.displayMedium,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          firstShelf
              ? 'One shelf per class. Every shelf you create is listed here, '
                    'on any phone or laptop where you sign in with this wallet.'
              : 'They follow your wallet to any phone or laptop.',
          style: text.bodyLarge!.copyWith(color: LecternColors.ink2),
        ),
      ],
    );

    final Widget list;
    if (shelves == null) {
      list = error != null
          ? MessageState(
              icon: Icons.wifi_off_outlined,
              title: 'Could not load your shelves',
              body: error.message,
              compact: true,
              actions: [
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            )
          : const SkeletonRows(count: 2);
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final shelf in shelves) _ShelfRow(shelf: shelf)],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SessionNotice(),
        RuledPaper(
          padding: EdgeInsets.fromLTRB(
            narrow ? Space.lg : Space.xxl,
            Space.lg,
            0,
            Space.lg,
          ),
          child: narrow || firstShelf || _creating
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    if (!firstShelf && !_creating && shelves != null) ...[
                      const SizedBox(height: Space.md),
                      newShelf,
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: Space.lg),
                    if (shelves != null) newShelf,
                  ],
                ),
        ),
        const SizedBox(height: Space.lg),
        if (firstShelf || _creating)
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: PaperCard(
                child: CreateShelfForm(
                  showTitle: !firstShelf,
                  onCancel: firstShelf
                      ? null
                      : () => setState(() => _creating = false),
                ),
              ),
            ),
          ),
        if (!firstShelf) ...[
          if (_creating) const SizedBox(height: Space.xl),
          list,
        ],
        const SizedBox(height: Space.xxl),
        const IndexHeading(number: '01', title: 'Have a shelf link?'),
        const SizedBox(height: Space.md),
        const _OpenLink(),
        if (firstShelf) ...[
          const SizedBox(height: Space.xxl),
          const IndexHeading(number: '02', title: 'How it works'),
          const SizedBox(height: Space.md),
          const _Steps(),
        ],
      ],
    );
  }
}

/// What a visitor who is not signed in sees: the pitch, sign-in, a place to
/// paste a class link, and how it works.
class _SignedOutHome extends StatelessWidget {
  const _SignedOutHome();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= Breakpoints.expanded;
    const intro = _Intro();
    const card = PaperCard(child: SignInPanel());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SessionNotice(),
        RuledPaper(
          padding: EdgeInsets.fromLTRB(
            width < Breakpoints.medium ? Space.lg : Space.xxl,
            Space.xl,
            0,
            Space.xl,
          ),
          child: wide
              ? const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: intro),
                    SizedBox(width: Space.xxl),
                    SizedBox(width: 440, child: card),
                  ],
                )
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    intro,
                    SizedBox(height: Space.xl),
                    card,
                  ],
                ),
        ),
        const SizedBox(height: Space.xxl),
        const IndexHeading(number: '01', title: 'Have a shelf link?'),
        const SizedBox(height: Space.md),
        const _OpenLink(),
        const SizedBox(height: Space.xxl),
        const IndexHeading(number: '02', title: 'How it works'),
        const SizedBox(height: Space.md),
        const _Steps(),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final narrow = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    final headline = narrow ? text.displayMedium! : text.displayLarge!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('For course reps and their classmates'),
        const SizedBox(height: Space.md),
        Semantics(
          header: true,
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Every handout for your class, on '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Highlighter(
                    child: Text('one shelf.', style: headline),
                  ),
                ),
              ],
            ),
            style: headline,
          ),
        ),
        const SizedBox(height: Space.md),
        Text(
          'Course reps upload lecture notes, past questions and assignments '
          'once. Classmates open one link on any phone, with no wallet, no '
          'account and no app to install.',
          style: text.bodyLarge!.copyWith(color: LecternColors.ink2),
        ),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.lg,
          runSpacing: Space.xs,
          children: [
            _Fact(
              icon: Icons.phone_android,
              text: 'Made for phones on mobile data',
            ),
            _Fact(
              icon: Icons.qr_code_2,
              text: 'QR poster for the lecture hall',
            ),
            _Fact(
              icon: Icons.inventory_2_outlined,
              text: 'Files stored on Walrus',
            ),
          ],
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: LecternColors.blue),
      const SizedBox(width: 6),
      Flexible(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    ],
  );
}

/// The form a rep fills in to create a shelf.
class CreateShelfForm extends StatefulWidget {
  const CreateShelfForm({super.key, this.showTitle = true, this.onCancel});

  /// False when the page heading already says what the form is for.
  final bool showTitle;

  /// Shows a Cancel button when the form was opened from "New shelf".
  final VoidCallback? onCancel;

  @override
  State<CreateShelfForm> createState() => _CreateShelfFormState();
}

class _CreateShelfFormState extends State<CreateShelfForm> {
  final _form = GlobalKey<FormState>();
  final _school = TextEditingController();
  final _department = TextEditingController();
  final _level = TextEditingController();
  late final TextEditingController _session;
  bool _busy = false;
  String? _error;
  final _serverErrors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _session = TextEditingController(text: currentSession(DateTime.now()));
    for (final c in [_school, _department, _level, _session]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_school, _department, _level, _session]) {
      c.dispose();
    }
    super.dispose();
  }

  ShelfDraft get _draft => ShelfDraft(
    school: _school.text,
    department: _department.text,
    level: _level.text,
    session: normalizeSession(_session.text) ?? _session.text,
  );

  Future<void> _submit() async {
    _serverErrors.clear();
    if (!_form.currentState!.validate()) return;
    final services = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await services.api.createShelf(_draft);
      if (mounted) context.go('/s/${created.shelf.id}/created');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.field != null) {
          _serverErrors[e.field!] = e.message;
          _form.currentState!.validate();
        } else {
          _error = e.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final preview = _draft.title;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle) ...[
            Text('Create a shelf', style: text.headlineSmall),
            const SizedBox(height: Space.xxs),
          ],
          Text(
            'For one class: a department and level, or a single course.',
            style: text.bodySmall,
          ),
          const SizedBox(height: Space.lg),
          TextFormField(
            controller: _school,
            decoration: const InputDecoration(
              labelText: 'School',
              hintText: 'FUTO',
            ),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                _serverErrors['school'] ??
                validateShortText(v ?? '', label: 'School'),
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _department,
            decoration: const InputDecoration(
              labelText: 'Department or course',
              hintText: 'Computer Science',
            ),
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                _serverErrors['department'] ?? validateDepartment(v ?? ''),
          ),
          const SizedBox(height: Space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _level,
                  decoration: const InputDecoration(
                    labelText: 'Level',
                    hintText: '300 Level',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      _serverErrors['level'] ??
                      validateShortText(v ?? '', label: 'Level', max: 24),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextFormField(
                  controller: _session,
                  decoration: const InputDecoration(
                    labelText: 'Session',
                    hintText: '2026/2027',
                  ),
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) =>
                      _serverErrors['session'] ??
                      validateSession(v ?? '', required: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Semantics(
            label: 'Shelf name preview',
            child: Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: LecternColors.sunk,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Text(
                preview.isEmpty ? 'Your shelf name appears here' : preview,
                style: preview.isEmpty
                    ? text.bodySmall
                    : LecternType.mono.copyWith(color: LecternColors.ink),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            Notice(tone: NoticeTone.error, child: Text(_error!)),
          ],
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? 'Creating…' : 'Create shelf'),
                  ),
                ),
              ),
              if (widget.onCancel != null) ...[
                const SizedBox(width: Space.xs),
                TextButton(
                  onPressed: _busy ? null : widget.onCancel,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Your class gets a public link. Only you can add or change files, '
            'from any device where you sign in with this wallet.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.shelf});
  final Shelf shelf;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final count = shelf.itemCount ?? 0;
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LecternColors.rule)),
      ),
      child: InkWell(
        onTap: () => context.go('/s/${shelf.id}/manage'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Space.md,
            horizontal: Space.xxs,
          ),
          child: Row(
            children: [
              const Icon(Icons.tune, color: LecternColors.blue),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shelf.title.isEmpty ? 'Shelf ${shelf.id}' : shelf.title,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count == 1 ? '1 file' : '$count files',
                      style: LecternType.mono,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Text(
                'Manage',
                style: text.labelLarge!.copyWith(color: LecternColors.blue),
              ),
              const Icon(Icons.chevron_right, color: LecternColors.blue),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenLink extends StatefulWidget {
  const _OpenLink();

  @override
  State<_OpenLink> createState() => _OpenLinkState();
}

class _OpenLinkState extends State<_OpenLink> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final raw = _controller.text;
    final id = shelfIdFromInput(raw);
    if (id == null) {
      setState(
        () => _error = 'Paste a shelf link, like lectern.app/s/k3x9m2qpzt.',
      );
      return;
    }
    // A pasted manage link opens the manage page, which asks the rep to
    // sign in if needed.
    context.go(raw.contains('/s/$id/manage') ? '/s/$id/manage' : '/s/$id');
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _open(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'Shelf link',
                hintText: 'Paste the link from your class group',
                errorText: _error,
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: PressScale(
              child: OutlinedButton(
                onPressed: _open,
                child: const Text('Open'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const steps = [
      (
        'Sign in and create a shelf',
        'Sign in with your Sui wallet, then name the shelf after your class, '
            'for example FUTO · Computer Science · 300 Level.',
      ),
      (
        'Upload files',
        'PDFs, images, Word and PowerPoint files up to 25 MB. Add the course '
            'code, type and semester for each one.',
      ),
      (
        'Share the link',
        'Post it in the class WhatsApp group or print the QR poster. Students '
            'see what is new since their last visit.',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 840 ? 3 : 1;
        final itemWidth = columns == 1
            ? c.maxWidth
            : (c.maxWidth - Space.lg * (columns - 1)) / columns;
        return Wrap(
          spacing: Space.lg,
          runSpacing: Space.lg,
          children: [
            for (var i = 0; i < steps.length; i++)
              SizedBox(
                width: itemWidth,
                child: Container(
                  padding: const EdgeInsets.only(top: Space.sm),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: LecternColors.ink, width: 1.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '0${i + 1}',
                        style: LecternType.code.copyWith(
                          color: LecternColors.blue,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(steps[i].$1, style: text.titleLarge),
                      const SizedBox(height: Space.xxs),
                      Text(
                        steps[i].$2,
                        style: text.bodyMedium!.copyWith(
                          color: LecternColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
