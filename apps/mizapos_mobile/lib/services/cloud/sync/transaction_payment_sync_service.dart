import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/database_service.dart';

/// Orchestrates draft save → outbox → post pipeline for customer/supplier payments.
class TransactionPaymentSyncService {
  TransactionPaymentSyncService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> createCustomerPaymentDraftAndPost({
    required String paymentId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String customerId,
    required double amount,
    required DateTime paymentDate,
    String paymentMethod = 'cash',
    String? voucherNumber,
    String? notes,
  }) async {
    final db = await _databaseService.database;
    final resolvedCustomerId = customerId.trim();

    await db.transaction((txn) async {
      await txn.insert('customerPayments', {
        'id': paymentId,
        'organizationId': organizationId,
        'branchId': branchId,
        'customerId': resolvedCustomerId,
        'amount': amount,
        'paymentDate': paymentDate.toIso8601String(),
        'paymentMethod': paymentMethod,
        'voucherNumber': voucherNumber,
        'notes': notes,
        'paymentStatus': 'draft',
        'createdBy': userId,
        'transactionVersion': 0,
        'rowVersion': 1,
      });
    });

    await _enqueueCustomerPaymentDraftCreate(
      paymentId: paymentId,
      organizationId: organizationId,
      branchId: branchId,
      userId: userId,
      customerId: resolvedCustomerId,
      amount: amount,
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      voucherNumber: voucherNumber,
      notes: notes,
    );

    return CustomerPaymentPostLocalService(databaseService: _databaseService)
        .postDraft(paymentId: paymentId);
  }

  Future<PostingResult> createSupplierPaymentDraftAndPost({
    required String paymentId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String supplierId,
    required double amount,
    required DateTime paymentDate,
    String paymentMethod = 'cash',
    String? voucherNumber,
    String? notes,
  }) async {
    final db = await _databaseService.database;
    final resolvedSupplierId = supplierId.trim();

    await db.transaction((txn) async {
      await txn.insert('supplierPayments', {
        'id': paymentId,
        'organizationId': organizationId,
        'branchId': branchId,
        'supplierId': resolvedSupplierId,
        'amount': amount,
        'paymentDate': paymentDate.toIso8601String(),
        'paymentMethod': paymentMethod,
        'voucherNumber': voucherNumber,
        'notes': notes,
        'paymentStatus': 'draft',
        'createdBy': userId,
        'transactionVersion': 0,
        'rowVersion': 1,
      });
    });

    await _enqueueSupplierPaymentDraftCreate(
      paymentId: paymentId,
      organizationId: organizationId,
      branchId: branchId,
      userId: userId,
      supplierId: resolvedSupplierId,
      amount: amount,
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      voucherNumber: voucherNumber,
      notes: notes,
    );

    return SupplierPaymentPostLocalService(databaseService: _databaseService)
        .postDraft(paymentId: paymentId);
  }

  Future<void> _enqueueCustomerPaymentDraftCreate({
    required String paymentId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String customerId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? voucherNumber,
    String? notes,
  }) async {
    final aggregate = customerPaymentDraftAggregate(
      id: paymentId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      customerId: customerId,
      amount: amount,
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      voucherNumber: voucherNumber,
      notes: notes,
    );

    await TransactionSyncOutboxWriter.record(
      entityType: CustomerPaymentSyncConstants.entityType,
      operation: 'create',
      entityId: paymentId,
      organizationId: organizationId,
      branchId: branchId,
      payload: customerPaymentDraftPushEnvelope(
        aggregateJson: aggregate,
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: _databaseService,
    );
  }

  Future<void> _enqueueSupplierPaymentDraftCreate({
    required String paymentId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String supplierId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? voucherNumber,
    String? notes,
  }) async {
    final aggregate = supplierPaymentDraftAggregate(
      id: paymentId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      supplierId: supplierId,
      amount: amount,
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      voucherNumber: voucherNumber,
      notes: notes,
    );

    await TransactionSyncOutboxWriter.record(
      entityType: SupplierPaymentSyncConstants.entityType,
      operation: 'create',
      entityId: paymentId,
      organizationId: organizationId,
      branchId: branchId,
      payload: supplierPaymentDraftPushEnvelope(
        aggregateJson: aggregate,
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: _databaseService,
    );
  }
}

String transactionPaymentPostFailureMessage(PostingResult result) {
  return result.failureMessage ??
      result.failureCode ??
      'Posting failed at ${result.failedStageId}';
}
