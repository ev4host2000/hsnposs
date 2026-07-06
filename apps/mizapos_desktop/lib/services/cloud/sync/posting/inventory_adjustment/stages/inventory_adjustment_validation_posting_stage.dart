import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Inventory-adjustment post validation — real DB checks, plans effects in stageData.
class InventoryAdjustmentValidationPostingStage extends PostingStage {
  InventoryAdjustmentValidationPostingStage();

  @override
  String get stageId => 'validation';

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    final header = context.aggregate.header;
    final adjustmentId = header.id;
    if (adjustmentId.isEmpty) {
      return const PostingStageResult.failure(
        code: 'missing_id',
        message: 'Header id is required for post',
      );
    }

    if (header.documentType != context.entityType) {
      return const PostingStageResult.failure(
        code: 'document_type_mismatch',
        message: 'document_type must be inventory_adjustment',
      );
    }

    final extra = header is MapTransactionHeader ? header.extra : const {};
    final txn = context.txn;
    final adjustmentDoc =
        await InventoryAdjustmentPostDb.loadAdjustment(txn, adjustmentId);
    if (adjustmentDoc == null) {
      return const PostingStageResult.failure(
        code: 'adjustment_not_found',
        message: 'Adjustment does not exist locally',
      );
    }

    final productId = _optionalString(extra['product_id']) ??
        _optionalString(adjustmentDoc['productId']);
    if (productId == null) {
      return const PostingStageResult.failure(
        code: 'missing_product',
        message: 'product_id is required for post',
      );
    }

    final headerDelta = _asDouble(extra['quantity_delta']);
    final quantityDelta = headerDelta.abs() >= 1e-9
        ? headerDelta
        : _asDouble(adjustmentDoc['quantityDelta']);
    if (quantityDelta.abs() < 1e-9) {
      return const PostingStageResult.failure(
        code: 'invalid_quantity_delta',
        message: 'quantity_delta must be non-zero',
      );
    }

    var adjustmentReason = InventoryAdjustmentPostEffects.normalizeReason(
      Map<String, Object?>.from(extra),
    );
    if (!InventoryAdjustmentPostEffects.allowedReasons
        .contains(adjustmentReason)) {
      adjustmentReason = InventoryAdjustmentPostEffects.normalizeReason({
        'adjustment_reason': adjustmentDoc['adjustmentReason'],
      });
    }
    if (!InventoryAdjustmentPostEffects.allowedReasons
        .contains(adjustmentReason)) {
      return PostingStageResult.failure(
        code: 'invalid_adjustment_reason',
        message:
            'adjustment_reason must be one of ${InventoryAdjustmentPostEffects.allowedReasons.join('/')}',
      );
    }

    context.stageData['resolved_product_id'] = productId;
    context.stageData['resolved_quantity_delta'] = quantityDelta;
    context.stageData['resolved_adjustment_reason'] = adjustmentReason;

    final dbStatus = (adjustmentDoc['adjustmentStatus'] ?? '').toString();
    final dbTxnVersion =
        (adjustmentDoc['transactionVersion'] as int?) ??
        int.tryParse('${adjustmentDoc['transactionVersion']}') ??
        0;

    if (dbStatus == 'posted') {
      if (header.transactionVersion <= dbTxnVersion) {
        context.stageData['idempotent_replay'] = true;
        _loadPlannedEffects(context);
        return const PostingStageResult.proceed();
      }
      return const PostingStageResult.failure(
        code: 'already_posted',
        message: 'Adjustment already posted with newer transaction_version',
      );
    }

    if (dbStatus != 'draft') {
      return PostingStageResult.failure(
        code: 'invalid_status_for_post',
        message: 'Post requires draft adjustmentStatus, got $dbStatus',
      );
    }

    if (header.status != 'draft' && header.status != 'posted') {
      return PostingStageResult.failure(
        code: 'invalid_aggregate_status',
        message:
            'Aggregate status must be draft or posted, got ${header.status}',
      );
    }

    final expectedTxnVersion = dbTxnVersion + 1;
    if (header.transactionVersion != dbTxnVersion &&
        header.transactionVersion != expectedTxnVersion) {
      return PostingStageResult.failure(
        code: 'transaction_version_mismatch',
        message:
            'Expected transaction_version $dbTxnVersion or $expectedTxnVersion, got ${header.transactionVersion}',
      );
    }

    if (await InventoryAdjustmentPostDb.hasPostMovementsForAdjustment(
      txn,
      adjustmentId,
    )) {
      return const PostingStageResult.failure(
        code: 'post_effects_exist',
        message: 'Stock movements already exist for this adjustment',
      );
    }

    if (!await InventoryAdjustmentPostDb.productExists(txn, productId)) {
      return const PostingStageResult.failure(
        code: 'product_not_found',
        message: 'Product does not exist',
      );
    }

    if (context.aggregate.lines.isNotEmpty) {
      return const PostingStageResult.failure(
        code: 'unexpected_lines',
        message: 'Inventory adjustment must not have line items',
      );
    }

    _loadPlannedEffects(context);
    context.stageData['validated_at'] = DateTime.now().toIso8601String();
    return const PostingStageResult.proceed();
  }

  void _loadPlannedEffects(PostingContext context) {
    final idempotentReplay = context.stageData['idempotent_replay'] == true;
    var inventory = idempotentReplay
        ? InventoryAdjustmentPostEffects.readInventory(context.aggregate)
        : null;

    if (inventory == null) {
      final header = context.aggregate.header;
      final extra = header is MapTransactionHeader ? header.extra : const {};
      final createdBy =
          _optionalString(extra['created_by_user_id']) ?? 'sync';
      final productId =
          context.stageData['resolved_product_id']?.toString() ??
          _optionalString(extra['product_id']) ??
          '';
      final quantityDelta =
          context.stageData['resolved_quantity_delta'] as double? ??
          _asDouble(extra['quantity_delta']);
      final adjustmentDate = _optionalString(extra['adjustment_date']);

      inventory = InventoryAdjustmentPostEffects.buildInventory(
        adjustmentId: header.id,
        productId: productId,
        quantityDelta: quantityDelta,
        createdBy: createdBy,
        movementDate: adjustmentDate,
      );
    }

    context.stageData['inventory'] = inventory;
  }

  String? _optionalString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
