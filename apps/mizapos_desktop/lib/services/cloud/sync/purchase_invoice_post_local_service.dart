import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/purchase_invoice_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/purchase_invoice_posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/purchase_invoice_post_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/purchase_invoice_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Executes local purchase-invoice post and enqueues a single `post` outbox event.
class PurchaseInvoicePostLocalService {
  PurchaseInvoicePostLocalService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> postDraft({
    required String invoiceId,
    String? originDeviceId,
  }) async {
    final db = await _databaseService.database;
    PostingResult? result;
    Map<String, dynamic>? envelope;
    MapTransactionAggregate? aggregate;
    var idempotentReplay = false;

    try {
      await db.transaction((txn) async {
        aggregate = await _loadDraftAggregate(txn, invoiceId);
        if (aggregate == null) {
          result = const PostingResult.failed(
            failedStageId: 'validation',
            failureCode: 'invoice_not_found',
            completedStageIds: [],
          );
          abortPostingTransactionIfFailed(result!);
        }

        final pipeline = PurchaseInvoicePostingPipeline.create();
        final context = PostingContext(
          aggregate: aggregate!,
          txn: txn,
          entityType: PurchaseInvoiceSyncConstants.entityType,
        );
        result = await pipeline.run(context);
        idempotentReplay = result!.idempotentReplay;
        abortPostingTransactionIfFailed(result!);

        final postAggregate = _buildPostAggregate(aggregate!, context.stageData);
        envelope = purchaseInvoicePostPushEnvelope(
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
            failureCode: 'invoice_not_found',
            completedStageIds: [],
          );
    }

    if (!idempotentReplay) {
      await TransactionSyncOutboxWriter.record(
        entityType: PurchaseInvoiceSyncConstants.entityType,
        operation: 'post',
        entityId: invoiceId,
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
    String invoiceId,
  ) async {
    final invoice = await PurchaseInvoicePostDb.loadInvoice(txn, invoiceId);
    if (invoice == null) return null;

    final lines = await PurchaseInvoicePostDb.loadInvoiceLines(txn, invoiceId);
    final txnVersion =
        (invoice['transactionVersion'] as int?) ??
        int.tryParse('${invoice['transactionVersion']}') ??
        0;
    final rowVersion =
        (invoice['rowVersion'] as int?) ??
        int.tryParse('${invoice['rowVersion']}') ??
        1;

    return MapTransactionAggregate.fromParts(
      header: {
        'id': invoiceId,
        'company_id': invoice['organizationId'],
        'branch_id': invoice['branchId'],
        'document_type': 'purchase_invoice',
        'status': 'draft',
        'transaction_version': txnVersion,
        'row_version': rowVersion,
        'supplier_id': invoice['supplierId'],
        'invoice_date': invoice['invoiceDate'],
        'payment_type': invoice['paymentType'],
        'line_subtotal': invoice['lineSubtotal'],
        'discount_amount': invoice['discountAmount'],
        'tax_percent': invoice['taxPercent'],
        'total': invoice['total'],
        'paid_amount': invoice['paidAmount'],
        'notes': invoice['notes'],
        'created_by_user_id': invoice['createdBy'],
      },
      lines: purchaseLineMapsFromDb(lines),
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

    return purchaseInvoicePostAggregate(
      id: header.id,
      organizationId: header.companyId,
      branchId: header.branchId,
      createdBy: (extra['created_by_user_id'] ?? 'sync').toString(),
      supplierId: (extra['supplier_id'] ?? '').toString(),
      invoiceDate: DateTime.tryParse(
        (extra['invoice_date'] ?? '').toString(),
      ),
      paymentType: (extra['payment_type'] ?? 'cash').toString(),
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
      inventory: purchaseInventoryJsonFromStageData(stageData),
      accounting: purchaseAccountingJsonFromStageData(stageData),
    );
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
