import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_inventory_adjustment_sync_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';

/// Verifies UI save path: draft insert → outbox create → post pipeline for adjustments.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const deviceId = '770e8400-e29b-41d4-a716-446655440002';
  const adjustmentId = 'b100e840-e29b-41d4-a716-446655440030';

  late DatabaseService databaseService;
  late TransactionInventoryAdjustmentSyncService syncService;

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    syncService =
        TransactionInventoryAdjustmentSyncService(databaseService: databaseService);
    final storage = CloudSecureStoragePlaceholder();
    TransactionSyncOutboxWriter.bindStorage(storage);
    await storage.writeDeviceId(deviceId);

    final db = await databaseService.database;
    for (final table in [
      'inventoryAdjustments',
      'stockMovements',
      'sync_outbox',
      'products',
    ]) {
      await db.delete(table);
    }

    await db.insert('products', {
      'id': productId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'UI Test Product',
      'salePrice': 25.0,
      'costPrice': 10.0,
      'stockQty': 10.0,
      'isHidden': 0,
      'isFrozen': 0,
      'isService': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
  });

  group('Transaction inventory adjustment UI integration path', () {
    test('create draft and post enqueues create + post outbox once', () async {
      final result = await syncService.createInventoryAdjustmentDraftAndPost(
        adjustmentId: adjustmentId,
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        productId: productId,
        quantityDelta: 5,
        adjustmentReason: 'correction',
        notes: 'UI test adjustment',
      );

      expect(result.ok, isTrue, reason: result.failureCode);

      final db = await databaseService.database;
      final adjustmentDoc = await db.query(
        'inventoryAdjustments',
        where: 'id = ?',
        whereArgs: [adjustmentId],
        limit: 1,
      );
      expect(adjustmentDoc.first['adjustmentStatus'], 'posted');
      expect(adjustmentDoc.first['productId'], productId);
      expect(adjustmentDoc.first['quantityDelta'], 5.0);

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [adjustmentId],
      );
      expect(movements.length, 1);
      expect(movements.first['movementType'], 'in');
      expect(movements.first['referenceType'], 'inventory_adjustment');
      expect(
        movements.first['id'],
        InventoryAdjustmentPostIds.stockMovementId(adjustmentId),
      );

      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect(product.first['stockQty'], 15.0);

      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [adjustmentId],
        orderBy: 'operation ASC',
      );
      expect(outbox.length, 2);
      expect(outbox.map((r) => r['operation']).toList(), ['create', 'post']);

      final replay = await InventoryAdjustmentPostLocalService(
        databaseService: databaseService,
      ).postDraft(adjustmentId: adjustmentId);
      expect(replay.ok, isTrue);
      expect(replay.idempotentReplay, isTrue);

      final outboxAfterReplay = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [adjustmentId],
      );
      expect(outboxAfterReplay.length, 2);
    });
  });
}
