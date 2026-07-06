import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_payment_sync_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';

/// Verifies UI save path: draft insert → outbox create → post pipeline for payments.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  const supplierId = 'd100e840-e29b-41d4-a716-446655440050';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const deviceId = '770e8400-e29b-41d4-a716-446655440002';
  const customerPaymentId = 'b100e840-e29b-41d4-a716-446655440030';
  const supplierPaymentId = 'b100e840-e29b-41d4-a716-446655440031';

  late DatabaseService databaseService;
  late TransactionPaymentSyncService syncService;

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    syncService = TransactionPaymentSyncService(databaseService: databaseService);
    final storage = CloudSecureStoragePlaceholder();
    TransactionSyncOutboxWriter.bindStorage(storage);
    await storage.writeDeviceId(deviceId);

    final db = await databaseService.database;
    for (final table in [
      'customerPayments',
      'supplierPayments',
      'cashTransactions',
      'partnerLedger',
      'sync_outbox',
      'customers',
      'suppliers',
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
  });

  group('Transaction payment UI integration path', () {
    test('customer payment create draft and post enqueues create + post outbox once', () async {
      final result = await syncService.createCustomerPaymentDraftAndPost(
        paymentId: customerPaymentId,
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        customerId: customerId,
        amount: 50,
        paymentDate: DateTime.now(),
        paymentMethod: 'cash',
        notes: 'UI test payment',
      );

      expect(result.ok, isTrue, reason: result.failureCode);

      final db = await databaseService.database;
      final paymentDoc = await db.query(
        'customerPayments',
        where: 'id = ?',
        whereArgs: [customerPaymentId],
        limit: 1,
      );
      expect(paymentDoc.first['paymentStatus'], 'posted');
      expect(paymentDoc.first['customerId'], customerId);
      expect(paymentDoc.first['amount'], 50.0);

      final cash = await db.query(
        'cashTransactions',
        where: 'referenceId = ?',
        whereArgs: [customerPaymentId],
      );
      expect(cash.length, 1);
      expect(cash.first['transactionType'], 'in');

      final ledger = await db.query(
        'partnerLedger',
        where: 'referenceId = ?',
        whereArgs: [customerPaymentId],
      );
      expect(ledger.length, 1);

      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [customerPaymentId],
        orderBy: 'operation ASC',
      );
      expect(outbox.length, 2);
      expect(outbox.map((r) => r['operation']).toList(), ['create', 'post']);

      final replay = await CustomerPaymentPostLocalService(
        databaseService: databaseService,
      ).postDraft(paymentId: customerPaymentId);
      expect(replay.ok, isTrue);
      expect(replay.idempotentReplay, isTrue);

      final outboxAfterReplay = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [customerPaymentId],
      );
      expect(outboxAfterReplay.length, 2);
    });

    test('supplier payment create draft and post enqueues create + post outbox once', () async {
      final result = await syncService.createSupplierPaymentDraftAndPost(
        paymentId: supplierPaymentId,
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        supplierId: supplierId,
        amount: 50,
        paymentDate: DateTime.now(),
        paymentMethod: 'cash',
        notes: 'UI test supplier payment',
      );

      expect(result.ok, isTrue, reason: result.failureCode);

      final db = await databaseService.database;
      final paymentDoc = await db.query(
        'supplierPayments',
        where: 'id = ?',
        whereArgs: [supplierPaymentId],
        limit: 1,
      );
      expect(paymentDoc.first['paymentStatus'], 'posted');
      expect(paymentDoc.first['supplierId'], supplierId);
      expect(paymentDoc.first['amount'], 50.0);

      final cash = await db.query(
        'cashTransactions',
        where: 'referenceId = ?',
        whereArgs: [supplierPaymentId],
      );
      expect(cash.length, 1);
      expect(cash.first['transactionType'], 'out');

      final ledger = await db.query(
        'partnerLedger',
        where: 'referenceId = ?',
        whereArgs: [supplierPaymentId],
      );
      expect(ledger.length, 1);

      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [supplierPaymentId],
        orderBy: 'operation ASC',
      );
      expect(outbox.length, 2);
      expect(outbox.map((r) => r['operation']).toList(), ['create', 'post']);

      final replay = await SupplierPaymentPostLocalService(
        databaseService: databaseService,
      ).postDraft(paymentId: supplierPaymentId);
      expect(replay.ok, isTrue);
      expect(replay.idempotentReplay, isTrue);

      final outboxAfterReplay = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [supplierPaymentId],
      );
      expect(outboxAfterReplay.length, 2);
    });
  });
}
