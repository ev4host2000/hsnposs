import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_integrity_exception.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/shared/inventory_adjustment_integrity_verifier.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Pre-finalize integrity checks — header product, inventory only, no accounting.
class InventoryAdjustmentIntegrityPostingStage extends PostingStage {
  InventoryAdjustmentIntegrityPostingStage();

  @override
  String get stageId => 'integrity';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    try {
      final inventory = context.stageData['inventory'];
      if (inventory is! InventoryAdjustmentInventoryEffect) {
        throw const PostingIntegrityException(
          'Inventory effect must be planned before integrity',
        );
      }

      await InventoryAdjustmentIntegrityVerifier.verify(
        context: context,
        referenceType: 'inventory_adjustment',
        loadAdjustment: InventoryAdjustmentPostDb.loadAdjustment,
        statusColumn: 'adjustmentStatus',
        quantityDelta: _headerQuantityDelta(context),
        inventory: InventoryAdjustmentEffectView(
          movementId: inventory.movementId,
          movementType: inventory.movementType,
          quantity: inventory.quantity,
        ),
      );
    } on PostingIntegrityException catch (e) {
      return PostingStageResult.failure(code: e.code, message: e.message);
    }

    context.stageData['integrity_verified'] = true;
    return const PostingStageResult.proceed();
  }

  double _headerQuantityDelta(PostingContext context) {
    final resolved = context.stageData['resolved_quantity_delta'];
    if (resolved is num) return resolved.toDouble();
    final extra = context.aggregate.header is MapTransactionHeader
        ? (context.aggregate.header as MapTransactionHeader).extra
        : const {};
    final value = extra['quantity_delta'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
