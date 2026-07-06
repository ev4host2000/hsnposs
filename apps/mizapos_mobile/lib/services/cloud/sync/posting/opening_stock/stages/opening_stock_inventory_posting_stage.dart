import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/opening_stock_post_db.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/opening_stock_post_effects.dart';

/// Creates stock_movements and updates inventory — idempotent single movement.
class OpeningStockInventoryPostingStage extends PostingStage {
  OpeningStockInventoryPostingStage();

  @override
  String get stageId => 'inventory';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final inventory = context.stageData['inventory'];
    if (inventory is! OpeningStockInventoryEffect) {
      return const PostingStageResult.failure(
        code: 'inventory_not_planned',
        message: 'Validation stage must plan inventory effect',
      );
    }

    final header = context.aggregate.header;
    try {
      await OpeningStockPostDb.applyInventoryEffect(
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
        OpeningStockPostEffects.inventoryJson(inventory);
    return const PostingStageResult.proceed();
  }
}
