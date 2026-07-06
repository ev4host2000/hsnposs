import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/supplier_payment/supplier_payment_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/supplier_payment_draft_apply_handler.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_operation_dispatcher.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';
import 'payment_test_seed.dart';

/// Local sync-layer hardening for supplier payments (no live backend).
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const supplierId = 'd100e840-e29b-41d4-a716-446655440050';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const deviceId = '770e8400-e29b-41d4-a716-446655440002';
  const paymentId = 'b100e840-e29b-41d4-a716-446655440031';

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
      entityType: SupplierPaymentSyncConstants.entityType,
      entityId: paymentId,
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
    double amount = 50,
    String? notes,
  }) {
    final aggregate = supplierPaymentDraftAggregate(
      id: paymentId,
      organizationId: companyId,
      branchId: branchId,
      createdBy: userId,
      supplierId: supplierId,
      transactionVersion: transactionVersion,
      rowVersion: rowVersion,
      amount: amount,
      notes: notes,
      originDeviceId: deviceId,
    );
    return supplierPaymentDraftPushEnvelope(
      aggregateJson: aggregate,
      operation: operation,
      clientRowVersion: rowVersion,
    );
  }

  Future<void> seedDependencies() async {
    final db = await databaseService.database;
    for (final table in [
      'supplierPayments',
      'cashTransactions',
      'partnerLedger',
      'sync_outbox',
      'suppliers',
    ]) {
      await db.delete(table);
    }
    await db.insert('suppliers', {
      'id': supplierId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Sync Hardening Supplier',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> seedLocalDraft() async {
    final db = await databaseService.database;
    await PaymentTestSeed.seedSupplierPaymentDraft(
      db,
      paymentId: paymentId,
      companyId: companyId,
      branchId: branchId,
      supplierId: supplierId,
      userId: userId,
    );
  }

  Future<Map<String, int>> readEffectCounts() async {
    final db = await databaseService.database;
    final cash = await db.query(
      'cashTransactions',
      where: 'referenceId = ?',
      whereArgs: [paymentId],
    );
    final ledger = await db.query(
      'partnerLedger',
      where: 'referenceId = ?',
      whereArgs: [paymentId],
    );
    final outbox = await db.query(
      'sync_outbox',
      where: 'entity_id = ?',
      whereArgs: [paymentId],
    );
    return {
      'cash': cash.length,
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
      whereArgs: [paymentId, 'post'],
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
      entityType: SupplierPaymentSyncConstants.entityType,
      scopeKey: SupplierPaymentSyncConstants.scopeKey,
      pushPath: SupplierPaymentSyncConstants.pushPath,
      pullPath: SupplierPaymentSyncConstants.pullPath,
      applyHandler: SupplierPaymentDraftApplyHandler(),
    );
    await seedDependencies();
  });

  group('Supplier payment sync hardening', () {
    test('pull apply create upserts draft', () async {
      expect(await applyPull('create', draftEnvelope()), SyncPullApplyOutcome.applied);

      final db = await databaseService.database;
      final header = await db.query(
        'supplierPayments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      expect(header.first['paymentStatus'], 'draft');
      expect(header.first['supplierId'], supplierId);
      expect(header.first['amount'], 50.0);
    });

    test('pull apply deferred when supplier missing', () async {
      final db = await databaseService.database;
      await db.delete('suppliers', where: 'id = ?', whereArgs: [supplierId]);

      expect(await applyPull('create', draftEnvelope()), SyncPullApplyOutcome.deferred);
      expect(await db.query('supplierPayments', where: 'id = ?', whereArgs: [paymentId]), isEmpty);
    });

    test('pull apply post applies cash and ledger exactly once on replay', () async {
      await applyPull('create', draftEnvelope());

      final postService = SupplierPaymentPostLocalService(
        databaseService: databaseService,
      );
      expect((await postService.postDraft(paymentId: paymentId)).ok, isTrue);
      final envelope = await readPostEnvelopeFromOutbox();

      final db = await databaseService.database;
      await db.delete('cashTransactions');
      await db.delete('partnerLedger');
      await db.update(
        'supplierPayments',
        {
          'paymentStatus': 'draft',
          'transactionVersion': 0,
          'rowVersion': 1,
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      expect(await applyPull('post', envelope), SyncPullApplyOutcome.applied);
      expect(await applyPull('post', envelope), SyncPullApplyOutcome.applied);

      final counts = await readEffectCounts();
      expect(counts['cash'], 1);
      expect(counts['ledger'], 1);

      expect(
        (await db.query(
          'cashTransactions',
          where: 'id = ?',
          whereArgs: [SupplierPaymentPostIds.cashTransactionId(paymentId)],
        )).length,
        1,
      );
    });

    test('pull apply cancel removes draft', () async {
      await applyPull('create', draftEnvelope());
      final cancelEnvelope = supplierPaymentDraftPushEnvelope(
        aggregateJson: supplierPaymentDraftAggregate(
          id: paymentId,
          organizationId: companyId,
          branchId: branchId,
          createdBy: userId,
          supplierId: supplierId,
          amount: 50,
          transactionVersion: 1,
          rowVersion: 2,
          status: 'cancelled',
        ),
        operation: 'cancel',
        clientRowVersion: 2,
      );
      expect(await applyPull('cancel', cancelEnvelope), SyncPullApplyOutcome.applied);
      final db = await databaseService.database;
      expect(await db.query('supplierPayments', where: 'id = ?', whereArgs: [paymentId]), isEmpty);
    });

    test('duplicate pull apply update upserts without duplicate rows', () async {
      await applyPull('create', draftEnvelope(notes: 'v1'));
      await applyPull(
        'update',
        draftEnvelope(
          operation: 'update',
          transactionVersion: 1,
          rowVersion: 2,
          amount: 80,
          notes: 'v2',
        ),
      );

      final db = await databaseService.database;
      final header = await db.query(
        'supplierPayments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      expect(header.first['notes'], 'v2');
      expect(header.first['amount'], 80.0);
      expect(
        (await db.query(
          'supplierPayments',
          where: 'id = ?',
          whereArgs: [paymentId],
        )).length,
        1,
      );
    });

    test('stable post outbox idempotency key on replay', () async {
      await seedLocalDraft();
      final storage = CloudSecureStoragePlaceholder();
      TransactionSyncOutboxWriter.bindStorage(storage);
      await storage.writeDeviceId(deviceId);

      final service = SupplierPaymentPostLocalService(databaseService: databaseService);
      expect((await service.postDraft(paymentId: paymentId)).ok, isTrue);
      expect((await service.postDraft(paymentId: paymentId)).idempotentReplay, isTrue);

      final db = await databaseService.database;
      final keys = await db.query(
        'sync_outbox',
        columns: const ['idempotency_key'],
        where: 'entity_id = ? AND operation = ?',
        whereArgs: [paymentId, 'post'],
      );
      expect(keys.length, 1);
      expect(keys.first['idempotency_key'], contains(':post'));
    });

    test('post local service skips outbox on idempotent replay', () async {
      await seedLocalDraft();
      final storage = CloudSecureStoragePlaceholder();
      TransactionSyncOutboxWriter.bindStorage(storage);
      await storage.writeDeviceId(deviceId);

      final service = SupplierPaymentPostLocalService(databaseService: databaseService);
      expect((await service.postDraft(paymentId: paymentId)).ok, isTrue);
      expect((await service.postDraft(paymentId: paymentId)).idempotentReplay, isTrue);

      final counts = await readEffectCounts();
      expect(counts['cash'], 1);
      expect(counts['ledger'], 1);
      expect(counts['outbox'], 1);
    });
  });
}
