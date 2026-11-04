import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/models.dart';
import '../models/validation.dart';
import '../services/upload_queue.dart';
import '../theme/tokens.dart';
import '../widgets/layout.dart';
import '../widgets/paper.dart';
import '../widgets/press.dart';
import '../widgets/tags.dart';
import 'item_fields.dart';
import 'wallet_upload.dart';

/// Where a rep adds files, fills in their details and uploads them.
class UploadDesk extends StatelessWidget {
  const UploadDesk({super.key, required this.queue, required this.onOpenItem});

  final UploadQueue queue;
  final ValueChanged<Item> onOpenItem;

  Future<void> _pick(BuildContext context) async {
    final services = AppScope.of(context);
    final files = await services.browser.pickFiles(
      accept: [
        ...FileKind.allExtensions,
        for (final k in FileKind.values) k.mimeType,
      ],
    );
    if (files.isNotEmpty) queue.addFiles(files);
  }

  Future<void> _start(BuildContext context) async {
    final invalid = await queue.startAll();
    if (invalid > 0 && context.mounted) {
      showToast(
        context,
        invalid == 1
            ? 'One file needs details before uploading.'
            : '$invalid files need details before uploading.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final services = AppScope.of(context);
    final maxMb = (services.config.maxUploadBytes / (1024 * 1024)).round();
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final editable = queue.tasks.where((t) => t.canEdit).length;
        final waiting = queue.waitingCount;
        return PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Upload files', style: text.headlineSmall),
              const SizedBox(height: Space.xxs),
              Text(
                'PDF, images, Word (.docx) and PowerPoint (.pptx). Up to '
                '$maxMb MB each. Your wallet pays for storage on Walrus and '
                'owns the files; students download them for free.',
                style: text.bodySmall,
              ),
              const SizedBox(height: Space.md),
              _DropZone(onPick: () => _pick(context), compact: !queue.isEmpty),
              if (editable >= 2) ...[
                const SizedBox(height: Space.lg),
                _ApplyToAll(queue: queue),
              ],
              for (final task in queue.tasks) ...[
                const SizedBox(height: Space.md),
                _TaskCard(
                  key: ValueKey(task.id),
                  task: task,
                  queue: queue,
                  onOpenItem: onOpenItem,
                ),
              ],
              if (!queue.isEmpty) ...[
                const SizedBox(height: Space.lg),
                if (waiting > 0 || queue.batch != null) ...[
                  StoragePlan(queue: queue),
                  const SizedBox(height: Space.md),
                ],
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // A stopped batch has its own Try again, next to the
                    // reason it stopped.
                    if (!(queue.batch?.failed ?? false))
                      PressScale(
                        child: FilledButton.icon(
                          onPressed: queue.running || waiting == 0
                              ? null
                              : () => _start(context),
                          icon: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 20,
                          ),
                          label: Text(_buttonLabel(queue, waiting)),
                        ),
                      ),
                    if (queue.doneCount > 0 && !queue.running)
                      TextButton(
                        onPressed: queue.clearFinished,
                        child: const Text('Clear finished'),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Semantics(
                  liveRegion: true,
                  child: Text(_summary(queue), style: text.bodySmall),
                ),
                if (queue.batch != null) ...[
                  const SizedBox(height: Space.md),
                  BatchPanel(queue: queue, batch: queue.batch!),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  static String _buttonLabel(UploadQueue q, int waiting) {
    if (q.running) return 'Storing…';
    return waiting <= 1 ? 'Upload file' : 'Upload $waiting files';
  }

  static String _summary(UploadQueue q) {
    final total = q.tasks.length;
    final parts = <String>[
      '${q.doneCount} of $total on the shelf',
      if (q.failedCount > 0) '${q.failedCount} need attention',
    ];
    return '${parts.join(' · ')}. Files you add together are stored in one '
        'batch: two wallet approvals and one storage fee.';
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.onPick, required this.compact});
  final VoidCallback onPick;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pointer = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
    return CustomPaint(
      painter: _DashedBorder(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: compact ? Space.md : Space.xl,
        ),
        child: Column(
          children: [
            if (!compact) ...[
              const Icon(
                Icons.note_add_outlined,
                size: 32,
                color: LecternColors.blue,
              ),
              const SizedBox(height: Space.xs),
            ],
            PressScale(
              child: FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add, size: 20),
                label: Text(compact ? 'Add more files' : 'Choose files'),
              ),
            ),
            if (pointer) ...[
              const SizedBox(height: Space.xs),
              Text('or drop them anywhere on this page', style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = LecternColors.ruleStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(Radii.lg),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Shared details for a batch of files.
class _ApplyToAll extends StatefulWidget {
  const _ApplyToAll({required this.queue});
  final UploadQueue queue;

  @override
  State<_ApplyToAll> createState() => _ApplyToAllState();
}

class _ApplyToAllState extends State<_ApplyToAll> {
  final _code = TextEditingController();
  ItemType? _type;
  Semester? _semester;
  late final _session = TextEditingController(
    text: widget.queue.defaultSession,
  );
  String? _codeError;
  String? _sessionError;
  bool? _open;

  @override
  void dispose() {
    _code.dispose();
    _session.dispose();
    super.dispose();
  }

  void _apply() {
    final code = _code.text.trim();
    final session = _session.text.trim();
    setState(() {
      _codeError = code.isEmpty ? null : validateCourseCode(code);
      _sessionError = session.isEmpty ? null : validateSession(session);
    });
    if (_codeError != null || _sessionError != null) return;
    widget.queue.applyToAll(
      courseCode: code.isEmpty ? null : normalizeCourseCode(code),
      type: _type,
      semester: _semester,
      session: session.isEmpty ? null : normalizeSession(session),
    );
    showToast(context, 'Applied to all files');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Open by default on wide screens; folded on phones to save scrolling.
    final open =
        _open ?? MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: LecternColors.blueTint,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Same details for every file?',
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Fill in what they share, then apply.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _open = !open),
                child: Text(open ? 'Hide' : 'Set once'),
              ),
            ],
          ),
          if (open) ...[
            const SizedBox(height: Space.md),
            FieldRow(
              breakpoint: 360,
              children: [
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Course code',
                    hintText: 'CSC 301',
                    errorText: _codeError,
                  ),
                ),
                DropdownButtonFormField<ItemType?>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  hint: const Text('Keep each'),
                  items: [
                    for (final t in ItemType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setState(() => _type = v),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            FieldRow(
              breakpoint: 360,
              children: [
                SemesterPicker(
                  value: _semester,
                  onChanged: (s) => setState(() => _semester = s),
                ),
                TextField(
                  controller: _session,
                  decoration: InputDecoration(
                    labelText: 'Session',
                    hintText: '2026/2027',
                    errorText: _sessionError,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Align(
              alignment: Alignment.centerLeft,
              child: PressScale(
                child: OutlinedButton(
                  onPressed: _apply,
                  child: const Text('Apply to all'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskCard extends StatefulWidget {
  const _TaskCard({
    super.key,
    required this.task,
    required this.queue,
    required this.onOpenItem,
  });

  final UploadTask task;
  final UploadQueue queue;
  final ValueChanged<Item> onOpenItem;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  late final _code = TextEditingController(text: widget.task.courseCode);
  late final _title = TextEditingController(text: widget.task.title);
  late final _session = TextEditingController(text: widget.task.session);
  late final _note = TextEditingController(text: widget.task.description);
  late bool _showNote = widget.task.description.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.task.addListener(_sync);
  }

  @override
  void dispose() {
    widget.task.removeListener(_sync);
    _code.dispose();
    _title.dispose();
    _session.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Pulls values set elsewhere (such as "Apply to all") into the fields.
  void _sync() {
    final t = widget.task;
    if (_code.text != t.courseCode) _code.text = t.courseCode;
    if (_session.text != t.session) _session.text = t.session;
    if (_title.text != t.title) _title.text = t.title;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.task,
      builder: (context, _) {
        final t = widget.task;
        // A stopped batch explains itself below; its files are not in error.
        final failed = t.stage == UploadStage.failed && t.batch == null;
        final borderColor = t.fileError != null || failed
            ? LecternColors.danger
            : t.stage == UploadStage.done
            ? LecternColors.success
            : LecternColors.rule;
        return Semantics(
          container: true,
          label: 'File ${t.file.name}',
          child: Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: LecternColors.paper,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (t.kind != null)
                      KindBadge(t.kind!)
                    else
                      const Icon(Icons.block, color: LecternColors.danger),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.file.name,
                            style: text.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${formatBytes(t.file.size)} · '
                            '${_stageLabel(t, widget.queue)}',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (!t.isBusy && !t.locked && t.stage != UploadStage.done)
                      IconButton(
                        tooltip: 'Remove ${t.file.name}',
                        onPressed: () => widget.queue.remove(t),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                if (t.fileError != null) ...[
                  const SizedBox(height: Space.sm),
                  Notice(tone: NoticeTone.error, child: Text(t.fileError!)),
                ] else if (t.canEdit) ...[
                  const SizedBox(height: Space.md),
                  _fields(t),
                ] else ...[
                  const SizedBox(height: Space.xs),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        normalizeCourseCode(t.courseCode) ?? t.courseCode,
                        style: text.labelMedium,
                      ),
                      TypeTag(t.type, dense: true),
                      Text(t.title, style: text.bodySmall),
                    ],
                  ),
                ],
                _status(context, t),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fields(UploadTask t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldRow(
          breakpoint: 360,
          children: [
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              onChanged: (v) => t.update((t) {
                t.courseCode = v;
                t.errors.remove('courseCode');
              }),
              decoration: InputDecoration(
                labelText: 'Course code',
                hintText: 'CSC 301',
                errorText: t.errors['courseCode'],
              ),
            ),
            TypePicker(
              key: ValueKey('type-${t.type}'),
              value: t.type,
              onChanged: (v) => t.update((t) => t.type = v),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _title,
          onChanged: (v) => t.update((t) {
            t.title = v;
            t.errors.remove('title');
          }),
          decoration: InputDecoration(
            labelText: 'Title',
            errorText: t.errors['title'],
          ),
        ),
        const SizedBox(height: Space.md),
        FieldRow(
          breakpoint: 360,
          children: [
            SemesterPicker(
              key: ValueKey('sem-${t.semester}'),
              value: t.semester,
              errorText: t.errors['semester'],
              onChanged: (v) => t.update((t) {
                t.semester = v;
                t.errors.remove('semester');
              }),
            ),
            TextField(
              controller: _session,
              onChanged: (v) => t.update((t) {
                t.session = v;
                t.errors.remove('session');
              }),
              decoration: InputDecoration(
                labelText: 'Session',
                hintText: '2026/2027',
                errorText: t.errors['session'],
              ),
            ),
          ],
        ),
        if (_showNote) ...[
          const SizedBox(height: Space.md),
          TextField(
            controller: _note,
            maxLength: 280,
            minLines: 2,
            maxLines: 4,
            onChanged: (v) => t.update((t) {
              t.description = v;
              t.errors.remove('description');
            }),
            decoration: InputDecoration(
              labelText: 'Short description (optional)',
              hintText: 'For example: covers weeks 1 to 4',
              errorText: t.errors['description'],
            ),
          ),
        ] else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showNote = true),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a short description'),
            ),
          ),
      ],
    );
  }

  static String _stageLabel(UploadTask t, UploadQueue q) {
    if (t.fileError != null) return 'Cannot upload';
    final batch = t.batch;
    if (batch != null) {
      return switch (batch.stage) {
        BatchStage.preparing => 'Preparing',
        BatchStage.approvePayment ||
        BatchStage.approveFinish => 'Waiting for your wallet',
        BatchStage.uploading => 'Uploading',
        BatchStage.listing || BatchStage.done => 'Adding to the shelf',
        BatchStage.failed =>
          batch.paid ? 'Paid, not finished' : 'Not stored yet',
      };
    }
    return switch (t.stage) {
      UploadStage.waiting => 'Ready',
      UploadStage.storing => 'Storing on Walrus',
      UploadStage.saving => 'Saving details',
      UploadStage.done => 'On the shelf',
      UploadStage.failed =>
        t.stored ? 'Stored, not on the shelf' : 'Not uploaded',
    };
  }

  Widget _status(BuildContext context, UploadTask t) {
    final text = Theme.of(context).textTheme;
    switch (t.stage) {
      case UploadStage.waiting:
      case UploadStage.storing:
        // The batch panel under the list shows the wallet steps.
        return const SizedBox.shrink();
      case UploadStage.saving:
        return Padding(
          padding: const EdgeInsets.only(top: Space.md),
          child: Semantics(
            liveRegion: true,
            label: 'Saving details to the shelf',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: const LinearProgressIndicator(minHeight: 6),
                ),
                const SizedBox(height: Space.xs),
                Text('Saving details to the shelf…', style: text.bodySmall),
              ],
            ),
          ),
        );
      case UploadStage.done:
        return Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: LecternColors.success,
                size: 20,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  'Stored on Walrus and added to the shelf.',
                  style: text.bodyMedium,
                ),
              ),
              if (t.item != null)
                TextButton(
                  onPressed: () => widget.onOpenItem(t.item!),
                  child: const Text('View'),
                ),
            ],
          ),
        );
      case UploadStage.failed:
        // A stopped batch explains itself once, under the list.
        if (t.batch != null) return const SizedBox.shrink();
        if (t.error == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Space.md),
          child: Notice(
            tone: NoticeTone.error,
            title: t.stored ? 'Not added to the shelf' : 'Not uploaded',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.error!),
                if (t.retryable) ...[
                  const SizedBox(height: Space.xs),
                  PressScale(
                    child: OutlinedButton.icon(
                      onPressed: widget.queue.running
                          ? null
                          : () => widget.queue.retry(t),
                      icon: const Icon(Icons.refresh, size: 20),
                      label: Text(t.stored ? 'Retry saving' : 'Retry'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }
}
