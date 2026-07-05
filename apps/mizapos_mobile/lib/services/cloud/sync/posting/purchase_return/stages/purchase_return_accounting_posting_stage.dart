import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/purchase_return_post_db.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/purchase_return_post_effects.dart';

class PurchaseReturnAccountingPostingStage extends PostingStage {
  PurchaseReturnAccountingPostingStage();

  @override
  String get stageId => 'accounting';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final accounting = context.stageData['accounting'];
    if (accounting is! List<PurchaseReturnAccountingEffect>) {
      return const PostingStageResult.failure(
        code: 'accounting_not_planned',
        message: 'Validation stage must plan accounting effects',
      );
    }

    final header = context.aggregate.header;
    for (final effect in accounting) {
      await PurchaseReturnPostDb.applyAccountingEffect(
        context.txn,
        effect: effect,
        organizationId: header.companyId,
        branchId: header.branchId,
      );
    }

    context.stageData['accounting_posted'] = true;
    context.stageData['journal_entries'] =
        PurchaseReturnPostEffects.accountingJson(accounting);
    return const PostingStageResult.proceed();
  }
}
