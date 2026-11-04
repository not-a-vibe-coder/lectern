import 'dart:async';

import 'package:dartus/dartus.dart'
    show
        InsufficientWalBalanceError,
        WalrusTransactionOutcomeUnknown,
        QuiltBlob,
        WalletTransactionSigner,
        WalrusTransactionSigner,
        WalrusWriteStage;
import 'package:flutter/foundation.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart';
import 'package:upload_recovery/walrus_recovery.dart';

import '../models/models.dart';
import '../models/validation.dart';
import '../platform/browser.dart';
import 'api.dart';
import 'wallet_storage.dart';

enum UploadStage {
  /// Waiting for the rep to press Upload.
  waiting,

  /// In a batch that the rep's wallet is paying for and storing.
  storing,

  /// Stored on Walrus and listed; saving the details to the shelf.
  saving,
  done,
  failed,
}

/// Where a batch is, in the order the rep sees it.
enum BatchStage {
  /// Computing the blob ID in the browser.
  preparing,

  /// Waiting for the wallet to approve and pay for storage.
  approvePayment,

  /// Sending the bytes to the Walrus upload relay.
  uploading,

  /// Waiting for the wallet's second approval, which certifies the files.
  approveFinish,

  /// Asking the server to check the files on Sui and list them.
  listing,
  done,
  failed,
}

/// Why a batch stopped, so the screen can say what to do.
enum BatchProblem {
  /// No wallet connected in this browser.
  walletNotConnected,

  /// The wallet's account is not the one the rep signed in with.
  wrongAccount,

  /// Not enough WAL in the wallet to pay for storage.
  notEnoughWal,

  /// The rep declined an approval in the wallet.
  declined,

  /// Another wallet error (locked, timed out, busy).
  wallet,

  /// The sign-in ended before the files were listed.
  signedOut,

  /// The server refused the files (wrong type, too large, not the rep's).
  refused,

  /// Anything else; trying again continues where it stopped.
  other,
}

/// Files stored together: one blob for one file, or one quilt for several.
/// Either way the wallet approves twice and pays one storage fee. The
/// write is kept after a failure, so trying again never pays twice.
class UploadBatch {
  UploadBatch._(this.tasks, this.files, this.write)
    : total = files.fold(0, (sum, f) => sum + f.contents.length);

  final List<UploadTask> tasks;
  final List<QuiltBlob> files;
  StorageWrite write;

  BatchStage stage = BatchStage.preparing;

  /// The stage the batch was in when it failed.
  BatchStage? failedAt;
  int sent = 0;
  int total;
  BatchProblem? problem;
  String? error;
  StoredUpload? stored;
  bool requiresWalletCheck = false;
  UploadRecoverySession? recoverySession;

  bool get isSingle => files.length == 1;
  bool get failed => stage == BatchStage.failed;

  /// True once the wallet paid for storage: trying again does not pay
  /// again, and the files can no longer change.
  bool get paid => write.paid;

  int get bytes => total;
}

/// One file in the upload queue, with the details the rep typed for it.
class UploadTask extends ChangeNotifier {
  UploadTask({
    required this.id,
    required this.file,
    required int maxBytes,
    required this.courseCode,
    required this.title,
    required this.type,
    required this.semester,
    required this.session,
  }) : kind = FileKind.fromFileName(file.name),
       fileError = validatePickedFile(
         name: file.name,
         size: file.size,
         maxBytes: maxBytes,
       );

  final int id;
  final PickedFile file;
  final FileKind? kind;

  /// Set when the file itself cannot be uploaded (type or size).
  final String? fileError;

  String courseCode;
  String title;
  ItemType type;
  Semester? semester;
  String session;
  String description = '';

  /// Field name -> problem, shown under each field.
  Map<String, String> errors = {};

  UploadStage stage = UploadStage.waiting;
  String? error;
  bool retryable = true;

  /// The batch this file is being stored in, until it is listed.
  UploadBatch? batch;
  UploadBatch? recoveryBatch;

  /// Where the file is stored, once it is listed on the shelf: the blob ID,
  /// plus the quilt patch ID when it was stored in a batch.
  String? blobId;
  String? patchId;
  Item? item;

  bool get stored => blobId != null;

  /// Details can change until the file is on the shelf: they are not part
  /// of the stored bytes.
  bool get canEdit =>
      fileError == null &&
      (stage == UploadStage.waiting || stage == UploadStage.failed);

  bool get isBusy =>
      stage == UploadStage.storing || stage == UploadStage.saving;

  /// In a batch the wallet already paid for: it cannot be removed.
  bool get locked =>
      (batch?.paid ?? false) ||
      (batch?.requiresWalletCheck ?? false) ||
      recoveryBatch?.recoverySession != null;

  void update(void Function(UploadTask task) change) {
    change(this);
    notifyListeners();
  }

  /// Validates the details; returns a draft, or null and fills [errors].
  ItemDraft? validate() {
    final problems = <String, String>{};
    final code = validateCourseCode(courseCode);
    if (code != null) problems['courseCode'] = code;
    final titleProblem = validateTitle(title);
    if (titleProblem != null) problems['title'] = titleProblem;
    if (semester == null) problems['semester'] = 'Choose a semester.';
    final sessionProblem = validateSession(session);
    if (sessionProblem != null) problems['session'] = sessionProblem;
    final note = validateDescription(description);
    if (note != null) problems['description'] = note;
    errors = problems;
    notifyListeners();
    if (problems.isNotEmpty) return null;
    return ItemDraft(
      courseCode: normalizeCourseCode(courseCode)!,
      title: title.trim(),
      type: type,
      semester: semester!,
      session: normalizeSession(session)!,
      description: description.trim(),
    );
  }
}

/// Stores a shelf's files on Walrus with the rep's own wallet, then lists
/// them on the shelf and saves their details.
///
/// Files waiting when the rep presses Upload go together: one file as one
/// blob, several as one quilt (one blob holding every file). Either way the
/// wallet approves twice, once to pay and once to finish, and pays one
/// storage fee for the batch. Batches are capped at [maxBatchBytes] so a
/// phone never holds hundreds of megabytes at once.
class UploadQueue extends ChangeNotifier {
  UploadQueue({
    required this.shelfId,
    required this.storage,
    required this.wallet,
    required this.signedInAddress,
    required this.api,
    required this.maxBytes,
    required this.defaultSession,
    required int suggestedEpochs,
    this.maxBatchBytes = 50 * 1024 * 1024,
    this.listRetryDelay = const Duration(seconds: 2),
    this.onItemCreated,
    this.onSignedOut,
    this.recovery,
  }) : _epochs = suggestedEpochs;

  final String shelfId;
  final WalletStorage storage;
  final WalrusUploadRecovery? recovery;
  final SuiWalletController wallet;

  /// The address the rep signed in with, or null when signed out.
  final String? Function() signedInAddress;
  final LecternApi api;
  final int maxBytes;
  final String defaultSession;
  final int maxBatchBytes;

  /// A full node can trail the wallet by a moment, so listing a fresh blob
  /// is retried after "not found".
  final Duration listRetryDelay;
  final void Function(Item item)? onItemCreated;

  /// Called when the server says the sign-in has ended.
  final void Function()? onSignedOut;

  final _created = StreamController<Item>.broadcast();

  /// Items added to the shelf by this queue.
  Stream<Item> get created => _created.stream;

  final List<UploadTask> tasks = [];
  bool running = false;
  var _nextId = 0;

  /// The batch being stored, or the one that stopped and can be continued.
  UploadBatch? batch;

  int _epochs;

  /// Storage epochs for the next batch. The rep pays for what they pick.
  int get epochs => _epochs;
  set epochs(int value) {
    if (batch?.recoverySession != null) return;
    if (value == _epochs) return;
    _epochs = value;
    notifyListeners();
  }

  String _lastCourseCode = '';
  Semester? _lastSemester;

  bool _waits(UploadTask t) =>
      t.fileError == null &&
      t.batch == null &&
      !t.stored &&
      (t.stage == UploadStage.waiting ||
          (t.stage == UploadStage.failed && t.retryable));

  /// Files the Upload button will act on.
  int get waitingCount =>
      tasks.where((t) => _waits(t) || _needsSaving(t)).length +
      (batch?.failed == true ? batch!.tasks.length : 0);

  int get doneCount => tasks.where((t) => t.stage == UploadStage.done).length;
  int get failedCount => tasks
      .where((t) => t.stage == UploadStage.failed && t.batch == null)
      .length;
  bool get isEmpty => tasks.isEmpty;

  bool _needsSaving(UploadTask t) =>
      t.stored && t.stage == UploadStage.failed && t.retryable;

  /// The sizes of the blobs the next upload would pay for: one per batch.
  /// A batch already paid for costs nothing more.
  List<int> get plannedBatchBytes {
    final sizes = <int>[];
    final current = batch;
    if (current != null && !current.paid && current.stored == null) {
      sizes.add(current.bytes);
    }
    var size = 0;
    for (final t in tasks.where(_waits)) {
      if (size > 0 && size + t.file.size > maxBatchBytes) {
        sizes.add(size);
        size = 0;
      }
      size += t.file.size;
    }
    if (size > 0) sizes.add(size);
    return sizes;
  }

  void addFiles(List<PickedFile> files) {
    for (final file in files) {
      final fromName = courseCodeFromFileName(file.name);
      final task = UploadTask(
        id: _nextId++,
        file: file,
        maxBytes: maxBytes,
        courseCode: fromName ?? _lastCourseCode,
        title: titleFromFileName(file.name),
        type: typeFromFileName(file.name),
        semester: _lastSemester,
        session: defaultSession,
      );
      task.addListener(_remember(task));
      tasks.add(task);
    }
    notifyListeners();
  }

  VoidCallback _remember(UploadTask task) => () {
    if (task.courseCode.trim().isNotEmpty) _lastCourseCode = task.courseCode;
    if (task.semester != null) _lastSemester = task.semester;
  };

  /// Removes a file. Removing a file from a batch that stopped before
  /// payment drops the batch, so the next upload starts afresh; a batch
  /// the wallet already paid for keeps its files.
  void remove(UploadTask task) {
    if (task.isBusy || task.locked) return;
    final current = task.batch;
    if (current != null) _dropBatch(current);
    tasks.remove(task);
    task.dispose();
    notifyListeners();
  }

  void _dropBatch(UploadBatch b) {
    for (final t in b.tasks) {
      t.update((t) {
        t.batch = null;
        t.stage = UploadStage.waiting;
        t.error = null;
      });
    }
    if (batch == b) batch = null;
  }

  void clearFinished() {
    final finished = tasks
        .where(
          (t) =>
              !t.locked && (t.stage == UploadStage.done || t.fileError != null),
        )
        .toList();
    for (final t in finished) {
      tasks.remove(t);
      t.dispose();
    }
    notifyListeners();
  }

  void recovered(String id) {
    final matching = tasks
        .where((task) => task.recoveryBatch?.recoverySession?.id == id)
        .toList();
    for (final task in matching) {
      if (identical(batch, task.recoveryBatch)) batch = null;
      tasks.remove(task);
      task.dispose();
    }
    notifyListeners();
  }

  /// Copies shared details to every editable file.
  void applyToAll({
    String? courseCode,
    ItemType? type,
    Semester? semester,
    String? session,
  }) {
    for (final task in tasks.where((t) => t.canEdit)) {
      task.update((t) {
        if (courseCode != null && courseCode.trim().isNotEmpty) {
          t.courseCode = courseCode;
          t.errors.remove('courseCode');
        }
        if (type != null) t.type = type;
        if (semester != null) {
          t.semester = semester;
          t.errors.remove('semester');
        }
        if (session != null && session.trim().isNotEmpty) {
          t.session = session;
          t.errors.remove('session');
        }
      });
    }
    notifyListeners();
  }

  /// Checks every file's details, then stores and lists them: first the
  /// batch that stopped (continuing where it stopped), then the files
  /// waiting, in batches. Returns the number of files with details to fix
  /// (nothing is stored when it is not zero).
  Future<int> startAll() async {
    if (running) return 0;
    final current = batch;
    final pending = [
      if (current != null && current.failed) ...current.tasks,
      ...tasks.where((t) => _waits(t) || _needsSaving(t)),
    ];
    var invalid = 0;
    for (final task in pending) {
      if (task.validate() == null) invalid++;
    }
    if (invalid > 0) {
      notifyListeners();
      return invalid;
    }
    running = true;
    notifyListeners();
    try {
      for (final task in tasks.where(_needsSaving).toList()) {
        await _saveDetails(task);
      }
      if (current != null && current.failed) {
        if (!await _store(current)) return 0;
      }
      while (true) {
        final next = _nextBatch();
        if (next.isEmpty) break;
        final created = await _newBatch(next);
        if (created == null) continue;
        if (!await _store(created)) break;
      }
    } finally {
      running = false;
      notifyListeners();
    }
    return 0;
  }

  /// Retries saving one file's details (the file is already stored).
  Future<void> retry(UploadTask task) async {
    if (running || task.isBusy) return;
    if (!task.stored) {
      await startAll();
      return;
    }
    running = true;
    notifyListeners();
    try {
      await _saveDetails(task);
    } finally {
      running = false;
      notifyListeners();
    }
  }

  List<UploadTask> _nextBatch() {
    final next = <UploadTask>[];
    var size = 0;
    for (final t in tasks.where(_waits)) {
      if (next.isNotEmpty && size + t.file.size > maxBatchBytes) break;
      next.add(t);
      size += t.file.size;
    }
    return next;
  }

  /// Reads the files and prepares their write; files that cannot be read
  /// are left out with a message.
  Future<UploadBatch?> _newBatch(List<UploadTask> chosen) async {
    final readable = <UploadTask>[];
    final files = <QuiltBlob>[];
    for (final task in chosen) {
      try {
        final bytes = await task.file.readBytes();
        files.add(
          QuiltBlob(
            contents: bytes,
            identifier: _identifier(files.length, task.file.name),
          ),
        );
        readable.add(task);
      } catch (_) {
        task.update((t) {
          t.stage = UploadStage.failed;
          t.error = 'Could not read this file from your device. Pick it again.';
          t.retryable = false;
        });
      }
    }
    if (readable.isEmpty) return null;
    final created = UploadBatch._(readable, files, _writeFor(files, _epochs));
    for (final t in readable) {
      t.update((t) {
        t.batch = created;
        t.error = null;
      });
    }
    return batch = created;
  }

  StorageWrite _writeFor(List<QuiltBlob> files, int epochs) => files.length == 1
      ? storage.single(files.single.contents, epochs: epochs)
      : storage.batch(files, epochs: epochs);

  /// Quilt identifiers must be unique; the file name helps anyone reading
  /// the quilt with other tools.
  static String _identifier(int index, String name) {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final short = safe.length > 60 ? safe.substring(safe.length - 60) : safe;
    return '${index + 1}-$short';
  }

  /// Pays for, stores and lists [b], then saves each file's details.
  /// Returns false when the batch stopped.
  Future<bool> _store(UploadBatch b) async {
    final manager = recovery;
    if (manager == null || b.write is! RecoveryCheckpointSource) {
      return _storeActive(b);
    }
    final owner = signedInAddress();
    if (owner == null || wallet.account?.address != owner) {
      _signer(b);
      return false;
    }
    try {
      if (b.recoverySession == null) {
        if (!b.paid && b.write.epochs != _epochs) {
          b.write = _writeFor(b.files, _epochs);
        }
        b.recoverySession = await manager.bind(
          b.write as RecoveryCheckpointSource,
          owner: owner,
          metadata: _recoveryMetadata(b),
        );
        for (final task in b.tasks) {
          task.recoveryBatch = b;
        }
      } else {
        await b.recoverySession!.activate();
        await b.recoverySession!.updateMetadata(_recoveryMetadata(b));
      }
      final done = await _storeActive(b);
      await _completeRecovery(b);
      return done;
    } on Object catch (error) {
      return _fail(
        b,
        BatchProblem.other,
        error is UploadRecoveryException
            ? error.message
            : 'Could not save this upload in the browser. Its existing progress is kept; try again.',
      );
    } finally {
      await b.recoverySession?.release();
    }
  }

  Map<String, Object?> _recoveryMetadata(UploadBatch b) => {
    'shelfId': shelfId,
    'label': b.tasks.length == 1
        ? b.tasks.single.file.name
        : '${b.tasks.length} files',
    'files': [
      for (final task in b.tasks)
        {
          'fileName': task.file.name,
          ...(task.validate() ??
                  (throw StateError('Fix the file details first.')))
              .toJson(),
        },
    ],
  };

  Future<void> _completeRecovery(UploadBatch b) async {
    if (b.recoverySession != null &&
        b.tasks.every((task) => task.stage == UploadStage.done)) {
      await b.recoverySession!.complete();
      b.recoverySession = null;
      for (final task in b.tasks) {
        task.recoveryBatch = null;
      }
    }
  }

  Future<bool> _storeActive(UploadBatch b) async {
    if (b.requiresWalletCheck) return false;
    // A batch that stopped before payment follows a new choice of epochs.
    if (b.recoverySession == null && !b.paid && b.write.epochs != _epochs) {
      b.write = _writeFor(b.files, _epochs);
    }
    b
      ..problem = null
      ..error = null
      ..failedAt = null;
    for (final t in b.tasks) {
      t.update((t) {
        t.stage = UploadStage.storing;
        t.error = null;
      });
    }

    final signer = _signer(b);
    if (signer == null) return false;

    var stored = b.stored;
    if (stored == null) {
      b.stage = b.paid ? BatchStage.uploading : BatchStage.preparing;
      notifyListeners();
      try {
        stored = b.stored = await b.write.run(
          signer,
          onStage: (stage) {
            b.stage = switch (stage) {
              WalrusWriteStage.encoding => BatchStage.preparing,
              WalrusWriteStage.registering => BatchStage.approvePayment,
              WalrusWriteStage.uploading => BatchStage.uploading,
              WalrusWriteStage.certifying => BatchStage.approveFinish,
            };
            if (stage == WalrusWriteStage.uploading) b.sent = 0;
            notifyListeners();
          },
          onProgress: (sent, total) {
            b.sent = sent;
            if (total != null && total > 0) b.total = total;
            notifyListeners();
          },
        );
      } on InsufficientWalBalanceError {
        return _fail(
          b,
          BatchProblem.notEnoughWal,
          'Your wallet needs a little WAL to pay for storage. In Slush, '
          'open Swap and change some SUI into WAL, then try again.',
        );
      } on WalrusTransactionOutcomeUnknown {
        b.requiresWalletCheck = b.recoverySession == null;
        return _fail(
          b,
          BatchProblem.other,
          b.requiresWalletCheck
              ? walletSubmissionUnknownMessage
              : 'The transaction result is not confirmed. Retry to check the saved transaction and continue.',
        );
      } on SuiWalletException catch (e) {
        final declined = e.kind == SuiWalletErrorKind.rejected;
        final after = b.paid
            ? ' The storage is already paid for. Try again to finish; you '
                  'will not pay twice.'
            : declined
            ? ' Nothing was paid.'
            : '';
        return _fail(
          b,
          declined ? BatchProblem.declined : BatchProblem.wallet,
          '${e.message}$after',
        );
      } on Object catch (e) {
        debugPrint('Walrus write failed: $e');
        return _fail(
          b,
          BatchProblem.other,
          'Storing stopped: ${_plain(e)}. Try again to continue where it '
          'stopped${b.paid ? '; you will not pay twice' : ''}.',
        );
      }
    }

    b.stage = BatchStage.listing;
    notifyListeners();
    try {
      await _list(stored);
    } on ApiException catch (e) {
      if (e.code != 'ALREADY_CLAIMED') {
        if (e.isSignedOut) onSignedOut?.call();
        return _fail(
          b,
          e.isSignedOut
              ? BatchProblem.signedOut
              : e.status == 403 || e.status == 413 || e.status == 415
              ? BatchProblem.refused
              : BatchProblem.other,
          e.isSignedOut
              ? 'Your files are stored on Walrus. Sign in again, then try '
                    'again to add them to the shelf.'
              : 'Your files are stored on Walrus, but the shelf could not '
                    'list them: ${e.message}',
        );
      }
      // Listed already (an earlier try got through): carry on.
    }

    for (var i = 0; i < b.tasks.length; i++) {
      b.tasks[i].update((t) {
        t.blobId = stored!.blobId;
        t.patchId = stored.patchIds.isEmpty ? null : stored.patchIds[i];
        t.batch = null;
      });
    }
    b.stage = BatchStage.done;
    if (batch == b) batch = null;
    notifyListeners();
    for (final task in b.tasks) {
      if (tasks.contains(task)) await _saveDetailsCore(task);
    }
    return true;
  }

  /// The wallet signer for the signed-in rep, or null (and the batch fails
  /// with a plain reason) when the wallet is missing or on another account.
  WalrusTransactionSigner? _signer(UploadBatch b) {
    // The wallet is checked before anything starts; a stop here is about
    // the next approval.
    b.stage = b.paid ? BatchStage.approveFinish : BatchStage.approvePayment;
    final address = signedInAddress();
    if (address == null) {
      _fail(
        b,
        BatchProblem.signedOut,
        'Your sign-in has ended. Sign in again, then try again.',
      );
      return null;
    }
    final account = wallet.account;
    if (account == null) {
      _fail(
        b,
        BatchProblem.walletNotConnected,
        'Connect the wallet you signed in with '
        '(${shortenSuiAddress(address)}). It pays for storage.',
      );
      return null;
    }
    if (account.address != address) {
      _fail(
        b,
        BatchProblem.wrongAccount,
        'Your wallet is on ${shortenSuiAddress(account.address)}, but you '
        'signed in as ${shortenSuiAddress(address)}. Switch to that account '
        'in your wallet, then try again.',
      );
      return null;
    }
    if (recovery != null && b.write is RecoveryCheckpointSource) {
      return recovery!.signer(
        address,
        canContinue: () =>
            signedInAddress() == address && wallet.account?.address == address,
      );
    }
    return WalletTransactionSigner(
      address: account.address,
      isDefinitelyNotCommitted: (error) =>
          error is SuiWalletException && error.definitelyNotSubmitted,
      execute: (tx) async {
        if (signedInAddress() != address ||
            wallet.account?.address != address) {
          throw const SuiWalletException(
            SuiWalletErrorKind.accountNotFound,
            'Your account changed. Switch back to the wallet you signed in '
            'with, then try again.',
            definitelyNotSubmitted: true,
          );
        }
        return (await wallet.signAndExecuteTransaction(tx.json)).digest;
      },
    );
  }

  bool _fail(UploadBatch b, BatchProblem problem, String message) {
    b
      ..failedAt = b.stage
      ..stage = BatchStage.failed
      ..problem = problem
      ..error = message;
    if (problem == BatchProblem.refused) {
      // The server will never list these bytes: drop the batch so the rep
      // can remove the file and upload the others.
      for (final t in b.tasks) {
        t.update((t) {
          t.batch = null;
          t.stage = UploadStage.failed;
          t.error = message;
          t.retryable = false;
        });
      }
      if (batch == b) batch = null;
    } else {
      for (final t in b.tasks) {
        t.update((t) => t.stage = UploadStage.failed);
      }
    }
    notifyListeners();
    return false;
  }

  /// Lists the stored files on the shelf. The server reads Sui through a
  /// GraphQL indexer that can trail the wallet by a few seconds: it may not
  /// see the new object yet (404), or still see it uncertified (409
  /// `BLOB_NOT_CERTIFIED`). Both are retried.
  Future<void> _list(StoredUpload stored) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await api.claimUpload(
          shelfId,
          objectId: stored.objectId,
          patchIds: stored.patchIds,
        );
        return;
      } on ApiException catch (e) {
        final lagging =
            e.status == 404 ||
            (e.status == 409 && e.code == 'BLOB_NOT_CERTIFIED');
        if (!lagging || attempt >= 7) rethrow;
        await Future<void>.delayed(listRetryDelay);
      }
    }
  }

  Future<void> _saveDetails(UploadTask task) async {
    final b = task.recoveryBatch;
    if (b?.recoverySession == null) return _saveDetailsCore(task);
    try {
      await b!.recoverySession!.activate();
      await b.recoverySession!.updateMetadata(_recoveryMetadata(b));
      await _saveDetailsCore(task);
      await _completeRecovery(b);
    } on Object catch (error) {
      task.update((t) {
        t.stage = UploadStage.failed;
        t.error = error is UploadRecoveryException
            ? error.message
            : 'Could not save these details. Check the fields and try again.';
      });
    } finally {
      await b?.recoverySession?.release();
    }
  }

  Future<void> _saveDetailsCore(UploadTask task) async {
    final draft = task.validate();
    if (draft == null) {
      task.update((t) {
        t.stage = UploadStage.failed;
        t.error = 'Fix the details above, then retry.';
        t.retryable = true;
      });
      return;
    }
    task.update((t) {
      t.stage = UploadStage.saving;
      t.error = null;
    });
    try {
      final item = await api.createItem(
        shelfId,
        blobId: task.blobId!,
        patchId: task.patchId,
        fileName: task.file.name,
        draft: draft,
      );
      task.update((t) {
        t.item = item;
        t.stage = UploadStage.done;
      });
      onItemCreated?.call(item);
      _created.add(item);
    } on ApiException catch (e) {
      if (e.isSignedOut) onSignedOut?.call();
      task.update((t) {
        t.stage = UploadStage.failed;
        t.retryable = !e.isOtherOwner && e.status != 409;
        if (e.field != null) t.errors = {...t.errors, e.field!: e.message};
        t.error = e.status == 409
            ? e.message
            : e.isSignedOut
            ? 'The file is stored on Walrus. Sign in again, then retry to '
                  'add it to the shelf.'
            : 'The file is stored on Walrus, but saving its details failed: '
                  '${e.message}';
      });
    }
  }

  static String _plain(Object error) {
    final text = error.toString().replaceFirst(
      RegExp(r'^\w*(Error|Exception): '),
      '',
    );
    final firstLine = text.split('\n').first.trim();
    return firstLine.length > 160
        ? '${firstLine.substring(0, 157)}…'
        : firstLine;
  }

  @override
  void dispose() {
    for (final t in tasks) {
      t.dispose();
    }
    _created.close();
    super.dispose();
  }
}
