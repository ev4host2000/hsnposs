import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_invoice_sync_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_walk_in_partners.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';
import 'sync_integration_test_helpers.dart';

/// Verifies UI save path: draft insert → outbox create → post pipeline.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  const supplierId = 'd100e840-e29b-41d4-a716-446655440050';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const deviceId = '770e8400-e29b-41d4-a716-446655440002';
  const salesInvoiceId = 'b100e840-e29b-41d4-a716-446655440030';
  const purchaseInvoiceId = 'b100e840-e29b-41d4-a716-446655440031';
  const salesLineId = 'b200e840-e29b-41d4-a716-446655440032';
  const purchaseLineId = 'b200e840-e29b-41d4-a716-446655440033';

  late DatabaseService databaseService;
  late TransactionInvoiceSyncService syncService;

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    await prepareSyncIntegrationTest(databaseService: databaseService);
    syncService = TransactionInvoiceSyncService(databaseService: databaseService);
    final storage = CloudSecureStoragePlaceholder();
    TransactionSyncOutboxWriter.bindStorage(storage);
    await storage.writeDeviceId(deviceId);

    final db = await databaseService.database;
    for (final table in [
      'salesInvoices',
      'salesInvoiceItems',
      'purchaseInvoices',
      'purchaseInvoiceItems',
      'stockMovements',
      'partnerLedger',
      'sync_outbox',
      'customers',
      'suppliers',
      'products',
    ]) {
      await db.delete(table);
    }

    await db.insert('customers', {
      'id': customerId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'UI Test Customer',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('suppliers', {
      'id': supplierId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'UI Test Supplier',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('products', {
      'id': productId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'UI Test Product',
      'salePrice': 25.0,
      'costPrice': 10.0,
      'stockQty': 100.0,
      'isHidden': 0,
      'isFrozen': 0,
      'isService': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
  });

  group('Transaction invoice UI integration path', () {
    test('sales create draft and post enqueues create + post outbox once', () async {
      final result = await syncService.createSalesDraftAndPost(
        invoiceId: salesInvoiceId,
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        customerId: customerId,
        invoiceDate: DateTime.now(),
        paymentType: 'cash',
        lineSubtotal: 50,
        discountAmount: 0,
        taxPercent: 0,
        total: 50,
        paidAmount: 50,
        notes: null,
        invoiceNumber: 1,
        lines: [
          (
            lineId: salesLineId,
            productId: productId,
            quantity: 2,
            unitPrice: 25,
          ),
        ],
      );

      expect(result.ok, isTrue, reason: result.failureCode);

      final db = await databaseService.database;
      final invoice = await db.query(
        'salesInvoices',
        where: 'id = ?',
        whereArgs: [salesInvoiceId],
        limit: 1,
      );
      expect(invoice.first['invoiceStatus'], 'posted');

      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [salesInvoiceId],
        orderBy: 'operation ASC',
      );
      expect(outbox.length, 2);
      expect(outbox.map((r) => r['operation']).toList(), ['create', 'post']);

      final replay = await SalesInvoicePostLocalService(
        databaseService: databaseService,
      ).postDraft(invoiceId: salesInvoiceId);
      expect(replay.ok, isTrue);
      expect(replay.idempotentReplay, isTrue);

      final outboxAfterReplay = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [salesInvoiceId],
      );
      expect(outboxAfterReplay.length, 2);
    });

    test('sales walk-in customer is created when partner is null', () async {
      final walkInId = TransactionWalkInPartners.walkInCustomerId(companyId);
      final result = await syncService.createSalesDraftAndPost(
        invoiceId: 'b100e840-e29b-41d4-a716-446655440040',
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        customerId: null,
        invoiceDate: DateTime.now(),
        paymentType: 'cash',
        lineSubtotal: 20,
        discountAmount: 0,
        taxPercent: 0,
        total: 20,
        paidAmount: 20,
        notes: null,
        invoiceNumber: 2,
        lines: [
          (
            lineId: 'b200e840-e29b-41d4-a716-446655440040',
            productId: productId,
            quantity: 1,
            unitPrice: 20,
          ),
        ],
      );
      expect(result.ok, isTrue);

      final db = await databaseService.database;
      final walkIn = await db.query(
        'customers',
        where: 'id = ?',
        whereArgs: [walkInId],
        limit: 1,
      );
      expect(walkIn, isNotEmpty);
    });

    test('purchase create draft and post increases stock once', () async {
      final result = await syncService.createPurchaseDraftAndPost(
        invoiceId: purchaseInvoiceId,
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        supplierId: supplierId,
        invoiceDate: DateTime.now(),
        paymentType: 'cash',
        lineSubtotal: 50,
        discountAmount: 0,
        taxPercent: 0,
        total: 50,
        paidAmount: 50,
        notes: null,
        invoiceNumber: 1,
        lines: [
          (
            lineId: purchaseLineId,
            productId: productId,
            quantity: 2,
            unitCost: 25,
          ),
        ],
      );
      expect(result.ok, isTrue);

      final db = await databaseService.database;
      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect(product.first['stockQty'], 102.0);

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [purchaseInvoiceId],
      );
      expect(movements.length, 1);
      expect(movements.first['movementType'], 'in');

      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [purchaseInvoiceId],
      );
      expect(outbox.length, 2);
    });
  });
}
