import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_return_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_return_sync_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_walk_in_partners.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';
import 'return_test_seed.dart';

/// Verifies UI save path: draft insert → outbox create → post pipeline for returns.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  const supplierId = 'd100e840-e29b-41d4-a716-446655440050';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const deviceId = '770e8400-e29b-41d4-a716-446655440002';
  const salesOriginalInvoiceId = 'b000e840-e29b-41d4-a716-446655440029';
  const purchaseOriginalInvoiceId = 'b000e840-e29b-41d4-a716-446655440028';
  const salesParentLineId = 'b100e840-e29b-41d4-a716-446655440027';
  const purchaseParentLineId = 'b100e840-e29b-41d4-a716-446655440026';
  const salesReturnId = 'b100e840-e29b-41d4-a716-446655440030';
  const purchaseReturnId = 'b100e840-e29b-41d4-a716-446655440031';
  const salesReturnLineId = 'b200e840-e29b-41d4-a716-446655440032';
  const purchaseReturnLineId = 'b200e840-e29b-41d4-a716-446655440033';

  late DatabaseService databaseService;
  late TransactionReturnSyncService syncService;

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    syncService = TransactionReturnSyncService(databaseService: databaseService);
    final storage = CloudSecureStoragePlaceholder();
    TransactionSyncOutboxWriter.bindStorage(storage);
    await storage.writeDeviceId(deviceId);

    final db = await databaseService.database;
    for (final table in [
      'salesReturns',
      'salesReturnItems',
      'purchaseReturns',
      'purchaseReturnItems',
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

    await ReturnTestSeed.seedPostedParentSalesInvoice(
      db,
      originalInvoiceId: salesOriginalInvoiceId,
      parentLineId: salesParentLineId,
      companyId: companyId,
      branchId: branchId,
      customerId: customerId,
      productId: productId,
      userId: userId,
    );
    await ReturnTestSeed.seedPostedParentPurchaseInvoice(
      db,
      originalInvoiceId: purchaseOriginalInvoiceId,
      parentLineId: purchaseParentLineId,
      companyId: companyId,
      branchId: branchId,
      supplierId: supplierId,
      productId: productId,
      userId: userId,
    );
    await db.update(
      'products',
      {'stockQty': 100.0},
      where: 'id = ?',
      whereArgs: [productId],
    );
  });

  group('Transaction return UI integration path', () {
    test('sales return create draft and post enqueues create + post outbox once', () async {
      final result = await syncService.createSalesReturnDraftAndPost(
        returnId: salesReturnId,
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        customerId: customerId,
        originalInvoiceId: salesOriginalInvoiceId,
        returnDate: DateTime.now(),
        refundPaymentType: 'cash',
        lineSubtotal: 50,
        discountAmount: 0,
        taxPercent: 0,
        total: 50,
        paidAmount: 50,
        notes: null,
        lines: [
          (
            lineId: salesReturnLineId,
            productId: productId,
            quantity: 2,
            unitPrice: 25,
          ),
        ],
      );

      expect(result.ok, isTrue, reason: result.failureCode);

      final db = await databaseService.database;
      final returnDoc = await db.query(
        'salesReturns',
        where: 'id = ?',
        whereArgs: [salesReturnId],
        limit: 1,
      );
      expect(returnDoc.first['returnStatus'], 'posted');
      expect(returnDoc.first['originalInvoiceId'], salesOriginalInvoiceId);

      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [salesReturnId],
        orderBy: 'operation ASC',
      );
      expect(outbox.length, 2);
      expect(outbox.map((r) => r['operation']).toList(), ['create', 'post']);

      final replay = await SalesReturnPostLocalService(
        databaseService: databaseService,
      ).postDraft(returnId: salesReturnId);
      expect(replay.ok, isTrue);
      expect(replay.idempotentReplay, isTrue);

      final outboxAfterReplay = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [salesReturnId],
      );
      expect(outboxAfterReplay.length, 2);
    });

    test('sales return walk-in customer is created when partner is null', () async {
      final walkInId = TransactionWalkInPartners.walkInCustomerId(companyId);
      final result = await syncService.createSalesReturnDraftAndPost(
        returnId: 'b100e840-e29b-41d4-a716-446655440040',
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        customerId: null,
        originalInvoiceId: salesOriginalInvoiceId,
        returnDate: DateTime.now(),
        refundPaymentType: 'cash',
        lineSubtotal: 20,
        discountAmount: 0,
        taxPercent: 0,
        total: 20,
        paidAmount: 20,
        notes: null,
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

    test('purchase return create draft and post decreases stock once', () async {
      final result = await syncService.createPurchaseReturnDraftAndPost(
        returnId: purchaseReturnId,
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        supplierId: supplierId,
        originalInvoiceId: purchaseOriginalInvoiceId,
        returnDate: DateTime.now(),
        refundPaymentType: 'cash',
        lineSubtotal: 50,
        discountAmount: 0,
        taxPercent: 0,
        total: 50,
        paidAmount: 50,
        notes: null,
        lines: [
          (
            lineId: purchaseReturnLineId,
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
      expect(product.first['stockQty'], 98.0);

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [purchaseReturnId],
      );
      expect(movements.length, 1);
      expect(movements.first['movementType'], 'out');

      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [purchaseReturnId],
      );
      expect(outbox.length, 2);
    });
  });
}
