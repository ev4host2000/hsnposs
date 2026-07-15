import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/sales_return_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_return/sales_return_posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_return_post_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_return_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Executes local sales-return post and enqueues a single `post` outbox event.
class SalesReturnPostLocalService {
  SalesReturnPostLocalService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> postDraft({
    required String returnId,
    String? originDeviceId,
  }) async {
    final db = await _databaseService.database;
    PostingResult? result;
    Map<String, dynamic>? envelope;
    MapTransactionAggregate? aggregate;
    var idempotentReplay = false;

    try {
      await db.transaction((txn) async {
        aggregate = await _loadDraftAggregate(txn, returnId);
        if (aggregate == null) {
          result = const PostingResult.failed(
            failedStageId: 'validation',
            failureCode: 'return_not_found',
            completedStageIds: [],
          );
          abortPostingTransactionIfFailed(result!);
        }

        final pipeline = SalesReturnPostingPipeline.create();
        final context = PostingContext(
          aggregate: aggregate!,
          txn: txn,
          entityType: SalesReturnSyncConstants.entityType,
        );
        result = await pipeline.run(context);
        idempotentReplay = result!.idempotentReplay;
        abortPostingTransactionIfFailed(result!);

        final postAggregate = _buildPostAggregate(aggregate!, context.stageData);
        envelope = salesReturnPostPushEnvelope(
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
            failureCode: 'return_not_found',
            completedStageIds: [],
          );
    }

    if (!idempotentReplay) {
      await TransactionSyncOutboxWriter.record(
        entityType: SalesReturnSyncConstants.entityType,
        operation: 'post',
        entityId: returnId,
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
    String returnId,
  ) async {
    final returnDoc = await SalesReturnPostDb.loadReturn(txn, returnId);
    if (returnDoc == null) return null;

    final lines = await SalesReturnPostDb.loadReturnLines(txn, returnId);
    final txnVersion =
        (returnDoc['transactionVersion'] as int?) ??
        int.tryParse('${returnDoc['transactionVersion']}') ??
        0;
    final rowVersion =
        (returnDoc['rowVersion'] as int?) ??
        int.tryParse('${returnDoc['rowVersion']}') ??
        1;

    return MapTransactionAggregate.fromParts(
      header: {
        'id': returnId,
        'company_id': returnDoc['organizationId'],
        'branch_id': returnDoc['branchId'],
        'document_type': 'sales_return',
        'status': 'draft',
        'transaction_version': txnVersion,
        'row_version': rowVersion,
        'original_invoice_id': returnDoc['originalInvoiceId'],
        'customer_id': returnDoc['customerId'],
        'return_date': returnDoc['returnDate'],
        'refund_payment_type': returnDoc['refundPaymentType'],
        'line_subtotal': returnDoc['lineSubtotal'],
        'discount_amount': returnDoc['discountAmount'],
        'tax_percent': returnDoc['taxPercent'],
        'total': returnDoc['total'],
        'paid_amount': returnDoc['paidAmount'],
        'notes': returnDoc['notes'],
        'created_by_user_id': returnDoc['createdBy'],
      },
      lines: salesReturnLineMapsFromDb(lines),
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

    return salesReturnPostAggregate(
      id: header.id,
      organizationId: header.companyId,
      branchId: header.branchId,
      createdBy: (extra['created_by_user_id'] ?? 'sync').toString(),
      originalInvoiceId: (extra['original_invoice_id'] ?? '').toString(),
      customerId: (extra['customer_id'] ?? '').toString(),
      returnDate: DateTime.tryParse(
        (extra['return_date'] ?? '').toString(),
      ),
      refundPaymentType: (extra['refund_payment_type'] ?? 'cash').toString(),
      lineSubtotal: _asDouble(extra['line_subtotal']),
      discountAmount: _asDouble(extra['discount_amount']),
      taxPercent: _asDouble(extra['tax_percent']),
      total: _asDouble(extra['total']),
      paidAmount: _asDouble(extra['paid_amount']),
      notes: extra['notes']?.toString(),
      transactionVersion: nextTxn,
      rowVersion: nextRow,
      postedAt: postedAt,
      lines: draft.lines.map((l) => l.toJson()).toList(),
      inventory: salesReturnInventoryJsonFromStageData(stageData),
      accounting: salesReturnAccountingJsonFromStageData(stageData),
    );
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
