import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/inventory_adjustment_post_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/inventory_adjustment_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Executes local inventory-adjustment post and enqueues a single `post` outbox event.
class InventoryAdjustmentPostLocalService {
  InventoryAdjustmentPostLocalService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> postDraft({
    required String adjustmentId,
    String? originDeviceId,
  }) async {
    final db = await _databaseService.database;
    PostingResult? result;
    Map<String, dynamic>? envelope;
    MapTransactionAggregate? aggregate;
    var idempotentReplay = false;

    try {
      await db.transaction((txn) async {
        aggregate = await _loadDraftAggregate(txn, adjustmentId);
        if (aggregate == null) {
          result = const PostingResult.failed(
            failedStageId: 'validation',
            failureCode: 'adjustment_not_found',
            completedStageIds: [],
          );
          abortPostingTransactionIfFailed(result!);
        }

        final pipeline = InventoryAdjustmentPostingPipeline.create();
        final context = PostingContext(
          aggregate: aggregate!,
          txn: txn,
          entityType: InventoryAdjustmentSyncConstants.entityType,
        );
        result = await pipeline.run(context);
        idempotentReplay = result!.idempotentReplay;
        abortPostingTransactionIfFailed(result!);

        final postAggregate = _buildPostAggregate(aggregate!, context.stageData);
        envelope = inventoryAdjustmentPostPushEnvelope(
          aggregateJson: postAggregate,
          clientRowVersion: postAggregate['header']['row_version'] as int,
        );
      });
    } on PostingPipelineAbortException catch (e) {
      return e.result;
    }

    if (result == null || !result!.ok || envelope == null || aggregate == null) {
      return result ??
          const PostingResult.failed(
            failedStageId: 'validation',
            failureCode: 'adjustment_not_found',
            completedStageIds: [],
          );
    }

    if (!idempotentReplay) {
      await TransactionSyncOutboxWriter.recordBestEffort(
        entityType: InventoryAdjustmentSyncConstants.entityType,
        operation: 'post',
        entityId: adjustmentId,
        organizationId: aggregate!.header.companyId,
        branchId: aggregate!.header.branchId,
        payload: envelope!,
        databaseService: _databaseService,
      );
    }

    return result!;
  }

  Future<MapTransactionAggregate?> _loadDraftAggregate(
    DatabaseExecutor txn,
    String adjustmentId,
  ) async {
    final adjustmentDoc =
        await InventoryAdjustmentPostDb.loadAdjustment(txn, adjustmentId);
    if (adjustmentDoc == null) return null;

    final txnVersion =
        (adjustmentDoc['transactionVersion'] as int?) ??
        int.tryParse('${adjustmentDoc['transactionVersion']}') ??
        0;
    final rowVersion =
        (adjustmentDoc['rowVersion'] as int?) ??
        int.tryParse('${adjustmentDoc['rowVersion']}') ??
        1;

    return MapTransactionAggregate.fromParts(
      header: {
        'id': adjustmentId,
        'company_id': adjustmentDoc['organizationId'],
        'branch_id': adjustmentDoc['branchId'],
        'document_type': 'inventory_adjustment',
        'status': 'draft',
        'transaction_version': txnVersion,
        'row_version': rowVersion,
        'product_id': adjustmentDoc['productId'],
        'quantity_delta': adjustmentDoc['quantityDelta'],
        'adjustment_reason': adjustmentDoc['adjustmentReason'],
        'adjustment_date': adjustmentDoc['adjustmentDate'],
        'notes': adjustmentDoc['notes'],
        'created_by_user_id': adjustmentDoc['createdBy'],
      },
      lines: const [],
      metadata: {'payload_schema_version': 1},
    );
  }

  Map<String, dynamic> _buildPostAggregate(
    MapTransactionAggregate draft,
    Map<String, Object?> stageData,
  ) {
    final header = draft.header;
    final extra = header.extra;
    final nextTxn = stageData['next_transaction_version'] as int? ??
        header.transactionVersion + 1;
    final nextRow =
        stageData['next_row_version'] as int? ?? header.rowVersion + 1;
    final postedAt =
        stageData['posted_at']?.toString() ?? DateTime.now().toIso8601String();

    return inventoryAdjustmentPostAggregate(
      id: header.id,
      organizationId: header.companyId,
      branchId: header.branchId,
      createdBy: (extra['created_by_user_id'] ?? 'sync').toString(),
      productId: (extra['product_id'] ?? '').toString(),
      quantityDelta: _asDouble(extra['quantity_delta']),
      adjustmentReason: (extra['adjustment_reason'] ?? 'correction').toString(),
      adjustmentDate: DateTime.tryParse(
        (extra['adjustment_date'] ?? '').toString(),
      ),
      notes: extra['notes']?.toString(),
      transactionVersion: nextTxn,
      rowVersion: nextRow,
      postedAt: postedAt,
      inventory: inventoryAdjustmentInventoryJsonFromStageData(stageData),
    );
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
