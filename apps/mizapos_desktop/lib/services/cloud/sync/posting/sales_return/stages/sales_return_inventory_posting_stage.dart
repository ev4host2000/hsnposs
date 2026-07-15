import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/sales_return_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/sales_return_post_effects.dart';

/// Creates stock_movements and adds inventory — one movement per line, idempotent.
class SalesReturnInventoryPostingStage extends PostingStage {
  SalesReturnInventoryPostingStage();

  @override
  String get stageId => 'inventory';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final inventory = context.stageData['inventory'];
    if (inventory is! List<SalesReturnInventoryEffect>) {
      return const PostingStageResult.failure(
        code: 'inventory_not_planned',
        message: 'Validation stage must plan inventory effects',
      );
    }

    final header = context.aggregate.header;
    try {
      for (final effect in inventory) {
        await SalesReturnPostDb.applyInventoryEffect(
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
        SalesReturnPostEffects.inventoryJson(inventory);
    return const PostingStageResult.proceed();
  }
}
