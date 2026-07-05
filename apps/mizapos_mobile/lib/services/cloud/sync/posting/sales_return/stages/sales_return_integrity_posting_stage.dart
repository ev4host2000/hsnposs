import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_integrity_exception.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/sales_return/sales_return_post_db.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/sales_return/sales_return_post_effects.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/shared/post_integrity_verifier.dart';

/// Pre-finalize integrity checks — lines, accounting balance, UUID uniqueness.
class SalesReturnIntegrityPostingStage extends PostingStage {
  SalesReturnIntegrityPostingStage();

  @override
  String get stageId => 'integrity';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    try {
      final inventory = context.stageData['inventory'];
      final accounting = context.stageData['accounting'];
      if (inventory is! List<SalesReturnInventoryEffect> ||
          accounting is! List<SalesReturnAccountingEffect>) {
        throw const PostingIntegrityException(
          'Inventory and accounting effects must be planned before integrity',
        );
      }

      await PostIntegrityVerifier.verify(
        context: context,
        referenceType: 'sale_return',
        loadReturn: SalesReturnPostDb.loadReturn,
        statusColumn: 'returnStatus',
        inventory: inventory
            .map((e) => PostInventoryEffectView(movementId: e.movementId))
            .toList(),
        accounting: accounting
            .map(
              (e) => PostAccountingEffectView(
                entryId: e.entryId,
                amountSigned: e.amountSigned,
              ),
            )
            .toList(),
      );
    } on PostingIntegrityException catch (e) {
      return PostingStageResult.failure(code: e.code, message: e.message);
    }

    context.stageData['integrity_verified'] = true;
    return const PostingStageResult.proceed();
  }
}
