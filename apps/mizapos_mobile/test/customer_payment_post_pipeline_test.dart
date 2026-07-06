import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/customer_payment_post_effects.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/customer_payment_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/customer_payment_posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_accounting_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_finalize_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_integrity_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/stages/customer_payment_validation_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
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

MapTransactionAggregate _draftAggregate({
  required String paymentId,
  required String companyId,
  required String branchId,
  required String customerId,
  required String userId,
  int transactionVersion = 0,
  int rowVersion = 1,
  double amount = 50,
  Map<String, dynamic>? metadataExtra,
}) {
  return MapTransactionAggregate.fromParts(
    header: {
      'id': paymentId,
      'company_id': companyId,
      'branch_id': branchId,
      'document_type': 'customer_payment',
      'status': 'draft',
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'customer_id': customerId,
      'amount': amount,
      'payment_method': 'cash',
      'created_by_user_id': userId,
    },
    lines: const [],
    metadata: {
      'payload_schema_version': 1,
      if (metadataExtra != null) ...metadataExtra,
    },
  );
}

void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const paymentId = 'b100e840-e29b-41d4-a716-446655440030';

  late DatabaseService databaseService;

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
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
      'name': 'Post Test Customer',
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
    );
  });

  group('CustomerPaymentPostingPipeline', () {
    test('posts draft with accounting and finalize', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        final aggregate = _draftAggregate(
          paymentId: paymentId,
          companyId: companyId,
          branchId: branchId,
          customerId: customerId,
          userId: userId,
        );

        final result = await CustomerPaymentPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: CustomerPaymentSyncConstants.entityType,
          ),
        );

        expect(result.ok, isTrue);
      });

      final paymentDoc = await db.query(
        'customerPayments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      expect(paymentDoc.first['paymentStatus'], 'posted');
      expect(paymentDoc.first['transactionVersion'], 1);

      final cash = await db.query(
        'cashTransactions',
        where: 'referenceId = ?',
        whereArgs: [paymentId],
      );
      expect(cash.length, 1);
      expect(cash.first['transactionType'], 'in');
      expect(
        cash.first['id'],
        CustomerPaymentPostIds.cashTransactionId(paymentId),
      );

      final ledger = await db.query(
        'partnerLedger',
        where: 'referenceId = ?',
        whereArgs: [paymentId],
      );
      expect(ledger.length, 1);
      expect(
        ledger.first['id'],
        CustomerPaymentPostIds.accountingEntryId(paymentId),
      );
    });

    test('local post service enqueues single post outbox event', () async {
      final service = CustomerPaymentPostLocalService(
        databaseService: databaseService,
      );
      final result = await service.postDraft(paymentId: paymentId);
      expect(result.ok, isTrue);

      final db = await databaseService.database;
      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [paymentId],
      );
      expect(outbox.length, 1);
      expect(outbox.first['operation'], 'post');
    });

    test('idempotent replay does not duplicate effects', () async {
      final db = await databaseService.database;
      final aggregate = _draftAggregate(
        paymentId: paymentId,
        companyId: companyId,
        branchId: branchId,
        customerId: customerId,
        userId: userId,
      );

      await db.transaction((txn) async {
        final first = await CustomerPaymentPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: CustomerPaymentSyncConstants.entityType,
          ),
        );
        abortPostingTransactionIfFailed(first);
      });

      final postedAggregate = MapTransactionAggregate.fromParts(
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

      await db.transaction((txn) async {
        final replay = await CustomerPaymentPostingPipeline.create().run(
          PostingContext(
            aggregate: postedAggregate,
            txn: txn,
            entityType: CustomerPaymentSyncConstants.entityType,
          ),
        );
        expect(replay.ok, isTrue);
        expect(replay.idempotentReplay, isTrue);
      });

      final cash = await db.query(
        'cashTransactions',
        where: 'referenceId = ?',
        whereArgs: [paymentId],
      );
      expect(cash.length, 1);

      final ledger = await db.query(
        'partnerLedger',
        where: 'referenceId = ?',
        whereArgs: [paymentId],
      );
      expect(ledger.length, 1);
    });

    test('validation fails when customer missing', () async {
      final db = await databaseService.database;

      final aggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': paymentId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'customer_payment',
          'status': 'draft',
          'transaction_version': 0,
          'row_version': 1,
          'amount': 50,
          'created_by_user_id': userId,
        },
        lines: const [],
      );

      await db.transaction((txn) async {
        final result = await CustomerPaymentPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: CustomerPaymentSyncConstants.entityType,
          ),
        );
        expect(result.ok, isFalse);
        expect(result.failureCode, 'missing_customer');
      });
    });

    test('accounting stage failure aborts pipeline', () async {
      final db = await databaseService.database;
      final pipeline = PostingPipeline(
        stages: [
          CustomerPaymentValidationPostingStage(),
          _FailingPostingStage('accounting'),
          CustomerPaymentIntegrityPostingStage(),
          CustomerPaymentFinalizePostingStage(),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: _draftAggregate(
                paymentId: paymentId,
                companyId: companyId,
                branchId: branchId,
                customerId: customerId,
                userId: userId,
              ),
              txn: txn,
              entityType: CustomerPaymentSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'accounting');
      }

      final cash = await db.query(
        'cashTransactions',
        where: 'referenceId = ?',
        whereArgs: [paymentId],
      );
      expect(cash, isEmpty);
    });

    test('accounting stage failure rolls back cash effects', () async {
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
              aggregate: _draftAggregate(
                paymentId: paymentId,
                companyId: companyId,
                branchId: branchId,
                customerId: customerId,
                userId: userId,
              ),
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

      final cash = await db.query(
        'cashTransactions',
        where: 'referenceId = ?',
        whereArgs: [paymentId],
      );
      expect(cash, isEmpty);
      final ledger = await db.query(
        'partnerLedger',
        where: 'referenceId = ?',
        whereArgs: [paymentId],
      );
      expect(ledger, isEmpty);
    });

    test('integrity stage failure rolls back effects', () async {
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

      final cash = await db.query(
        'cashTransactions',
        where: 'referenceId = ?',
        whereArgs: [paymentId],
      );
      expect(cash, isEmpty);
    });

    test('finalize stage failure rolls back prior stages', () async {
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
              aggregate: _draftAggregate(
                paymentId: paymentId,
                companyId: companyId,
                branchId: branchId,
                customerId: customerId,
                userId: userId,
              ),
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

      final paymentDoc = await db.query(
        'customerPayments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      expect(paymentDoc.first['paymentStatus'], 'draft');

      final cash = await db.query(
        'cashTransactions',
        where: 'referenceId = ?',
        whereArgs: [paymentId],
      );
      expect(cash, isEmpty);
    });
  });
}
