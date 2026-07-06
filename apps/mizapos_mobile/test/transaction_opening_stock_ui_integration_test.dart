import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/opening_stock_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/opening_stock_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_opening_stock_sync_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';
import 'sync_integration_test_helpers.dart';

/// Verifies UI save path: draft insert → outbox create → post pipeline for opening stock.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const deviceId = '770e8400-e29b-41d4-a716-446655440002';
  const openingStockId = 'b100e840-e29b-41d4-a716-446655440030';

  late DatabaseService databaseService;
  late TransactionOpeningStockSyncService syncService;

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    await prepareSyncIntegrationTest(databaseService: databaseService);
    syncService =
        TransactionOpeningStockSyncService(databaseService: databaseService);
    final storage = CloudSecureStoragePlaceholder();
    TransactionSyncOutboxWriter.bindStorage(storage);
    await storage.writeDeviceId(deviceId);

    final db = await databaseService.database;
    for (final table in [
      'openingStocks',
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

  group('Transaction opening stock UI integration path', () {
    test('create draft and post enqueues create + post outbox once', () async {
      final result = await syncService.createOpeningStockDraftAndPost(
        openingStockId: openingStockId,
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        productId: productId,
        openingQuantity: 5,
        notes: 'UI test opening stock',
      );

      expect(result.ok, isTrue, reason: result.failureCode);

      final db = await databaseService.database;
      final openingStockDoc = await db.query(
        'openingStocks',
        where: 'id = ?',
        whereArgs: [openingStockId],
        limit: 1,
      );
      expect(openingStockDoc.first['openingStatus'], 'posted');
      expect(openingStockDoc.first['productId'], productId);
      expect(openingStockDoc.first['openingQuantity'], 5.0);

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [openingStockId],
      );
      expect(movements.length, 1);
      expect(movements.first['movementType'], 'in');
      expect(movements.first['referenceType'], 'opening_stock');
      expect(
        movements.first['id'],
        OpeningStockPostIds.stockMovementId(openingStockId),
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
        whereArgs: [openingStockId],
        orderBy: 'operation ASC',
      );
      expect(outbox.length, 2);
      expect(outbox.map((r) => r['operation']).toList(), ['create', 'post']);

      final replay = await OpeningStockPostLocalService(
        databaseService: databaseService,
      ).postDraft(openingStockId: openingStockId);
      expect(replay.ok, isTrue);
      expect(replay.idempotentReplay, isTrue);

      final outboxAfterReplay = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [openingStockId],
      );
      expect(outboxAfterReplay.length, 2);
    });
  });
}
