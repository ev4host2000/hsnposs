import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/opening_stock_draft_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/opening_stock_post_local_service.dart';
import 'package:mizapos_desktop/services/cloud/sync/opening_stock_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/database_service.dart';

/// Orchestrates draft save → outbox → post pipeline for opening stock.
class TransactionOpeningStockSyncService {
  TransactionOpeningStockSyncService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> createOpeningStockDraftAndPost({
    required String openingStockId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String productId,
    required double openingQuantity,
    DateTime? openingDate,
    String? notes,
  }) async {
    final db = await _databaseService.database;
    final when = openingDate ?? DateTime.now();

    await db.transaction((txn) async {
      await txn.insert('openingStocks', {
        'id': openingStockId,
        'organizationId': organizationId,
        'branchId': branchId,
        'productId': productId,
        'openingQuantity': openingQuantity,
        'openingDate': when.toIso8601String(),
        'notes': notes,
        'openingStatus': 'draft',
        'createdBy': userId,
        'transactionVersion': 0,
        'rowVersion': 1,
      });
    });

    await _enqueueOpeningStockDraftCreate(
      openingStockId: openingStockId,
      organizationId: organizationId,
      branchId: branchId,
      userId: userId,
      productId: productId,
      openingQuantity: openingQuantity,
      openingDate: when,
      notes: notes,
    );

    return OpeningStockPostLocalService(databaseService: _databaseService)
        .postDraft(openingStockId: openingStockId);
  }

  Future<void> _enqueueOpeningStockDraftCreate({
    required String openingStockId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String productId,
    required double openingQuantity,
    required DateTime openingDate,
    String? notes,
  }) async {
    final aggregate = openingStockDraftAggregate(
      id: openingStockId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      productId: productId,
      openingQuantity: openingQuantity,
      openingDate: openingDate,
      notes: notes,
    );

    await TransactionSyncOutboxWriter.recordBestEffort(
      entityType: OpeningStockSyncConstants.entityType,
      operation: 'create',
      entityId: openingStockId,
      organizationId: organizationId,
      branchId: branchId,
      payload: openingStockDraftPushEnvelope(
        aggregateJson: aggregate,
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: _databaseService,
    );
  }
}

String transactionOpeningStockPostFailureMessage(PostingResult result) {
  return result.failureMessage ??
      result.failureCode ??
      'Posting failed at ${result.failedStageId}';
}
