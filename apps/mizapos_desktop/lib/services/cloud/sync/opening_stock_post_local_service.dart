import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/opening_stock_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/opening_stock_posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/opening_stock_post_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/opening_stock_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Executes local opening-stock post and enqueues a single `post` outbox event.
class OpeningStockPostLocalService {
  OpeningStockPostLocalService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> postDraft({
    required String openingStockId,
    String? originDeviceId,
  }) async {
    final db = await _databaseService.database;
    PostingResult? result;
    Map<String, dynamic>? envelope;
    MapTransactionAggregate? aggregate;
    var idempotentReplay = false;

    try {
      await db.transaction((txn) async {
        aggregate = await _loadDraftAggregate(txn, openingStockId);
        if (aggregate == null) {
          result = const PostingResult.failed(
            failedStageId: 'validation',
            failureCode: 'opening_stock_not_found',
            completedStageIds: [],
          );
          abortPostingTransactionIfFailed(result!);
        }

        final pipeline = OpeningStockPostingPipeline.create();
        final context = PostingContext(
          aggregate: aggregate!,
          txn: txn,
          entityType: OpeningStockSyncConstants.entityType,
        );
        result = await pipeline.run(context);
        idempotentReplay = result!.idempotentReplay;
        abortPostingTransactionIfFailed(result!);

        final postAggregate = _buildPostAggregate(aggregate!, context.stageData);
        envelope = openingStockPostPushEnvelope(
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
            failureCode: 'opening_stock_not_found',
            completedStageIds: [],
          );
    }

    if (!idempotentReplay) {
      await TransactionSyncOutboxWriter.record(
        entityType: OpeningStockSyncConstants.entityType,
        operation: 'post',
        entityId: openingStockId,
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
    String openingStockId,
  ) async {
    final openingStockDoc =
        await OpeningStockPostDb.loadOpeningStock(txn, openingStockId);
    if (openingStockDoc == null) return null;

    final txnVersion =
        (openingStockDoc['transactionVersion'] as int?) ??
        int.tryParse('${openingStockDoc['transactionVersion']}') ??
        0;
    final rowVersion =
        (openingStockDoc['rowVersion'] as int?) ??
        int.tryParse('${openingStockDoc['rowVersion']}') ??
        1;

    return MapTransactionAggregate.fromParts(
      header: {
        'id': openingStockId,
        'company_id': openingStockDoc['organizationId'],
        'branch_id': openingStockDoc['branchId'],
        'document_type': 'opening_stock',
        'status': 'draft',
        'transaction_version': txnVersion,
        'row_version': rowVersion,
        'product_id': openingStockDoc['productId'],
        'opening_quantity': openingStockDoc['openingQuantity'],
        'opening_date': openingStockDoc['openingDate'],
        'notes': openingStockDoc['notes'],
        'created_by_user_id': openingStockDoc['createdBy'],
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

    return openingStockPostAggregate(
      id: header.id,
      organizationId: header.companyId,
      branchId: header.branchId,
      createdBy: (extra['created_by_user_id'] ?? 'sync').toString(),
      productId: (extra['product_id'] ?? '').toString(),
      openingQuantity: _asDouble(extra['opening_quantity']),
      openingDate: DateTime.tryParse(
        (extra['opening_date'] ?? '').toString(),
      ),
      notes: extra['notes']?.toString(),
      transactionVersion: nextTxn,
      rowVersion: nextRow,
      postedAt: postedAt,
      inventory: openingStockInventoryJsonFromStageData(stageData),
    );
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
