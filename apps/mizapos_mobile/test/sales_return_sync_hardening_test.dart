import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/sales_return/sales_return_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/sales_return_draft_apply_handler.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_operation_dispatcher.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';
import 'return_test_seed.dart';

/// Local sync-layer hardening for sales returns (no live backend).
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const deviceId = '770e8400-e29b-41d4-a716-446655440002';
  const originalInvoiceId = 'b000e840-e29b-41d4-a716-446655440029';
  const parentLineId = 'b100e840-e29b-41d4-a716-446655440028';
  const returnId = 'b100e840-e29b-41d4-a716-446655440030';
  const returnLineId = 'b200e840-e29b-41d4-a716-446655440031';

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
      entityType: SalesReturnSyncConstants.entityType,
      entityId: returnId,
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
    double total = 50,
    String? notes,
  }) {
    final aggregate = salesReturnDraftAggregate(
      id: returnId,
      organizationId: companyId,
      branchId: branchId,
      createdBy: userId,
      originalInvoiceId: originalInvoiceId,
      customerId: customerId,
      transactionVersion: transactionVersion,
      rowVersion: rowVersion,
      lineSubtotal: total,
      total: total,
      notes: notes,
      lines: [
        salesReturnLinePayload(
          lineId: returnLineId,
          productId: productId,
          quantity: 2,
          unitPrice: total / 2,
        ),
      ],
      originDeviceId: deviceId,
    );
    return salesReturnDraftPushEnvelope(
      aggregateJson: aggregate,
      operation: operation,
      clientRowVersion: rowVersion,
    );
  }

  Future<void> seedDependencies() async {
    final db = await databaseService.database;
    for (final table in [
      'salesReturns',
      'salesReturnItems',
      'salesInvoices',
      'salesInvoiceItems',
      'stockMovements',
      'partnerLedger',
      'sync_outbox',
      'customers',
    ]) {
      await db.delete(table);
    }
    await db.delete('products', where: 'id = ?', whereArgs: [productId]);
    await db.insert('customers', {
      'id': customerId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Sync Hardening Customer',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('products', {
      'id': productId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Sync Hardening Product',
      'salePrice': 25.0,
      'costPrice': 10.0,
      'stockQty': 98.0,
      'isHidden': 0,
      'isFrozen': 0,
      'isService': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await ReturnTestSeed.seedPostedParentSalesInvoice(
      db,
      originalInvoiceId: originalInvoiceId,
      parentLineId: parentLineId,
      companyId: companyId,
      branchId: branchId,
      customerId: customerId,
      productId: productId,
      userId: userId,
    );
  }

  Future<void> seedLocalDraft() async {
    final db = await databaseService.database;
    await ReturnTestSeed.seedSalesReturnDraft(
      db,
      returnId: returnId,
      returnLineId: returnLineId,
      originalInvoiceId: originalInvoiceId,
      companyId: companyId,
      branchId: branchId,
      customerId: customerId,
      productId: productId,
      userId: userId,
    );
  }

  Future<Map<String, int>> readEffectCounts() async {
    final db = await databaseService.database;
    final movements = await db.query(
      'stockMovements',
      where: 'referenceId = ?',
      whereArgs: [returnId],
    );
    final ledger = await db.query(
      'partnerLedger',
      where: 'referenceId = ?',
      whereArgs: [returnId],
    );
    final outbox = await db.query(
      'sync_outbox',
      where: 'entity_id = ?',
      whereArgs: [returnId],
    );
    return {
      'movements': movements.length,
      'ledger': ledger.length,
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
      whereArgs: [returnId, 'post'],
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
      entityType: SalesReturnSyncConstants.entityType,
      scopeKey: SalesReturnSyncConstants.scopeKey,
      pushPath: SalesReturnSyncConstants.pushPath,
      pullPath: SalesReturnSyncConstants.pullPath,
      applyHandler: SalesReturnDraftApplyHandler(),
    );
    await seedDependencies();
  });

  group('Sales return sync hardening', () {
    test('pull apply create upserts draft', () async {
      expect(await applyPull('create', draftEnvelope()), SyncPullApplyOutcome.applied);

      final db = await databaseService.database;
      final header = await db.query(
        'salesReturns',
        where: 'id = ?',
        whereArgs: [returnId],
        limit: 1,
      );
      expect(header.first['returnStatus'], 'draft');
      expect(header.first['customerId'], customerId);
      expect(header.first['originalInvoiceId'], originalInvoiceId);
    });

    test('pull apply deferred when customer missing', () async {
      final db = await databaseService.database;
      await db.delete('customers', where: 'id = ?', whereArgs: [customerId]);

      expect(await applyPull('create', draftEnvelope()), SyncPullApplyOutcome.deferred);
      expect(await db.query('salesReturns', where: 'id = ?', whereArgs: [returnId]), isEmpty);
    });

    test('pull apply post increases inventory exactly once on replay', () async {
      await applyPull('create', draftEnvelope());

      final postService = SalesReturnPostLocalService(
        databaseService: databaseService,
      );
      expect((await postService.postDraft(returnId: returnId)).ok, isTrue);
      final envelope = await readPostEnvelopeFromOutbox();

      final db = await databaseService.database;
      await db.delete('stockMovements');
      await db.delete('partnerLedger');
      await db.update(
        'salesReturns',
        {
          'returnStatus': 'draft',
          'transactionVersion': 0,
          'rowVersion': 1,
        },
        where: 'id = ?',
        whereArgs: [returnId],
      );
      await db.update(
        'products',
        {'stockQty': 98.0},
        where: 'id = ?',
        whereArgs: [productId],
      );

      expect(await applyPull('post', envelope), SyncPullApplyOutcome.applied);
      expect(await applyPull('post', envelope), SyncPullApplyOutcome.applied);

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);
      expect(counts['ledger'], 2);

      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect(product.first['stockQty'], 100.0);
      expect(
        (await db.query(
          'stockMovements',
          where: 'id = ?',
          whereArgs: [SalesReturnPostIds.stockMovementId(returnId, returnLineId)],
        )).length,
        1,
      );
    });

    test('pull apply cancel removes draft', () async {
      await applyPull('create', draftEnvelope());
      final cancelEnvelope = salesReturnDraftPushEnvelope(
        aggregateJson: salesReturnDraftAggregate(
          id: returnId,
          organizationId: companyId,
          branchId: branchId,
          createdBy: userId,
          originalInvoiceId: originalInvoiceId,
          customerId: customerId,
          transactionVersion: 1,
          rowVersion: 2,
          status: 'cancelled',
        ),
        operation: 'cancel',
        clientRowVersion: 2,
      );
      expect(await applyPull('cancel', cancelEnvelope), SyncPullApplyOutcome.applied);
      final db = await databaseService.database;
      expect(await db.query('salesReturns', where: 'id = ?', whereArgs: [returnId]), isEmpty);
    });

    test('duplicate pull apply update upserts without duplicate lines', () async {
      await applyPull('create', draftEnvelope(notes: 'v1'));
      await applyPull(
        'update',
        draftEnvelope(
          operation: 'update',
          transactionVersion: 1,
          rowVersion: 2,
          total: 80,
          notes: 'v2',
        ),
      );

      final db = await databaseService.database;
      final header = await db.query(
        'salesReturns',
        where: 'id = ?',
        whereArgs: [returnId],
        limit: 1,
      );
      expect(header.first['notes'], 'v2');
      expect(header.first['total'], 80.0);
      expect(
        (await db.query(
          'salesReturnItems',
          where: 'returnId = ?',
          whereArgs: [returnId],
        )).length,
        1,
      );
    });

    test('stable post outbox idempotency key on replay', () async {
      await seedLocalDraft();
      final storage = CloudSecureStoragePlaceholder();
      TransactionSyncOutboxWriter.bindStorage(storage);
      await storage.writeDeviceId(deviceId);

      final service = SalesReturnPostLocalService(databaseService: databaseService);
      expect((await service.postDraft(returnId: returnId)).ok, isTrue);
      expect((await service.postDraft(returnId: returnId)).idempotentReplay, isTrue);

      final db = await databaseService.database;
      final keys = await db.query(
        'sync_outbox',
        columns: const ['idempotency_key'],
        where: 'entity_id = ? AND operation = ?',
        whereArgs: [returnId, 'post'],
      );
      expect(keys.length, 1);
      expect(keys.first['idempotency_key'], contains(':post'));
    });

    test('post local service skips outbox on idempotent replay', () async {
      await seedLocalDraft();
      final storage = CloudSecureStoragePlaceholder();
      TransactionSyncOutboxWriter.bindStorage(storage);
      await storage.writeDeviceId(deviceId);

      final service = SalesReturnPostLocalService(databaseService: databaseService);
      expect((await service.postDraft(returnId: returnId)).ok, isTrue);
      expect((await service.postDraft(returnId: returnId)).idempotentReplay, isTrue);

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);
      expect(counts['ledger'], 2);
      expect(counts['outbox'], 1);
    });
  });
}
