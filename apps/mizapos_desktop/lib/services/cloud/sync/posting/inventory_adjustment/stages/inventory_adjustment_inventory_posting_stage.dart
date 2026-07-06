import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_effects.dart';

/// Creates stock_movements and updates inventory — idempotent single movement.
class InventoryAdjustmentInventoryPostingStage extends PostingStage {
  InventoryAdjustmentInventoryPostingStage();

  @override
  String get stageId => 'inventory';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final inventory = context.stageData['inventory'];
    if (inventory is! InventoryAdjustmentInventoryEffect) {
      return const PostingStageResult.failure(
        code: 'inventory_not_planned',
        message: 'Validation stage must plan inventory effect',
      );
    }

    final header = context.aggregate.header;
    try {
      await InventoryAdjustmentPostDb.applyInventoryEffect(
        context.txn,
        effect: inventory,
        organizationId: header.companyId,
        branchId: header.branchId,
      );
    } on StateError catch (e) {
      return PostingStageResult.failure(
        code: e.message.split(':').first,
        message: e.message,
      );
    }

    context.stageData['inventory_posted'] = true;
    context.stageData['inventory_movements'] =
        InventoryAdjustmentPostEffects.inventoryJson(inventory);
    return const PostingStageResult.proceed();
  }
}
