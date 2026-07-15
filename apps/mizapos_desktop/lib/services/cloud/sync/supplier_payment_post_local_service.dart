import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/supplier_payment_post_db.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/supplier_payment_posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/supplier_payment_post_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/supplier_payment_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Executes local supplier-payment post and enqueues a single `post` outbox event.
class SupplierPaymentPostLocalService {
  SupplierPaymentPostLocalService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> postDraft({
    required String paymentId,
    String? originDeviceId,
  }) async {
    final db = await _databaseService.database;
    PostingResult? result;
    Map<String, dynamic>? envelope;
    MapTransactionAggregate? aggregate;
    var idempotentReplay = false;

    try {
      await db.transaction((txn) async {
        aggregate = await _loadDraftAggregate(txn, paymentId);
        if (aggregate == null) {
          result = const PostingResult.failed(
            failedStageId: 'validation',
            failureCode: 'payment_not_found',
            completedStageIds: [],
          );
          abortPostingTransactionIfFailed(result!);
        }

        final pipeline = SupplierPaymentPostingPipeline.create();
        final context = PostingContext(
          aggregate: aggregate!,
          txn: txn,
          entityType: SupplierPaymentSyncConstants.entityType,
        );
        result = await pipeline.run(context);
        idempotentReplay = result!.idempotentReplay;
        abortPostingTransactionIfFailed(result!);

        final postAggregate = _buildPostAggregate(aggregate!, context.stageData);
        envelope = supplierPaymentPostPushEnvelope(
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
            failureCode: 'payment_not_found',
            completedStageIds: [],
          );
    }

    if (!idempotentReplay) {
      await TransactionSyncOutboxWriter.record(
        entityType: SupplierPaymentSyncConstants.entityType,
        operation: 'post',
        entityId: paymentId,
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
    String paymentId,
  ) async {
    final paymentDoc = await SupplierPaymentPostDb.loadPayment(txn, paymentId);
    if (paymentDoc == null) return null;

    final txnVersion =
        (paymentDoc['transactionVersion'] as int?) ??
        int.tryParse('${paymentDoc['transactionVersion']}') ??
        0;
    final rowVersion =
        (paymentDoc['rowVersion'] as int?) ??
        int.tryParse('${paymentDoc['rowVersion']}') ??
        1;

    return MapTransactionAggregate.fromParts(
      header: {
        'id': paymentId,
        'company_id': paymentDoc['organizationId'],
        'branch_id': paymentDoc['branchId'],
        'document_type': 'supplier_payment',
        'status': 'draft',
        'transaction_version': txnVersion,
        'row_version': rowVersion,
        'supplier_id': paymentDoc['supplierId'],
        'amount': paymentDoc['amount'],
        'payment_date': paymentDoc['paymentDate'],
        'payment_method': paymentDoc['paymentMethod'],
        'voucher_number': paymentDoc['voucherNumber'],
        'notes': paymentDoc['notes'],
        'created_by_user_id': paymentDoc['createdBy'],
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

    return supplierPaymentPostAggregate(
      id: header.id,
      organizationId: header.companyId,
      branchId: header.branchId,
      createdBy: (extra['created_by_user_id'] ?? 'sync').toString(),
      supplierId: (extra['supplier_id'] ?? '').toString(),
      amount: _asDouble(extra['amount']),
      paymentDate: DateTime.tryParse(
        (extra['payment_date'] ?? '').toString(),
      ),
      paymentMethod: (extra['payment_method'] ?? 'cash').toString(),
      voucherNumber: extra['voucher_number']?.toString(),
      notes: extra['notes']?.toString(),
      transactionVersion: nextTxn,
      rowVersion: nextRow,
      postedAt: postedAt,
      cash: supplierPaymentCashJsonFromStageData(stageData),
      accounting: supplierPaymentAccountingJsonFromStageData(stageData),
    );
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
