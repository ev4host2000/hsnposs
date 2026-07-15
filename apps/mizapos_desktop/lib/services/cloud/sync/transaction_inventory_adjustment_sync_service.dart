import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/inventory_adjustment_draft_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/inventory_adjustment_post_local_service.dart';
import 'package:mizapos_desktop/services/cloud/sync/inventory_adjustment_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/database_service.dart';

/// Orchestrates draft save → outbox → post pipeline for inventory adjustments.
class TransactionInventoryAdjustmentSyncService {
  TransactionInventoryAdjustmentSyncService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> createInventoryAdjustmentDraftAndPost({
    required String adjustmentId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String productId,
    required double quantityDelta,
    required String adjustmentReason,
    DateTime? adjustmentDate,
    String? notes,
  }) async {
    final db = await _databaseService.database;
    final when = adjustmentDate ?? DateTime.now();
    final reason = adjustmentReason.trim().toLowerCase();

    await db.transaction((txn) async {
      await txn.insert('inventoryAdjustments', {
        'id': adjustmentId,
        'organizationId': organizationId,
        'branchId': branchId,
        'productId': productId,
        'quantityDelta': quantityDelta,
        'adjustmentReason': reason,
        'adjustmentDate': when.toIso8601String(),
        'notes': notes,
        'adjustmentStatus': 'draft',
        'createdBy': userId,
        'transactionVersion': 0,
        'rowVersion': 1,
      });
    });

    await _enqueueInventoryAdjustmentDraftCreate(
      adjustmentId: adjustmentId,
      organizationId: organizationId,
      branchId: branchId,
      userId: userId,
      productId: productId,
      quantityDelta: quantityDelta,
      adjustmentReason: reason,
      adjustmentDate: when,
      notes: notes,
    );

    return InventoryAdjustmentPostLocalService(databaseService: _databaseService)
        .postDraft(adjustmentId: adjustmentId);
  }

  Future<void> _enqueueInventoryAdjustmentDraftCreate({
    required String adjustmentId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String productId,
    required double quantityDelta,
    required String adjustmentReason,
    required DateTime adjustmentDate,
    String? notes,
  }) async {
    final aggregate = inventoryAdjustmentDraftAggregate(
      id: adjustmentId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      productId: productId,
      quantityDelta: quantityDelta,
      adjustmentReason: adjustmentReason,
      adjustmentDate: adjustmentDate,
      notes: notes,
    );

    await TransactionSyncOutboxWriter.recordBestEffort(
      entityType: InventoryAdjustmentSyncConstants.entityType,
      operation: 'create',
      entityId: adjustmentId,
      organizationId: organizationId,
      branchId: branchId,
      payload: inventoryAdjustmentDraftPushEnvelope(
        aggregateJson: aggregate,
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: _databaseService,
    );
  }
}

String transactionInventoryAdjustmentPostFailureMessage(PostingResult result) {
  return result.failureMessage ??
      result.failureCode ??
      'Posting failed at ${result.failedStageId}';
}
