import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_post_effects.dart';

/// Dr Customer / Cr Sales / Cr Tax — idempotent partner_ledger entries.
class SalesInvoiceAccountingPostingStage extends PostingStage {
  SalesInvoiceAccountingPostingStage();

  @override
  String get stageId => 'accounting';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final accounting = context.stageData['accounting'];
    if (accounting is! List<SalesInvoiceAccountingEffect>) {
      return const PostingStageResult.failure(
        code: 'accounting_not_planned',
        message: 'Validation stage must plan accounting effects',
      );
    }

    if (context.stageData['idempotent_replay'] == true) {
      context.stageData['accounting_posted'] = true;
      context.stageData['journal_entries'] =
          SalesInvoicePostEffects.accountingJson(accounting);
      return const PostingStageResult.proceed();
    }

    final header = context.aggregate.header;
    for (final effect in accounting) {
      await SalesInvoicePostDb.applyAccountingEffect(
        context.txn,
        effect: effect,
        organizationId: header.companyId,
        branchId: header.branchId,
      );
    }

    context.stageData['accounting_posted'] = true;
    context.stageData['journal_entries'] =
        SalesInvoicePostEffects.accountingJson(accounting);
    return const PostingStageResult.proceed();
  }
}
