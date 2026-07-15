import 'package:flutter/foundation.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_invoice/purchase_invoice_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/purchase_invoice_draft_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/purchase_invoice_post_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/purchase_invoice_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_draft_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_post_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_walk_in_partners.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Backfills already-posted local invoices that never entered sync_outbox
/// (legacy createSale path before cloud wiring).
class InvoiceSyncBackfill {
  InvoiceSyncBackfill._();

  static Future<int> enqueueMissingPostedInvoices({
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
    required String organizationId,
    required String branchId,
  }) async {
    TransactionSyncOutboxWriter.bindStorage(storage);
    final db = await databaseService.database;
    await TransactionWalkInPartners.ensureCustomer(
      db,
      organizationId: organizationId,
      branchId: branchId,
    );
    await TransactionWalkInPartners.ensureSupplier(
      db,
      organizationId: organizationId,
      branchId: branchId,
    );

    var n = 0;
    n += await _enqueueMissingSales(
      db: db,
      databaseService: databaseService,
      organizationId: organizationId,
      branchId: branchId,
    );
    n += await _enqueueMissingPurchases(
      db: db,
      databaseService: databaseService,
      organizationId: organizationId,
      branchId: branchId,
    );
    if (kDebugMode) {
      debugPrint('InvoiceSyncBackfill: enqueued=$n');
    }
    return n;
  }

  static Future<int> _enqueueMissingSales({
    required Database db,
    required DatabaseService databaseService,
    required String organizationId,
    required String branchId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT s.*
      FROM salesInvoices s
      WHERE s.organizationId = ? AND s.branchId = ?
        AND IFNULL(s.invoiceStatus, 'posted') = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM sync_outbox o
          WHERE o.entity_type = ? AND o.entity_id = s.id
        )
      ''',
      [organizationId, branchId, SalesInvoiceSyncConstants.entityType],
    );
    var count = 0;
    final walkIn = TransactionWalkInPartners.walkInCustomerId(organizationId);
    for (final row in rows) {
      final invoiceId = (row['id'] ?? '').toString();
      if (invoiceId.isEmpty) continue;
      final lines = await db.query(
        'salesInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      if (lines.isEmpty) continue;

      final customerId = TransactionWalkInPartners.resolveCustomerId(
        row['customerId']?.toString(),
        organizationId,
      );
      if ((row['customerId'] ?? '').toString().trim().isEmpty) {
        await db.update(
          'salesInvoices',
          {'customerId': walkIn},
          where: 'id = ?',
          whereArgs: [invoiceId],
        );
      }
      final createdBy = (row['createdBy'] ?? '').toString();
      if (createdBy.isEmpty) continue;
      final invoiceDate = DateTime.tryParse(
            (row['invoiceDate'] ?? '').toString(),
          ) ??
          DateTime.now();
      final paymentType = (row['paymentType'] ?? 'cash').toString();
      final lineSubtotal = (row['lineSubtotal'] as num?)?.toDouble() ??
          (row['total'] as num?)?.toDouble() ??
          0;
      final discount = (row['discountAmount'] as num?)?.toDouble() ?? 0;
      final taxPercent = (row['taxPercent'] as num?)?.toDouble() ?? 0;
      final total = (row['total'] as num?)?.toDouble() ?? 0;
      final paid = (row['paidAmount'] as num?)?.toDouble() ?? total;
      final notes = row['notes']?.toString();

      final linePayloads = <Map<String, dynamic>>[];
      for (final line in lines) {
        final lineId = (line['id'] ?? '').toString();
        final productId = (line['productId'] ?? '').toString();
        final qty = (line['quantity'] as num?)?.toDouble() ?? 0;
        final price = (line['unitPrice'] as num?)?.toDouble() ?? 0;
        if (lineId.isEmpty || productId.isEmpty || qty <= 0) continue;
        linePayloads.add(
          salesInvoiceLinePayload(
            lineId: lineId,
            productId: productId,
            quantity: qty,
            unitPrice: price,
          ),
        );
      }
      if (linePayloads.isEmpty) continue;

      final draft = salesInvoiceDraftAggregate(
        id: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        createdBy: createdBy,
        customerId: customerId,
        invoiceDate: invoiceDate,
        paymentType: paymentType,
        lineSubtotal: lineSubtotal,
        discountAmount: discount,
        taxPercent: taxPercent,
        total: total,
        paidAmount: paid,
        notes: notes,
        lines: linePayloads,
        transactionVersion: 0,
        rowVersion: 1,
      );

      await TransactionSyncOutboxWriter.record(
        entityType: SalesInvoiceSyncConstants.entityType,
        operation: 'create',
        entityId: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        payload: salesInvoiceDraftPushEnvelope(
          aggregateJson: draft,
          operation: 'create',
          clientRowVersion: 1,
        ),
        databaseService: databaseService,
      );

      final amounts = SalesInvoicePostEffects.computeAmounts(
        lines: linePayloads,
        discountAmount: discount,
        taxPercent: taxPercent,
        headerTotal: total,
      );
      final inventory = SalesInvoicePostEffects.buildInventory(
        invoiceId: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        lines: linePayloads,
        createdBy: createdBy,
        movementDate: invoiceDate.toIso8601String(),
      );
      final accounting = SalesInvoicePostEffects.buildAccounting(
        invoiceId: invoiceId,
        organizationId: organizationId,
        customerId: customerId,
        amounts: amounts,
        createdBy: createdBy,
        entryDate: invoiceDate.toIso8601String(),
      );

      final postedAt = DateTime.now().toIso8601String();
      final postAgg = salesInvoicePostAggregate(
        id: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        createdBy: createdBy,
        customerId: customerId,
        invoiceDate: invoiceDate,
        paymentType: paymentType,
        lineSubtotal: lineSubtotal,
        discountAmount: discount,
        taxPercent: taxPercent,
        total: total,
        paidAmount: paid,
        notes: notes,
        transactionVersion: 1,
        rowVersion: 2,
        postedAt: postedAt,
        lines: linePayloads,
        inventory: inventory.map((e) => e.toJson()).toList(),
        accounting: accounting.map((e) => e.toJson()).toList(),
      );

      await TransactionSyncOutboxWriter.record(
        entityType: SalesInvoiceSyncConstants.entityType,
        operation: 'post',
        entityId: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        payload: salesInvoicePostPushEnvelope(
          aggregateJson: postAgg,
          clientRowVersion: 2,
        ),
        databaseService: databaseService,
      );
      count++;
    }
    return count;
  }

  static Future<int> _enqueueMissingPurchases({
    required Database db,
    required DatabaseService databaseService,
    required String organizationId,
    required String branchId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.*
      FROM purchaseInvoices p
      WHERE p.organizationId = ? AND p.branchId = ?
        AND IFNULL(p.invoiceStatus, 'posted') = 'posted'
        AND NOT EXISTS (
          SELECT 1 FROM sync_outbox o
          WHERE o.entity_type = ? AND o.entity_id = p.id
        )
      ''',
      [organizationId, branchId, PurchaseInvoiceSyncConstants.entityType],
    );
    var count = 0;
    final walkIn = TransactionWalkInPartners.walkInSupplierId(organizationId);
    for (final row in rows) {
      final invoiceId = (row['id'] ?? '').toString();
      if (invoiceId.isEmpty) continue;
      final lines = await db.query(
        'purchaseInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      if (lines.isEmpty) continue;

      final supplierId = TransactionWalkInPartners.resolveSupplierId(
        row['supplierId']?.toString(),
        organizationId,
      );
      if ((row['supplierId'] ?? '').toString().trim().isEmpty) {
        await db.update(
          'purchaseInvoices',
          {'supplierId': walkIn},
          where: 'id = ?',
          whereArgs: [invoiceId],
        );
      }
      final createdBy = (row['createdBy'] ?? '').toString();
      if (createdBy.isEmpty) continue;
      final invoiceDate = DateTime.tryParse(
            (row['invoiceDate'] ?? '').toString(),
          ) ??
          DateTime.now();
      final paymentType = (row['paymentType'] ?? 'cash').toString();
      final lineSubtotal = (row['lineSubtotal'] as num?)?.toDouble() ??
          (row['total'] as num?)?.toDouble() ??
          0;
      final discount = (row['discountAmount'] as num?)?.toDouble() ?? 0;
      final taxPercent = (row['taxPercent'] as num?)?.toDouble() ?? 0;
      final total = (row['total'] as num?)?.toDouble() ?? 0;
      final paid = (row['paidAmount'] as num?)?.toDouble() ?? total;
      final notes = row['notes']?.toString();

      final linePayloads = <Map<String, dynamic>>[];
      for (final line in lines) {
        final lineId = (line['id'] ?? '').toString();
        final productId = (line['productId'] ?? '').toString();
        final qty = (line['quantity'] as num?)?.toDouble() ?? 0;
        final cost = (line['unitCost'] as num?)?.toDouble() ??
            (line['unitPrice'] as num?)?.toDouble() ??
            0;
        if (lineId.isEmpty || productId.isEmpty || qty <= 0) continue;
        linePayloads.add(
          purchaseInvoiceLinePayload(
            lineId: lineId,
            productId: productId,
            quantity: qty,
            unitCost: cost,
          ),
        );
      }
      if (linePayloads.isEmpty) continue;

      final draft = purchaseInvoiceDraftAggregate(
        id: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        createdBy: createdBy,
        supplierId: supplierId,
        invoiceDate: invoiceDate,
        paymentType: paymentType,
        lineSubtotal: lineSubtotal,
        discountAmount: discount,
        taxPercent: taxPercent,
        total: total,
        paidAmount: paid,
        notes: notes,
        lines: linePayloads,
        transactionVersion: 0,
        rowVersion: 1,
      );

      await TransactionSyncOutboxWriter.record(
        entityType: PurchaseInvoiceSyncConstants.entityType,
        operation: 'create',
        entityId: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        payload: purchaseInvoiceDraftPushEnvelope(
          aggregateJson: draft,
          operation: 'create',
          clientRowVersion: 1,
        ),
        databaseService: databaseService,
      );

      final amounts = PurchaseInvoicePostEffects.computeAmounts(
        lines: linePayloads,
        discountAmount: discount,
        taxPercent: taxPercent,
        headerTotal: total,
      );
      final inventory = PurchaseInvoicePostEffects.buildInventory(
        invoiceId: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        lines: linePayloads,
        createdBy: createdBy,
        movementDate: invoiceDate.toIso8601String(),
      );
      final accounting = PurchaseInvoicePostEffects.buildAccounting(
        invoiceId: invoiceId,
        organizationId: organizationId,
        supplierId: supplierId,
        amounts: amounts,
        createdBy: createdBy,
        entryDate: invoiceDate.toIso8601String(),
      );

      final postedAt = DateTime.now().toIso8601String();
      final postAgg = purchaseInvoicePostAggregate(
        id: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        createdBy: createdBy,
        supplierId: supplierId,
        invoiceDate: invoiceDate,
        paymentType: paymentType,
        lineSubtotal: lineSubtotal,
        discountAmount: discount,
        taxPercent: taxPercent,
        total: total,
        paidAmount: paid,
        notes: notes,
        transactionVersion: 1,
        rowVersion: 2,
        postedAt: postedAt,
        lines: linePayloads,
        inventory: inventory.map((e) => e.toJson()).toList(),
        accounting: accounting.map((e) => e.toJson()).toList(),
      );

      await TransactionSyncOutboxWriter.record(
        entityType: PurchaseInvoiceSyncConstants.entityType,
        operation: 'post',
        entityId: invoiceId,
        organizationId: organizationId,
        branchId: branchId,
        payload: purchaseInvoicePostPushEnvelope(
          aggregateJson: postAgg,
          clientRowVersion: 2,
        ),
        databaseService: databaseService,
      );
      count++;
    }
    return count;
  }
}
