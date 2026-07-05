import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_return_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_return_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_return_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_walk_in_partners.dart';
import 'package:mizapos_mobile/services/database_service.dart';

/// Orchestrates draft save → outbox → post pipeline for sales/purchase returns.
class TransactionReturnSyncService {
  TransactionReturnSyncService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> createSalesReturnDraftAndPost({
    required String returnId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String? customerId,
    required String originalInvoiceId,
    required DateTime returnDate,
    required String refundPaymentType,
    required double lineSubtotal,
    required double discountAmount,
    required double taxPercent,
    required double total,
    required double paidAmount,
    required String? notes,
    required List<({String lineId, String productId, double quantity, double unitPrice})> lines,
  }) async {
    final db = await _databaseService.database;
    final resolvedCustomerId = TransactionWalkInPartners.resolveCustomerId(
      customerId,
      organizationId,
    );

    await db.transaction((txn) async {
      await TransactionWalkInPartners.ensureCustomer(
        txn,
        organizationId: organizationId,
        branchId: branchId,
      );

      await txn.insert('salesReturns', {
        'id': returnId,
        'organizationId': organizationId,
        'branchId': branchId,
        'customerId': resolvedCustomerId,
        'originalInvoiceId': originalInvoiceId,
        'returnDate': returnDate.toIso8601String(),
        'total': total,
        'refundPaymentType': refundPaymentType,
        'returnStatus': 'draft',
        'createdBy': userId,
        'notes': notes,
        'discountAmount': discountAmount,
        'taxPercent': taxPercent,
        'lineSubtotal': lineSubtotal,
        'paidAmount': paidAmount,
        'transactionVersion': 0,
        'rowVersion': 1,
      });

      for (final line in lines) {
        final lineTotal = line.quantity * line.unitPrice;
        await txn.insert('salesReturnItems', {
          'id': line.lineId,
          'returnId': returnId,
          'productId': line.productId,
          'quantity': line.quantity,
          'unitPrice': line.unitPrice,
          'lineTotal': lineTotal,
        });
      }
    });

    await _enqueueSalesReturnDraftCreate(
      returnId: returnId,
      organizationId: organizationId,
      branchId: branchId,
      userId: userId,
      customerId: resolvedCustomerId,
      originalInvoiceId: originalInvoiceId,
      returnDate: returnDate,
      refundPaymentType: refundPaymentType,
      lineSubtotal: lineSubtotal,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      total: total,
      paidAmount: paidAmount,
      notes: notes,
      lines: lines,
    );

    return SalesReturnPostLocalService(databaseService: _databaseService)
        .postDraft(returnId: returnId);
  }

  Future<PostingResult> createPurchaseReturnDraftAndPost({
    required String returnId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String? supplierId,
    required String originalInvoiceId,
    required DateTime returnDate,
    required String refundPaymentType,
    required double lineSubtotal,
    required double discountAmount,
    required double taxPercent,
    required double total,
    required double paidAmount,
    required String? notes,
    required List<({String lineId, String productId, double quantity, double unitCost})> lines,
  }) async {
    final db = await _databaseService.database;
    final resolvedSupplierId = TransactionWalkInPartners.resolveSupplierId(
      supplierId,
      organizationId,
    );

    await db.transaction((txn) async {
      await TransactionWalkInPartners.ensureSupplier(
        txn,
        organizationId: organizationId,
        branchId: branchId,
      );

      await txn.insert('purchaseReturns', {
        'id': returnId,
        'organizationId': organizationId,
        'branchId': branchId,
        'supplierId': resolvedSupplierId,
        'originalInvoiceId': originalInvoiceId,
        'returnDate': returnDate.toIso8601String(),
        'total': total,
        'refundPaymentType': refundPaymentType,
        'returnStatus': 'draft',
        'createdBy': userId,
        'notes': notes,
        'discountAmount': discountAmount,
        'taxPercent': taxPercent,
        'lineSubtotal': lineSubtotal,
        'paidAmount': paidAmount,
        'transactionVersion': 0,
        'rowVersion': 1,
      });

      for (final line in lines) {
        final lineTotal = line.quantity * line.unitCost;
        await txn.insert('purchaseReturnItems', {
          'id': line.lineId,
          'returnId': returnId,
          'productId': line.productId,
          'quantity': line.quantity,
          'unitCost': line.unitCost,
          'lineTotal': lineTotal,
        });
      }
    });

    await _enqueuePurchaseReturnDraftCreate(
      returnId: returnId,
      organizationId: organizationId,
      branchId: branchId,
      userId: userId,
      supplierId: resolvedSupplierId,
      originalInvoiceId: originalInvoiceId,
      returnDate: returnDate,
      refundPaymentType: refundPaymentType,
      lineSubtotal: lineSubtotal,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      total: total,
      paidAmount: paidAmount,
      notes: notes,
      lines: lines,
    );

    return PurchaseReturnPostLocalService(databaseService: _databaseService)
        .postDraft(returnId: returnId);
  }

  Future<void> _enqueueSalesReturnDraftCreate({
    required String returnId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String customerId,
    required String originalInvoiceId,
    required DateTime returnDate,
    required String refundPaymentType,
    required double lineSubtotal,
    required double discountAmount,
    required double taxPercent,
    required double total,
    required double paidAmount,
    required String? notes,
    required List<({String lineId, String productId, double quantity, double unitPrice})> lines,
  }) async {
    final aggregate = salesReturnDraftAggregate(
      id: returnId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      originalInvoiceId: originalInvoiceId,
      customerId: customerId,
      returnDate: returnDate,
      refundPaymentType: refundPaymentType,
      lineSubtotal: lineSubtotal,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      total: total,
      paidAmount: paidAmount,
      notes: notes,
      lines: lines
          .map(
            (l) => salesReturnLinePayload(
              lineId: l.lineId,
              productId: l.productId,
              quantity: l.quantity,
              unitPrice: l.unitPrice,
            ),
          )
          .toList(),
    );

    await TransactionSyncOutboxWriter.record(
      entityType: SalesReturnSyncConstants.entityType,
      operation: 'create',
      entityId: returnId,
      organizationId: organizationId,
      branchId: branchId,
      payload: salesReturnDraftPushEnvelope(
        aggregateJson: aggregate,
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: _databaseService,
    );
  }

  Future<void> _enqueuePurchaseReturnDraftCreate({
    required String returnId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String supplierId,
    required String originalInvoiceId,
    required DateTime returnDate,
    required String refundPaymentType,
    required double lineSubtotal,
    required double discountAmount,
    required double taxPercent,
    required double total,
    required double paidAmount,
    required String? notes,
    required List<({String lineId, String productId, double quantity, double unitCost})> lines,
  }) async {
    final aggregate = purchaseReturnDraftAggregate(
      id: returnId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      originalInvoiceId: originalInvoiceId,
      supplierId: supplierId,
      returnDate: returnDate,
      refundPaymentType: refundPaymentType,
      lineSubtotal: lineSubtotal,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      total: total,
      paidAmount: paidAmount,
      notes: notes,
      lines: lines
          .map(
            (l) => purchaseReturnLinePayload(
              lineId: l.lineId,
              productId: l.productId,
              quantity: l.quantity,
              unitCost: l.unitCost,
            ),
          )
          .toList(),
    );

    await TransactionSyncOutboxWriter.record(
      entityType: PurchaseReturnSyncConstants.entityType,
      operation: 'create',
      entityId: returnId,
      organizationId: organizationId,
      branchId: branchId,
      payload: purchaseReturnDraftPushEnvelope(
        aggregateJson: aggregate,
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: _databaseService,
    );
  }
}

String transactionReturnPostFailureMessage(PostingResult result) {
  return result.failureMessage ??
      result.failureCode ??
      'Posting failed at ${result.failedStageId}';
}
