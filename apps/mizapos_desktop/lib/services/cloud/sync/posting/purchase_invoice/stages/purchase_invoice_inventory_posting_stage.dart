import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/purchase_invoice_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/purchase_invoice_post_effects.dart';

class PurchaseInvoiceInventoryPostingStage extends PostingStage {
  PurchaseInvoiceInventoryPostingStage();

  @override
  String get stageId => 'inventory';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final inventory = context.stageData['inventory'];
    if (inventory is! List<PurchaseInvoiceInventoryEffect>) {
      return const PostingStageResult.failure(
        code: 'inventory_not_planned',
        message: 'Validation stage must plan inventory effects',
      );
    }

    if (context.stageData['idempotent_replay'] == true) {
      context.stageData['inventory_posted'] = true;
      context.stageData['inventory_movements'] =
          PurchaseInvoicePostEffects.inventoryJson(inventory);
      return const PostingStageResult.proceed();
    }

    final header = context.aggregate.header;
    try {
      for (final effect in inventory) {
        await PurchaseInvoicePostDb.applyInventoryEffect(
          context.txn,
          effect: effect,
          organizationId: header.companyId,
          branchId: header.branchId,
        );
      }
    } on StateError catch (e) {
      return PostingStageResult.failure(
        code: e.message.split(':').first,
        message: e.message,
      );
    }

    context.stageData['inventory_posted'] = true;
    context.stageData['inventory_movements'] =
        PurchaseInvoicePostEffects.inventoryJson(inventory);
    return const PostingStageResult.proceed();
  }
}
