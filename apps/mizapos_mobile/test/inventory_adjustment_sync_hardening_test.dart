import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/inventory_adjustment_draft_apply_handler.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_operation_dispatcher.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'adjustment_test_seed.dart';
import 'isolated_test_database.dart';

/// Local sync-layer hardening for inventory adjustments (no live backend).
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const deviceId = '770e8400-e29b-41d4-a716-446655440002';
  const adjustmentId = 'b100e840-e29b-41d4-a716-446655440030';

  late DatabaseService databaseService;
  late TransactionOperationDispatcher dispatcher;
  late TransactionTypeDefinition typeDef;

  SyncChangelogEntry changelogEntry({
    required String operation,
    required Map<String, dynamic> envelope,
    int sequence = 1,
    int rowVersion = 1,
  }) {
    return SyncChangelogEntry(
      sequence: sequence,
      entityType: InventoryAdjustmentSyncConstants.entityType,
      entityId: adjustmentId,
      operation: operation,
      payloadJson: envelope,
      rowVersion: rowVersion,
      originDeviceId: deviceId,
    );
  }

  Map<String, dynamic> draftEnvelope({
    String operation = 'create',
    int transactionVersion = 0,
    int rowVersion = 1,
    double quantityDelta = 5,
    String? notes,
  }) {
    final aggregate = inventoryAdjustmentDraftAggregate(
      id: adjustmentId,
      organizationId: companyId,
      branchId: branchId,
      createdBy: userId,
      productId: productId,
      quantityDelta: quantityDelta,
      adjustmentReason: 'correction',
      transactionVersion: transactionVersion,
      rowVersion: rowVersion,
      notes: notes,
      originDeviceId: deviceId,
    );
    return inventoryAdjustmentDraftPushEnvelope(
      aggregateJson: aggregate,
      operation: operation,
      clientRowVersion: rowVersion,
    );
  }

  Future<void> seedDependencies() async {
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
      'name': 'Sync Hardening Product',
      'salePrice': 25.0,
      'costPrice': 10.0,
      'stockQty': 10.0,
      'isHidden': 0,
      'isFrozen': 0,
      'isService': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> seedLocalDraft() async {
    final db = await databaseService.database;
    await AdjustmentTestSeed.seedInventoryAdjustmentDraft(
      db,
      adjustmentId: adjustmentId,
      companyId: companyId,
      branchId: branchId,
      productId: productId,
      userId: userId,
    );
  }

  Future<Map<String, int>> readEffectCounts() async {
    final db = await databaseService.database;
    final movements = await db.query(
      'stockMovements',
      where: 'referenceId = ?',
      whereArgs: [adjustmentId],
    );
    final outbox = await db.query(
      'sync_outbox',
      where: 'entity_id = ?',
      whereArgs: [adjustmentId],
    );
    return {
      'movements': movements.length,
      'outbox': outbox.length,
    };
  }

  Future<SyncPullApplyOutcome> applyPull(
    String operation,
    Map<String, dynamic> envelope,
  ) async {
    final db = await databaseService.database;
    late SyncPullApplyOutcome outcome;
    await db.transaction((txn) async {
      outcome = await dispatcher.dispatchPullApply(
        entry: changelogEntry(operation: operation, envelope: envelope),
        type: typeDef,
        txn: txn,
      );
    });
    return outcome;
  }

  Future<Map<String, dynamic>> readPostEnvelopeFromOutbox() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'sync_outbox',
      where: 'entity_id = ? AND operation = ?',
      whereArgs: [adjustmentId, 'post'],
      limit: 1,
    );
    expect(rows, isNotEmpty);
    final raw = rows.first['payload_json'] as String?;
    expect(raw, isNotNull);
    return Map<String, dynamic>.from(jsonDecode(raw!) as Map);
  }

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    dispatcher = TransactionOperationDispatcher();
    typeDef = TransactionTypeDefinition(
      entityType: InventoryAdjustmentSyncConstants.entityType,
      scopeKey: InventoryAdjustmentSyncConstants.scopeKey,
      pushPath: InventoryAdjustmentSyncConstants.pushPath,
      pullPath: InventoryAdjustmentSyncConstants.pullPath,
      applyHandler: InventoryAdjustmentDraftApplyHandler(),
    );
    await seedDependencies();
  });

  group('Inventory adjustment sync hardening', () {
    test('pull apply create upserts draft', () async {
      expect(await applyPull('create', draftEnvelope()), SyncPullApplyOutcome.applied);

      final db = await databaseService.database;
      final header = await db.query(
        'inventoryAdjustments',
        where: 'id = ?',
        whereArgs: [adjustmentId],
        limit: 1,
      );
      expect(header.first['adjustmentStatus'], 'draft');
      expect(header.first['productId'], productId);
      expect(header.first['quantityDelta'], 5.0);
    });

    test('pull apply deferred when product missing', () async {
      final db = await databaseService.database;
      await db.delete('products', where: 'id = ?', whereArgs: [productId]);

      expect(await applyPull('create', draftEnvelope()), SyncPullApplyOutcome.deferred);
      expect(
        await db.query('inventoryAdjustments', where: 'id = ?', whereArgs: [adjustmentId]),
        isEmpty,
      );
    });

    test('pull apply post applies stock movement exactly once on replay', () async {
      await applyPull('create', draftEnvelope());

      final postService = InventoryAdjustmentPostLocalService(
        databaseService: databaseService,
      );
      expect((await postService.postDraft(adjustmentId: adjustmentId)).ok, isTrue);
      final envelope = await readPostEnvelopeFromOutbox();

      final db = await databaseService.database;
      await db.delete('stockMovements');
      await db.update(
        'inventoryAdjustments',
        {
          'adjustmentStatus': 'draft',
          'transactionVersion': 0,
          'rowVersion': 1,
        },
        where: 'id = ?',
        whereArgs: [adjustmentId],
      );
      await db.update(
        'products',
        {'stockQty': 10.0},
        where: 'id = ?',
        whereArgs: [productId],
      );

      expect(await applyPull('post', envelope), SyncPullApplyOutcome.applied);
      expect(await applyPull('post', envelope), SyncPullApplyOutcome.applied);

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);

      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect(product.first['stockQty'], 15.0);
      expect(
        (await db.query(
          'stockMovements',
          where: 'id = ?',
          whereArgs: [InventoryAdjustmentPostIds.stockMovementId(adjustmentId)],
        )).length,
        1,
      );
    });

    test('pull apply cancel removes draft', () async {
      await applyPull('create', draftEnvelope());
      final cancelEnvelope = inventoryAdjustmentDraftPushEnvelope(
        aggregateJson: inventoryAdjustmentDraftAggregate(
          id: adjustmentId,
          organizationId: companyId,
          branchId: branchId,
          createdBy: userId,
          productId: productId,
          quantityDelta: 5,
          adjustmentReason: 'correction',
          transactionVersion: 1,
          rowVersion: 2,
          status: 'cancelled',
        ),
        operation: 'cancel',
        clientRowVersion: 2,
      );
      expect(await applyPull('cancel', cancelEnvelope), SyncPullApplyOutcome.applied);
      final db = await databaseService.database;
      expect(
        await db.query('inventoryAdjustments', where: 'id = ?', whereArgs: [adjustmentId]),
        isEmpty,
      );
    });

    test('duplicate pull apply update upserts without duplicate rows', () async {
      await applyPull('create', draftEnvelope(notes: 'v1'));
      await applyPull(
        'update',
        draftEnvelope(
          operation: 'update',
          transactionVersion: 1,
          rowVersion: 2,
          quantityDelta: 8,
          notes: 'v2',
        ),
      );

      final db = await databaseService.database;
      final header = await db.query(
        'inventoryAdjustments',
        where: 'id = ?',
        whereArgs: [adjustmentId],
        limit: 1,
      );
      expect(header.first['notes'], 'v2');
      expect(header.first['quantityDelta'], 8.0);
      expect(
        (await db.query(
          'inventoryAdjustments',
          where: 'id = ?',
          whereArgs: [adjustmentId],
        )).length,
        1,
      );
    });

    test('stable post outbox idempotency key on replay', () async {
      await seedLocalDraft();
      final storage = CloudSecureStoragePlaceholder();
      TransactionSyncOutboxWriter.bindStorage(storage);
      await storage.writeDeviceId(deviceId);

      final service =
          InventoryAdjustmentPostLocalService(databaseService: databaseService);
      expect((await service.postDraft(adjustmentId: adjustmentId)).ok, isTrue);
      expect(
        (await service.postDraft(adjustmentId: adjustmentId)).idempotentReplay,
        isTrue,
      );

      final db = await databaseService.database;
      final keys = await db.query(
        'sync_outbox',
        columns: const ['idempotency_key'],
        where: 'entity_id = ? AND operation = ?',
        whereArgs: [adjustmentId, 'post'],
      );
      expect(keys.length, 1);
      expect(keys.first['idempotency_key'], contains(':post'));
    });

    test('post local service skips outbox on idempotent replay', () async {
      await seedLocalDraft();
      final storage = CloudSecureStoragePlaceholder();
      TransactionSyncOutboxWriter.bindStorage(storage);
      await storage.writeDeviceId(deviceId);

      final service =
          InventoryAdjustmentPostLocalService(databaseService: databaseService);
      expect((await service.postDraft(adjustmentId: adjustmentId)).ok, isTrue);
      expect(
        (await service.postDraft(adjustmentId: adjustmentId)).idempotentReplay,
        isTrue,
      );

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);
      expect(counts['outbox'], 1);
    });
  });
}
