import 'package:sui_wallet_web/sui_wallet_web.dart';
import 'package:upload_recovery/walrus_recovery.dart';

import '../models/models.dart';
import 'api.dart';

Future<RecoveryCompletion> finishLecternUpload(
  LecternApi api,
  RecoverySummary job,
  RecoveredUpload stored, {
  required String? Function() signedInAddress,
}) async {
  if (signedInAddress()?.toLowerCase() != job.scope.owner) {
    throw const SuiWalletException(
      SuiWalletErrorKind.accountNotFound,
      'Sign in with the account that started this upload.',
    );
  }
  final shelfId = job.metadata['shelfId'] as String;
  final files = job.metadata['files'] as List;
  if (files.length != (stored.patchIds.isEmpty ? 1 : stored.patchIds.length)) {
    throw StateError('Saved file details do not match the upload');
  }
  try {
    await api.claimUpload(
      shelfId,
      objectId: stored.objectId,
      patchIds: stored.patchIds,
    );
  } on ApiException catch (error) {
    if (error.code != 'ALREADY_CLAIMED') rethrow;
  }
  for (var i = 0; i < files.length; i++) {
    if (signedInAddress()?.toLowerCase() != job.scope.owner) {
      throw const SuiWalletException(
        SuiWalletErrorKind.accountNotFound,
        'Sign in with the account that started this upload.',
      );
    }
    final data = Map<String, Object?>.from(files[i] as Map);
    await api.createItem(
      shelfId,
      blobId: stored.blobId,
      patchId: stored.patchIds.isEmpty ? null : stored.patchIds[i],
      fileName: data['fileName'] as String,
      draft: ItemDraft(
        courseCode: data['courseCode'] as String,
        title: data['title'] as String,
        type: ItemType.fromWire(data['type']),
        semester: Semester.fromWire(data['semester']),
        session: data['session'] as String,
        description: data['description'] as String,
      ),
    );
  }
  return const RecoveryCompletion.complete();
}
