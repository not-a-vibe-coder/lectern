import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/validation.dart';
import '../services/upload_queue.dart';
import '../services/wallet_storage.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import '../widgets/press.dart';

/// WAL from FROST (10^9 per WAL), short and plain: "0.0123", "1.25".
String formatWal(BigInt frost) {
  final wal = frost / BigInt.from(1000000000);
  if (wal >= 1) return wal.toStringAsFixed(2);
  if (wal < 0.0001) return 'less than 0.0001';
  final fixed = wal.toStringAsFixed(4);
  return fixed.replaceFirst(RegExp(r'0+$'), '');
}

/// A storage period in words: "about 26 days", "about a year".
String describeEpochs(int epochs, int epochHours) {
  final hours = epochs * epochHours;
  final days = hours / 24;
  if (days < 1) return 'about $hours hours';
  if (days < 1.5) return 'about 1 day';
  if (days <= 31) return 'about ${days.round()} days';
  if (days < 60) return 'about ${(days / 7).round()} weeks';
  if (days < 330) return 'about ${(days / 30).round()} months';
  if (days <= 400) return 'about a year';
  final years = (days / 365).toStringAsFixed(1).replaceFirst('.0', '');
  return 'about $years years';
}

/// Storage periods a rep can pick, with the app's suggestion among them.
/// Walrus stores for at most 53 epochs ahead.
List<int> epochChoices(int suggested) =>
    {1, 2, 4, 7, 13, 26, 53, suggested}.where((e) => e <= 53).toList()..sort();

/// How long to keep the files, and what that costs, shown before the
/// wallet asks for anything.
class StoragePlan extends StatefulWidget {
  const StoragePlan({super.key, required this.queue});
  final UploadQueue queue;

  @override
  State<StoragePlan> createState() => _StoragePlanState();
}

class _StoragePlanState extends State<StoragePlan> {
  final _cache = <String, StorageEstimate>{};
  String? _key;
  StorageEstimate? _estimate;
  bool _failed = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _plan(List<int> sizes, int epochs) {
    final key = '${sizes.join(',')}@$epochs';
    if (key == _key) return;
    _key = key;
    _estimate = null;
    _failed = false;
    _debounce?.cancel();
    if (sizes.isEmpty) {
      _estimate = null;
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final storage = AppScope.of(context).storage;
      try {
        var total = StorageEstimate(
          wal: BigInt.zero,
          relayTipMist: BigInt.zero,
        );
        for (final size in sizes) {
          final one = _cache['$size@$epochs'] ??= await storage.estimate(
            size: size,
            epochs: epochs,
          );
          total = total + one;
        }
        if (!mounted || _key != key) return;
        setState(() {
          _estimate = total;
          _failed = false;
        });
      } on Object catch (e) {
        debugPrint('Storage estimate failed: $e');
        if (!mounted || _key != key) return;
        setState(() {
          _estimate = null;
          _failed = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final queue = widget.queue;
    final text = Theme.of(context).textTheme;
    final hours = services.config.epochDurationHours;
    final sizes = queue.plannedBatchBytes;
    _plan(sizes, queue.epochs);
    final batch = queue.batch;
    final paidAlready = batch != null && batch.failed && batch.paid;

    final String costLine;
    if (sizes.isEmpty && batch != null && batch.paid) {
      costLine =
          'Storage for these files is paid for.'
          '${paidAlready ? ' Your wallet asks once more to finish.' : ''}';
    } else if (sizes.isEmpty) {
      costLine = '';
    } else if (_estimate != null &&
        _key == '${sizes.join(',')}@${queue.epochs}') {
      final batches = sizes.length;
      costLine =
          'About ${formatWal(_estimate!.wal)} WAL for storage'
          '${_estimate!.relayTipMist > BigInt.zero ? ' and ${formatWal(_estimate!.relayTipMist)} SUI for the upload relay' : ''}, '
          'plus SUI for gas${batches > 1 ? ', over $batches batches' : ''}. Your '
          'wallet pays and owns the files.';
    } else if (_failed) {
      costLine =
          'Your wallet shows the cost before you approve. Your wallet pays '
          'and owns the files.';
    } else {
      costLine = 'Working out the cost…';
    }

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: LecternColors.paper,
        border: Border.all(color: LecternColors.rule),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: LecternColors.blue,
              ),
              const SizedBox(width: Space.xs),
              Expanded(child: Text('Storage', style: text.titleSmall)),
            ],
          ),
          const SizedBox(height: Space.sm),
          DropdownButtonFormField<int>(
            key: ValueKey('epochs-${queue.epochs}'),
            initialValue: queue.epochs,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Keep files for',
              helperText:
                  'Lectern suggests '
                  '${describeEpochs(services.config.epochs, hours)} '
                  '(${_epochs(services.config.epochs)}).',
              helperMaxLines: 2,
            ),
            items: [
              for (final e in epochChoices(services.config.epochs))
                DropdownMenuItem(
                  value: e,
                  child: Text(
                    '${_capitalise(describeEpochs(e, hours))} · ${_epochs(e)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: queue.running
                ? null
                : (e) {
                    if (e != null) queue.epochs = e;
                  },
          ),
          if (costLine.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Semantics(
              liveRegion: true,
              identifier: 'lectern-cost',
              child: Text(costLine, style: text.bodyMedium),
            ),
          ],
        ],
      ),
    );
  }

  static String _epochs(int e) => '$e ${e == 1 ? 'epoch' : 'epochs'}';

  static String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// What the rep's wallet and Walrus are doing with the current batch, in
/// four numbered steps, and what to do when it stopped.
class BatchPanel extends StatelessWidget {
  const BatchPanel({super.key, required this.queue, required this.batch});
  final UploadQueue queue;
  final UploadBatch batch;

  static const _steps = ['Prepare', 'Pay', 'Upload', 'Finish'];

  static int _stepOf(BatchStage stage) => switch (stage) {
    BatchStage.preparing => 0,
    BatchStage.approvePayment => 1,
    BatchStage.uploading => 2,
    BatchStage.approveFinish => 3,
    BatchStage.listing || BatchStage.done => 4,
    BatchStage.failed => 0,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final failed = batch.failed;
    final step = _stepOf(
      failed ? batch.failedAt ?? BatchStage.preparing : batch.stage,
    );
    final count = batch.tasks.length;
    final title = count == 1
        ? 'Storing 1 file on Walrus'
        : 'Storing $count files on Walrus, in one batch';

    return Semantics(
      container: true,
      identifier: 'lectern-batch',
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: LecternColors.surface,
          border: Border.all(
            color: failed ? LecternColors.ruleStrong : LecternColors.blue,
          ),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Eyebrow(
              count == 1
                  ? 'One file · two approvals'
                  : '$count files · two approvals',
            ),
            const SizedBox(height: Space.xxs),
            Text(title, style: text.titleMedium),
            const SizedBox(height: Space.sm),
            _StepRow(current: step, failed: failed),
            const Divider(height: Space.lg),
            if (failed) _failure(context) else _progress(context),
          ],
        ),
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (String headline, String detail, bool wallet) = switch (batch.stage) {
      BatchStage.preparing => (
        'Preparing…',
        'Working out the file\'s Walrus ID on this device.',
        false,
      ),
      BatchStage.approvePayment => (
        'Approve the payment in your wallet',
        'This pays WAL for storage and a small SUI fee. Nothing is sent '
            'until you approve.',
        true,
      ),
      BatchStage.uploading => (
        'Uploading ${formatBytes(batch.sent)} of ${formatBytes(batch.total)}',
        'Sending the files to Walrus.',
        false,
      ),
      BatchStage.approveFinish => (
        'Approve once more to finish',
        'This certifies the files on Walrus. There is no second storage fee.',
        true,
      ),
      BatchStage.listing || BatchStage.done => (
        'Adding to the shelf…',
        'Lectern checks the files on Sui, then lists them.',
        false,
      ),
      BatchStage.failed => ('', '', false),
    };
    final uploading = batch.stage == BatchStage.uploading;
    final value = uploading && batch.total > 0
        ? (batch.sent / batch.total).clamp(0.0, 1.0)
        : null;
    return Semantics(
      liveRegion: true,
      identifier: 'lectern-batch-status',
      label: headline,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: wallet
                      ? const _WalletWaiting()
                      : const Padding(
                          padding: EdgeInsets.all(3),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headline, style: text.titleSmall),
                      const SizedBox(height: 2),
                      Text(detail, style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (uploading) ...[
              const SizedBox(height: Space.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: LinearProgressIndicator(value: value, minHeight: 6),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _failure(BuildContext context) {
    final services = AppScope.of(context);
    final problem = batch.problem ?? BatchProblem.other;
    final (NoticeTone tone, String title) = switch (problem) {
      BatchProblem.declined => (NoticeTone.info, 'You declined in your wallet'),
      BatchProblem.notEnoughWal => (
        NoticeTone.warning,
        'Not enough WAL in your wallet',
      ),
      BatchProblem.wrongAccount => (
        NoticeTone.warning,
        'Your wallet is on another account',
      ),
      BatchProblem.walletNotConnected => (
        NoticeTone.warning,
        'Connect your wallet to pay',
      ),
      BatchProblem.signedOut => (NoticeTone.warning, 'Sign in again'),
      BatchProblem.wallet => (NoticeTone.warning, 'Your wallet did not answer'),
      BatchProblem.refused => (NoticeTone.error, 'The shelf refused the files'),
      BatchProblem.other => (NoticeTone.error, 'Storing stopped'),
    };
    return Semantics(
      identifier: 'lectern-batch-status',
      container: true,
      label: '$title. ${batch.error ?? ''}',
      child: Notice(
        tone: tone,
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(batch.error ?? 'Try again to continue.'),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                if (problem == BatchProblem.walletNotConnected)
                  PressScale(
                    child: FilledButton.icon(
                      onPressed: queue.running
                          ? null
                          : () async {
                              if (await services.session.connectWallet(
                                context,
                              )) {
                                await queue.startAll();
                              }
                            },
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 20,
                      ),
                      label: const Text('Connect wallet'),
                    ),
                  )
                else if (!batch.requiresWalletCheck)
                  PressScale(
                    child: OutlinedButton.icon(
                      onPressed: queue.running ? null : queue.startAll,
                      icon: const Icon(Icons.refresh, size: 20),
                      label: const Text('Try again'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Four numbered steps: done (tick), current (blue), to come (grey).
class _StepRow extends StatelessWidget {
  const _StepRow({required this.current, required this.failed});
  final int current;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final steps = BatchPanel._steps;
    return Semantics(
      label:
          'Step ${current >= steps.length ? steps.length : current + 1} of '
          '${steps.length}${failed ? ', stopped' : ''}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _line(i > 0, i <= current)),
                        _StepMark(
                          number: i + 1,
                          done: i < current,
                          active: i == current,
                          failed: failed && i == current,
                        ),
                        Expanded(
                          child: _line(i < steps.length - 1, i < current),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xxs + 2),
                    Text(
                      steps[i],
                      textAlign: TextAlign.center,
                      style: text.bodySmall!.copyWith(
                        color: i == current
                            ? (failed
                                  ? LecternColors.danger
                                  : LecternColors.ink)
                            : i < current
                            ? LecternColors.ink2
                            : LecternColors.ink3,
                        fontWeight: i == current
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The rule joining two steps; green once the step before is done.
  static Widget _line(bool visible, bool done) => Container(
    height: 1.5,
    color: !visible
        ? null
        : done
        ? LecternColors.success
        : LecternColors.rule,
  );
}

class _StepMark extends StatelessWidget {
  const _StepMark({
    required this.number,
    required this.done,
    required this.active,
    required this.failed,
  });
  final int number;
  final bool done;
  final bool active;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final color = failed
        ? LecternColors.danger
        : done
        ? LecternColors.success
        : active
        ? LecternColors.blue
        : LecternColors.ruleStrong;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done || active ? color : LecternColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child: done
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : failed
          ? const Icon(Icons.priority_high, size: 14, color: Colors.white)
          : Text(
              '$number',
              style: LecternType.mono.copyWith(
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : LecternColors.ink3,
              ),
            ),
    );
  }
}

/// A wallet icon with a slow ring, while the wallet waits for the rep.
/// Still under reduced motion.
class _WalletWaiting extends StatelessWidget {
  const _WalletWaiting();

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (!still)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: LecternColors.blue,
              backgroundColor: LecternColors.blueTint,
            ),
          ),
        const Icon(
          Icons.account_balance_wallet_outlined,
          size: 14,
          color: LecternColors.blue,
        ),
      ],
    );
  }
}
