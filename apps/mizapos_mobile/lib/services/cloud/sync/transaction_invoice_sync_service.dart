import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_walk_in_partners.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Orchestrates draft save → outbox → post pipeline for sales/purchase invoices.
class TransactionInvoiceSyncService {
  TransactionInvoiceSyncService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  final DatabaseService _databaseService;

  Future<PostingResult> createSalesDraftAndPost({
    required String invoiceId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String? customerId,
    required DateTime invoiceDate,
    required String paymentType,
    required double lineSubtotal,
    required double discountAmount,
    required double taxPercent,
    required double total,
    required double paidAmount,
    required String? notes,
    required int? invoiceNumber,
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

      await txn.insert('salesInvoices', {
        'id': invoiceId,
        'organizationId': organizationId,
        'branchId': branchId,
        'customerId': resolvedCustomerId,
        'invoiceDate': invoiceDate.toIso8601String(),
        'total': total,
        'paymentType': paymentType,
        'invoiceStatus': 'draft',
        'createdBy': userId,
        'notes': notes,
        'discountAmount': discountAmount,
        'taxPercent': taxPercent,
        'lineSubtotal': lineSubtotal,
        'totalsFormat': 1,
        'paidAmount': paidAmount,
        if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
        'transactionVersion': 0,
        'rowVersion': 1,
      });

      for (final line in lines) {
        final lineTotal = line.quantity * line.unitPrice;
        await txn.insert('salesInvoiceItems', {
          'id': line.lineId,
          'invoiceId': invoiceId,
          'productId': line.productId,
          'quantity': line.quantity,
          'unitPrice': line.unitPrice,
          'lineTotal': lineTotal,
        });
      }
    });

    await _enqueueSalesDraftCreate(
      invoiceId: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      userId: userId,
      customerId: resolvedCustomerId,
      invoiceDate: invoiceDate,
      paymentType: paymentType,
      lineSubtotal: lineSubtotal,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      total: total,
      paidAmount: paidAmount,
      notes: notes,
      lines: lines,
    );

    return SalesInvoicePostLocalService(databaseService: _databaseService)
        .postDraft(invoiceId: invoiceId);
  }

  Future<PostingResult> createPurchaseDraftAndPost({
    required String invoiceId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String? supplierId,
    required DateTime invoiceDate,
    required String paymentType,
    required double lineSubtotal,
    required double discountAmount,
    required double taxPercent,
    required double total,
    required double paidAmount,
    required String? notes,
    required int? invoiceNumber,
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

      await txn.insert('purchaseInvoices', {
        'id': invoiceId,
        'organizationId': organizationId,
        'branchId': branchId,
        'supplierId': resolvedSupplierId,
        'invoiceDate': invoiceDate.toIso8601String(),
        'total': total,
        'paymentType': paymentType,
        'invoiceStatus': 'draft',
        'createdBy': userId,
        'notes': notes,
        'discountAmount': discountAmount,
        'taxPercent': taxPercent,
        'lineSubtotal': lineSubtotal,
        'totalsFormat': 1,
        'paidAmount': paidAmount,
        if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
        'transactionVersion': 0,
        'rowVersion': 1,
      });

      for (final line in lines) {
        final lineTotal = line.quantity * line.unitCost;
        await txn.insert('purchaseInvoiceItems', {
          'id': line.lineId,
          'invoiceId': invoiceId,
          'productId': line.productId,
          'quantity': line.quantity,
          'unitCost': line.unitCost,
          'lineTotal': lineTotal,
        });
      }
    });

    await _enqueuePurchaseDraftCreate(
      invoiceId: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      userId: userId,
      supplierId: resolvedSupplierId,
      invoiceDate: invoiceDate,
      paymentType: paymentType,
      lineSubtotal: lineSubtotal,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      total: total,
      paidAmount: paidAmount,
      notes: notes,
      lines: lines,
    );

    return PurchaseInvoicePostLocalService(databaseService: _databaseService)
        .postDraft(invoiceId: invoiceId);
  }

  Future<void> _enqueueSalesDraftCreate({
    required String invoiceId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String customerId,
    required DateTime invoiceDate,
    required String paymentType,
    required double lineSubtotal,
    required double discountAmount,
    required double taxPercent,
    required double total,
    required double paidAmount,
    required String? notes,
    required List<({String lineId, String productId, double quantity, double unitPrice})> lines,
  }) async {
    final aggregate = salesInvoiceDraftAggregate(
      id: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      customerId: customerId,
      invoiceDate: invoiceDate,
      paymentType: paymentType,
      lineSubtotal: lineSubtotal,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      total: total,
      paidAmount: paidAmount,
      notes: notes,
      lines: lines
          .map(
            (l) => salesInvoiceLinePayload(
              lineId: l.lineId,
              productId: l.productId,
              quantity: l.quantity,
              unitPrice: l.unitPrice,
            ),
          )
          .toList(),
    );

    await TransactionSyncOutboxWriter.record(
      entityType: SalesInvoiceSyncConstants.entityType,
      operation: 'create',
      entityId: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      payload: salesInvoiceDraftPushEnvelope(
        aggregateJson: aggregate,
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: _databaseService,
    );
  }

  Future<void> _enqueuePurchaseDraftCreate({
    required String invoiceId,
    required String organizationId,
    required String branchId,
    required String userId,
    required String supplierId,
    required DateTime invoiceDate,
    required String paymentType,
    required double lineSubtotal,
    required double discountAmount,
    required double taxPercent,
    required double total,
    required double paidAmount,
    required String? notes,
    required List<({String lineId, String productId, double quantity, double unitCost})> lines,
  }) async {
    final aggregate = purchaseInvoiceDraftAggregate(
      id: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      supplierId: supplierId,
      invoiceDate: invoiceDate,
      paymentType: paymentType,
      lineSubtotal: lineSubtotal,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      total: total,
      paidAmount: paidAmount,
      notes: notes,
      lines: lines
          .map(
            (l) => purchaseInvoiceLinePayload(
              lineId: l.lineId,
              productId: l.productId,
              quantity: l.quantity,
              unitCost: l.unitCost,
            ),
          )
          .toList(),
    );

    await TransactionSyncOutboxWriter.record(
      entityType: PurchaseInvoiceSyncConstants.entityType,
      operation: 'create',
      entityId: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      payload: purchaseInvoiceDraftPushEnvelope(
        aggregateJson: aggregate,
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: _databaseService,
    );
  }
}

String transactionInvoicePostFailureMessage(PostingResult result) {
  return result.failureMessage ??
      result.failureCode ??
      'Posting failed at ${result.failedStageId}';
}
