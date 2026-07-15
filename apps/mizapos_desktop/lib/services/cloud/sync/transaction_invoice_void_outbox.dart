import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/purchase_invoice_post_ids.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_post_ids.dart';
import 'package:mizapos_desktop/services/cloud/sync/purchase_invoice_draft_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/purchase_invoice_post_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/purchase_invoice_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_draft_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_post_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_walk_in_partners.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/models/miza_payment_types.dart';

/// Enqueues cloud void/cancel after local invoice void succeeds.
class TransactionInvoiceVoidOutbox {
  TransactionInvoiceVoidOutbox._();

  static Future<void> enqueueSalesVoid({
    required DatabaseService databaseService,
    required String invoiceId,
    required String organizationId,
    required String branchId,
    required String userId,
  }) async {
    final db = await databaseService.database;
    final rows = await db.query(
      'salesInvoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final inv = rows.first;
    final status = (inv['invoiceStatus'] ?? '').toString();
    if (status != 'voided' && status != 'void') return;

    final items = await db.query(
      'salesInvoiceItems',
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );
    if (items.isEmpty) return;

    final customerId = TransactionWalkInPartners.resolveCustomerId(
      inv['customerId']?.toString(),
      organizationId,
    );
    final paymentType = (inv['paymentType'] ?? 'cash').toString();
    final total = ((inv['total'] as num?) ?? 0).toDouble();
    final invoiceDate = DateTime.tryParse((inv['invoiceDate'] ?? '').toString()) ??
        DateTime.now();
    final voidedAt = DateTime.now().toIso8601String();
    final txnVersion = (((inv['transactionVersion'] as num?) ?? 1).toInt());
    final rowVersion = (((inv['rowVersion'] as num?) ?? 2).toInt());

    final linePayloads = <Map<String, dynamic>>[];
    final inventory = <Map<String, dynamic>>[];
    for (final item in items) {
      final lineId = (item['id'] ?? '').toString();
      final productId = (item['productId'] ?? '').toString();
      final qty = ((item['quantity'] as num?) ?? 0).toDouble();
      final price = ((item['unitPrice'] as num?) ?? 0).toDouble();
      if (lineId.isEmpty || productId.isEmpty || qty <= 0) continue;
      linePayloads.add(
        salesInvoiceLinePayload(
          lineId: lineId,
          productId: productId,
          quantity: qty,
          unitPrice: price,
        ),
      );
      final mid =
          SalesInvoicePostIds.stockMovementId(invoiceId, 'void:$lineId');
      inventory.add({
        'movement_id': mid,
        'id': mid,
        'product_id': productId,
        'quantity': qty,
        'movement_type': 'in',
        'reference_type': 'sale_void',
        'reference_id': invoiceId,
        'movement_date': voidedAt,
        'created_by_user_id': userId,
      });
    }
    if (linePayloads.isEmpty) return;

    final accounting = <Map<String, dynamic>>[];
    if (MizaPaymentTypes.isDeferred(paymentType) && total != 0) {
      final eid =
          SalesInvoicePostIds.accountingEntryId(invoiceId, 'void_customer');
      accounting.add({
        'entry_id': eid,
        'id': eid,
        'partner_kind': 'customer',
        'partner_id': customerId,
        'entry_type': 'sale_void',
        'reference_type': 'sale',
        'reference_id': invoiceId,
        'amount_signed': -total,
        'entry_date': voidedAt,
        'created_by_user_id': userId,
        'notes': 'إلغاء فاتورة بيع آجل',
      });
    }

    final cash = <Map<String, dynamic>>[];
    final voidCashRows = await db.query(
      'cashTransactions',
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: ['sale_void', invoiceId],
      limit: 5,
    );
    for (final row in voidCashRows) {
      cash.add({
        'cash_transaction_id': (row['id'] ?? '').toString(),
        'id': (row['id'] ?? '').toString(),
        'transaction_type': (row['transactionType'] ?? 'out').toString(),
        'amount': ((row['amount'] as num?) ?? 0).toDouble(),
        'description': (row['description'] ?? '').toString(),
        'reference_type': 'sale_void',
        'reference_id': invoiceId,
        'transaction_date':
            (row['transactionDate'] ?? voidedAt).toString(),
        'created_by_user_id':
            (row['createdBy'] ?? userId).toString(),
      });
    }

    final aggregate = salesInvoicePostAggregate(
      id: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      customerId: customerId,
      invoiceDate: invoiceDate,
      paymentType: paymentType,
      lineSubtotal: ((inv['lineSubtotal'] as num?) ?? total).toDouble(),
      discountAmount: ((inv['discountAmount'] as num?) ?? 0).toDouble(),
      taxPercent: ((inv['taxPercent'] as num?) ?? 0).toDouble(),
      total: total,
      paidAmount: ((inv['paidAmount'] as num?) ?? total).toDouble(),
      notes: inv['notes']?.toString(),
      transactionVersion: txnVersion,
      rowVersion: rowVersion,
      postedAt: voidedAt,
      lines: linePayloads,
      inventory: inventory,
      accounting: accounting,
    );
    final header = Map<String, dynamic>.from(aggregate['header'] as Map);
    header['status'] = 'void';
    header['voided_at'] = voidedAt;
    aggregate['header'] = header;
    final metadata = Map<String, dynamic>.from(aggregate['metadata'] as Map);
    metadata['voided_at'] = voidedAt;
    if (cash.isNotEmpty) {
      metadata['cash'] = cash;
      aggregate['cash'] = cash;
    }
    aggregate['metadata'] = metadata;

    final envelope = salesInvoicePostPushEnvelope(
      aggregateJson: aggregate,
      clientRowVersion: rowVersion,
    );
    envelope['operation'] = 'void';

    await TransactionSyncOutboxWriter.record(
      entityType: SalesInvoiceSyncConstants.entityType,
      operation: 'void',
      entityId: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      payload: envelope,
      databaseService: databaseService,
    );
  }

  static Future<void> enqueuePurchaseVoid({
    required DatabaseService databaseService,
    required String invoiceId,
    required String organizationId,
    required String branchId,
    required String userId,
  }) async {
    final db = await databaseService.database;
    final rows = await db.query(
      'purchaseInvoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final inv = rows.first;
    final status = (inv['invoiceStatus'] ?? '').toString();
    if (status != 'voided' && status != 'void') return;

    final items = await db.query(
      'purchaseInvoiceItems',
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );
    if (items.isEmpty) return;

    final supplierId = TransactionWalkInPartners.resolveSupplierId(
      inv['supplierId']?.toString(),
      organizationId,
    );
    final paymentType = (inv['paymentType'] ?? 'cash').toString();
    final total = ((inv['total'] as num?) ?? 0).toDouble();
    final invoiceDate = DateTime.tryParse((inv['invoiceDate'] ?? '').toString()) ??
        DateTime.now();
    final voidedAt = DateTime.now().toIso8601String();
    final txnVersion = (((inv['transactionVersion'] as num?) ?? 1).toInt());
    final rowVersion = (((inv['rowVersion'] as num?) ?? 2).toInt());

    final linePayloads = <Map<String, dynamic>>[];
    final inventory = <Map<String, dynamic>>[];
    for (final item in items) {
      final lineId = (item['id'] ?? '').toString();
      final productId = (item['productId'] ?? '').toString();
      final qty = ((item['quantity'] as num?) ?? 0).toDouble();
      final cost = ((item['unitCost'] as num?) ??
              (item['unitPrice'] as num?) ??
              0)
          .toDouble();
      if (lineId.isEmpty || productId.isEmpty || qty <= 0) continue;
      linePayloads.add(
        purchaseInvoiceLinePayload(
          lineId: lineId,
          productId: productId,
          quantity: qty,
          unitCost: cost,
        ),
      );
      final mid =
          PurchaseInvoicePostIds.stockMovementId(invoiceId, 'void:$lineId');
      inventory.add({
        'movement_id': mid,
        'id': mid,
        'product_id': productId,
        'quantity': qty,
        'movement_type': 'out',
        'reference_type': 'purchase_void',
        'reference_id': invoiceId,
        'movement_date': voidedAt,
        'created_by_user_id': userId,
      });
    }
    if (linePayloads.isEmpty) return;

    final accounting = <Map<String, dynamic>>[];
    if (MizaPaymentTypes.isDeferred(paymentType) && total != 0) {
      final eid = PurchaseInvoicePostIds.accountingEntryId(
        invoiceId,
        'void_supplier',
      );
      accounting.add({
        'entry_id': eid,
        'id': eid,
        'partner_kind': 'supplier',
        'partner_id': supplierId,
        'entry_type': 'purchase_void',
        'reference_type': 'purchase',
        'reference_id': invoiceId,
        'amount_signed': -total,
        'entry_date': voidedAt,
        'created_by_user_id': userId,
        'notes': 'إلغاء فاتورة شراء آجل',
      });
    }

    final cash = <Map<String, dynamic>>[];
    final voidCashRows = await db.query(
      'cashTransactions',
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: ['purchase_void', invoiceId],
      limit: 5,
    );
    for (final row in voidCashRows) {
      cash.add({
        'cash_transaction_id': (row['id'] ?? '').toString(),
        'id': (row['id'] ?? '').toString(),
        'transaction_type': (row['transactionType'] ?? 'in').toString(),
        'amount': ((row['amount'] as num?) ?? 0).toDouble(),
        'description': (row['description'] ?? '').toString(),
        'reference_type': 'purchase_void',
        'reference_id': invoiceId,
        'transaction_date':
            (row['transactionDate'] ?? voidedAt).toString(),
        'created_by_user_id':
            (row['createdBy'] ?? userId).toString(),
      });
    }

    final aggregate = purchaseInvoicePostAggregate(
      id: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      createdBy: userId,
      supplierId: supplierId,
      invoiceDate: invoiceDate,
      paymentType: paymentType,
      lineSubtotal: ((inv['lineSubtotal'] as num?) ?? total).toDouble(),
      discountAmount: ((inv['discountAmount'] as num?) ?? 0).toDouble(),
      taxPercent: ((inv['taxPercent'] as num?) ?? 0).toDouble(),
      total: total,
      paidAmount: ((inv['paidAmount'] as num?) ?? total).toDouble(),
      notes: inv['notes']?.toString(),
      transactionVersion: txnVersion,
      rowVersion: rowVersion,
      postedAt: voidedAt,
      lines: linePayloads,
      inventory: inventory,
      accounting: accounting,
    );
    final header = Map<String, dynamic>.from(aggregate['header'] as Map);
    header['status'] = 'void';
    header['voided_at'] = voidedAt;
    aggregate['header'] = header;
    final metadata = Map<String, dynamic>.from(aggregate['metadata'] as Map);
    metadata['voided_at'] = voidedAt;
    if (cash.isNotEmpty) {
      metadata['cash'] = cash;
      aggregate['cash'] = cash;
    }
    aggregate['metadata'] = metadata;

    final envelope = purchaseInvoicePostPushEnvelope(
      aggregateJson: aggregate,
      clientRowVersion: rowVersion,
    );
    envelope['operation'] = 'void';

    await TransactionSyncOutboxWriter.record(
      entityType: PurchaseInvoiceSyncConstants.entityType,
      operation: 'void',
      entityId: invoiceId,
      organizationId: organizationId,
      branchId: branchId,
      payload: envelope,
      databaseService: databaseService,
    );
  }
}
