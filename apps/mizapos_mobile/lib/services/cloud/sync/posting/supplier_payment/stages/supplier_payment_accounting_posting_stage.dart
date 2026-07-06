import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/supplier_payment/supplier_payment_post_db.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/supplier_payment/supplier_payment_post_effects.dart';

/// Cash out + Cr Supplier ledger — idempotent cash and partner_ledger entries.
class SupplierPaymentAccountingPostingStage extends PostingStage {
  SupplierPaymentAccountingPostingStage();

  @override
  String get stageId => 'accounting';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final cash = context.stageData['cash'];
    final accounting = context.stageData['accounting'];
    if (cash is! SupplierPaymentCashEffect ||
        accounting is! SupplierPaymentAccountingEffect) {
      return const PostingStageResult.failure(
        code: 'effects_not_planned',
        message: 'Validation stage must plan cash and accounting effects',
      );
    }

    final header = context.aggregate.header;
    await SupplierPaymentPostDb.applyCashEffect(
      context.txn,
      effect: cash,
      organizationId: header.companyId,
      branchId: header.branchId,
    );
    await SupplierPaymentPostDb.applyAccountingEffect(
      context.txn,
      effect: accounting,
      organizationId: header.companyId,
      branchId: header.branchId,
    );

    context.stageData['accounting_posted'] = true;
    context.stageData['cash_transactions'] =
        SupplierPaymentPostEffects.cashJson(cash);
    context.stageData['journal_entries'] =
        SupplierPaymentPostEffects.accountingJson(accounting);
    return const PostingStageResult.proceed();
  }
}
