import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/sales_return_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/sales_return_post_effects.dart';

/// Cr Customer / Dr Sales / Dr Tax — idempotent partner_ledger entries.
class SalesReturnAccountingPostingStage extends PostingStage {
  SalesReturnAccountingPostingStage();

  @override
  String get stageId => 'accounting';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final accounting = context.stageData['accounting'];
    if (accounting is! List<SalesReturnAccountingEffect>) {
      return const PostingStageResult.failure(
        code: 'accounting_not_planned',
        message: 'Validation stage must plan accounting effects',
      );
    }

    final header = context.aggregate.header;
    for (final effect in accounting) {
      await SalesReturnPostDb.applyAccountingEffect(
        context.txn,
        effect: effect,
        organizationId: header.companyId,
        branchId: header.branchId,
      );
    }

    context.stageData['accounting_posted'] = true;
    context.stageData['journal_entries'] =
        SalesReturnPostEffects.accountingJson(accounting);
    return const PostingStageResult.proceed();
  }
}
