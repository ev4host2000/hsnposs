import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/customer_payment_post_effects.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/customer_payment_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/customer_payment_posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_accounting_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_finalize_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_integrity_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_validation_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';
import 'payment_test_seed.dart';

class _FailingPostingStage extends PostingStage {
  _FailingPostingStage(this.id, {this.code = 'forced_failure'});

  final String id;
  final String code;

  @override
  String get stageId => id;

  @override
  Future<PostingStageResult> run(PostingContext context) async {
    return PostingStageResult.failure(code: code, message: 'stage $id failed');
  }
}

void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const paymentId = 'b100e840-e29b-41d4-a716-446655440030';

  late DatabaseService databaseService;

  Future<void> seedDraft({double amount = 50}) async {
    final db = await databaseService.database;
    for (final table in [
      'customerPayments',
      'cashTransactions',
      'partnerLedger',
      'sync_outbox',
    ]) {
      await db.delete(table);
    }
    await db.delete('customers', where: 'id = ?', whereArgs: [customerId]);

    await db.insert('customers', {
      'id': customerId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Hardening Customer',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await PaymentTestSeed.seedCustomerPaymentDraft(
      db,
      paymentId: paymentId,
      companyId: companyId,
      branchId: branchId,
      customerId: customerId,
      userId: userId,
      amount: amount,
    );
  }

  MapTransactionAggregate draftAggregate({int transactionVersion = 0}) {
    return MapTransactionAggregate.fromParts(
      header: {
        'id': paymentId,
        'company_id': companyId,
        'branch_id': branchId,
        'document_type': 'customer_payment',
        'status': 'draft',
        'transaction_version': transactionVersion,
        'row_version': 1,
        'customer_id': customerId,
        'amount': 50,
        'payment_method': 'cash',
        'created_by_user_id': userId,
      },
      lines: const [],
    );
  }

  MapTransactionAggregate postedAggregateForReplay() {
    return MapTransactionAggregate.fromParts(
      header: {
        'id': paymentId,
        'company_id': companyId,
        'branch_id': branchId,
        'document_type': 'customer_payment',
        'status': 'posted',
        'transaction_version': 1,
        'row_version': 2,
        'customer_id': customerId,
        'amount': 50,
        'payment_method': 'cash',
        'created_by_user_id': userId,
      },
      lines: const [],
      metadata: {
        'payload_schema_version': 1,
        'cash': CustomerPaymentPostEffects.cashJson(
          CustomerPaymentPostEffects.buildCash(
            paymentId: paymentId,
            amount: 50,
            createdBy: userId,
          ),
        ),
        'accounting': CustomerPaymentPostEffects.accountingJson(
          CustomerPaymentPostEffects.buildAccounting(
            paymentId: paymentId,
            customerId: customerId,
            amount: 50,
            createdBy: userId,
          ),
        ),
      },
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
      where: 'entity_id = ? AND operation = ?',
      whereArgs: [paymentId, 'post'],
    );
    return {
      'cash': cash.length,
      'ledger': ledger.length,
      'outbox': outbox.length,
    };
  }

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    await seedDraft();
  });

  group('Customer payment post hardening', () {
    test('replay x10 does not duplicate effects or outbox', () async {
      final service = CustomerPaymentPostLocalService(
        databaseService: databaseService,
      );

      expect((await service.postDraft(paymentId: paymentId)).ok, isTrue);

      for (var i = 0; i < 10; i++) {
        final replay = await service.postDraft(paymentId: paymentId);
        expect(replay.ok, isTrue, reason: 'replay $i');
        expect(replay.idempotentReplay, isTrue, reason: 'replay $i');
      }

      final counts = await readEffectCounts();
      expect(counts['cash'], 1);
      expect(counts['ledger'], 1);
      expect(counts['outbox'], 1);
    });

    test('concurrent postDraft calls produce single post effects', () async {
      final service = CustomerPaymentPostLocalService(
        databaseService: databaseService,
      );

      final results = await Future.wait([
        service.postDraft(paymentId: paymentId),
        service.postDraft(paymentId: paymentId),
        service.postDraft(paymentId: paymentId),
      ]);

      expect(results.where((r) => r.ok).length, 3);
      expect(results.where((r) => r.idempotentReplay).length, greaterThanOrEqualTo(2));

      final db = await databaseService.database;
      final paymentDoc = await db.query(
        'customerPayments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      expect(paymentDoc.first['paymentStatus'], 'posted');

      final counts = await readEffectCounts();
      expect(counts['cash'], 1);
      expect(counts['ledger'], 1);
      expect(counts['outbox'], 1);
    });

    test('transaction_version mismatch is rejected', () async {
      final db = await databaseService.database;
      final aggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': paymentId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'customer_payment',
          'status': 'draft',
          'transaction_version': 5,
          'row_version': 1,
          'customer_id': customerId,
          'amount': 50,
          'created_by_user_id': userId,
        },
        lines: const [],
      );

      late PostingResult result;
      await db.transaction((txn) async {
        result = await CustomerPaymentPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: CustomerPaymentSyncConstants.entityType,
          ),
        );
      });

      expect(result.ok, isFalse);
      expect(result.failureCode, 'transaction_version_mismatch');
    });

    test('post on already posted payment with stale version fails', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        await CustomerPaymentPostingPipeline.create().run(
          PostingContext(
            aggregate: draftAggregate(),
            txn: txn,
            entityType: CustomerPaymentSyncConstants.entityType,
          ),
        );
      });

      final staleAggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': paymentId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'customer_payment',
          'status': 'posted',
          'transaction_version': 2,
          'row_version': 3,
          'customer_id': customerId,
          'amount': 50,
          'created_by_user_id': userId,
        },
        lines: const [],
      );

      late PostingResult result;
      await db.transaction((txn) async {
        result = await CustomerPaymentPostingPipeline.create().run(
          PostingContext(
            aggregate: staleAggregate,
            txn: txn,
            entityType: CustomerPaymentSyncConstants.entityType,
          ),
        );
      });

      expect(result.ok, isFalse);
      expect(result.failureCode, 'already_posted');
    });

    test('device B scenario — post after already posted skips duplicate outbox',
        () async {
      final service = CustomerPaymentPostLocalService(
        databaseService: databaseService,
      );
      expect((await service.postDraft(paymentId: paymentId)).ok, isTrue);

      final replay = await service.postDraft(paymentId: paymentId);
      expect(replay.ok, isTrue);
      expect(replay.idempotentReplay, isTrue);

      final counts = await readEffectCounts();
      expect(counts['cash'], 1);
      expect(counts['outbox'], 1);
    });

    test('accounting stage failure rolls back all effects', () async {
      final db = await databaseService.database;
      final pipeline = PostingPipeline(
        stages: [
          CustomerPaymentValidationPostingStage(),
          CustomerPaymentAccountingPostingStage(),
          _FailingPostingStage('integrity'),
          CustomerPaymentFinalizePostingStage(),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: draftAggregate(),
              txn: txn,
              entityType: CustomerPaymentSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'integrity');
      }

      final counts = await readEffectCounts();
      expect(counts['cash'], 0);
      expect(counts['ledger'], 0);

      final paymentDoc = await db.query(
        'customerPayments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      expect(paymentDoc.first['paymentStatus'], 'draft');
    });

    test('integrity stage failure rolls back accounting', () async {
      final db = await databaseService.database;
      final badAggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': paymentId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'customer_payment',
          'status': 'draft',
          'transaction_version': 0,
          'row_version': 1,
          'customer_id': customerId,
          'amount': 50,
          'payment_method': 'cash',
          'created_by_user_id': userId,
        },
        lines: const [],
        metadata: {
          'payload_schema_version': 1,
          'cash': CustomerPaymentPostEffects.cashJson(
            CustomerPaymentPostEffects.buildCash(
              paymentId: paymentId,
              amount: 999,
              createdBy: userId,
            ),
          ),
          'accounting': CustomerPaymentPostEffects.accountingJson(
            CustomerPaymentPostEffects.buildAccounting(
              paymentId: paymentId,
              customerId: customerId,
              amount: 50,
              createdBy: userId,
            ),
          ),
        },
      );

      try {
        await db.transaction((txn) async {
          final result = await CustomerPaymentPostingPipeline.create().run(
            PostingContext(
              aggregate: badAggregate,
              txn: txn,
              entityType: CustomerPaymentSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'integrity');
        expect(e.result.failureCode, 'posting_integrity_violation');
      }

      final counts = await readEffectCounts();
      expect(counts['cash'], 0);
      expect(counts['ledger'], 0);
    });

    test('crash recovery — replay pipeline after successful post is idempotent', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        await CustomerPaymentPostingPipeline.create().run(
          PostingContext(
            aggregate: draftAggregate(),
            txn: txn,
            entityType: CustomerPaymentSyncConstants.entityType,
          ),
        );
      });

      for (var i = 0; i < 3; i++) {
        await db.transaction((txn) async {
          final replay = await CustomerPaymentPostingPipeline.create().run(
            PostingContext(
              aggregate: postedAggregateForReplay(),
              txn: txn,
              entityType: CustomerPaymentSyncConstants.entityType,
            ),
          );
          expect(replay.ok, isTrue);
          expect(replay.idempotentReplay, isTrue);
        });
      }

      final counts = await readEffectCounts();
      expect(counts['cash'], 1);
      expect(counts['ledger'], 1);

      final cashId = CustomerPaymentPostIds.cashTransactionId(paymentId);
      final cash = await db.query(
        'cashTransactions',
        where: 'id = ?',
        whereArgs: [cashId],
      );
      expect(cash.length, 1);
    });

    test('finalize posting_conflict rolls back all effects', () async {
      final db = await databaseService.database;
      final pipeline = PostingPipeline(
        stages: [
          CustomerPaymentValidationPostingStage(),
          CustomerPaymentAccountingPostingStage(),
          CustomerPaymentIntegrityPostingStage(),
          _FailingPostingStage('finalize', code: 'posting_conflict'),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: draftAggregate(),
              txn: txn,
              entityType: CustomerPaymentSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'finalize');
        expect(e.result.failureCode, 'posting_conflict');
      }

      final counts = await readEffectCounts();
      expect(counts['cash'], 0);
      expect(counts['ledger'], 0);
    });

    test('stable outbox idempotency key prevents duplicate outbox rows', () async {
      final service = CustomerPaymentPostLocalService(
        databaseService: databaseService,
      );
      expect((await service.postDraft(paymentId: paymentId)).ok, isTrue);

      final db = await databaseService.database;
      final keys = await db.query(
        'sync_outbox',
        columns: const ['idempotency_key'],
        where: 'entity_id = ?',
        whereArgs: [paymentId],
      );
      expect(keys.length, 1);
      expect(keys.first['idempotency_key'], contains(':post'));
    });

    test('integrity stage rejects unbalanced accounting', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        final context = PostingContext(
          aggregate: draftAggregate(),
          txn: txn,
          entityType: CustomerPaymentSyncConstants.entityType,
        );
        await CustomerPaymentValidationPostingStage().run(context);
        await CustomerPaymentAccountingPostingStage().run(context);

        final accounting = context.stageData['accounting'];
        if (accounting is CustomerPaymentAccountingEffect) {
          context.stageData['accounting'] = CustomerPaymentAccountingEffect(
            entryId: accounting.entryId,
            partnerKind: accounting.partnerKind,
            partnerId: accounting.partnerId,
            entryType: accounting.entryType,
            referenceType: accounting.referenceType,
            referenceId: accounting.referenceId,
            amountSigned: -999,
            entryDate: accounting.entryDate,
            createdBy: accounting.createdBy,
          );
        }

        final result = await CustomerPaymentIntegrityPostingStage().run(context);
        expect(result.isFailure, isTrue);
        expect(result.code, 'posting_integrity_violation');
      });
    });
  });
}
