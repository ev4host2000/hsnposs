import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/purchase_return_post_effects.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/purchase_return_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/purchase_return_posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_accounting_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_finalize_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_integrity_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_inventory_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_return/stages/purchase_return_validation_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_return_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_return_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';
import 'return_test_seed.dart';

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
  const supplierId = 'd100e840-e29b-41d4-a716-446655440050';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const originalInvoiceId = 'b000e840-e29b-41d4-a716-446655440029';
  const parentLineId = 'b100e840-e29b-41d4-a716-446655440028';
  const returnId = 'b100e840-e29b-41d4-a716-446655440030';
  const returnLineId = 'b200e840-e29b-41d4-a716-446655440031';

  late DatabaseService databaseService;

  Future<void> seedDraft({double total = 50}) async {
    final db = await databaseService.database;
    for (final table in [
      'purchaseReturns',
      'purchaseReturnItems',
      'purchaseInvoices',
      'purchaseInvoiceItems',
      'stockMovements',
      'partnerLedger',
      'sync_outbox',
    ]) {
      await db.delete(table);
    }
    await db.delete('products', where: 'id = ?', whereArgs: [productId]);
    await db.delete('suppliers', where: 'id = ?', whereArgs: [supplierId]);

    await db.insert('suppliers', {
      'id': supplierId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Hardening Supplier',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('products', {
      'id': productId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Hardening Product',
      'salePrice': 25.0,
      'costPrice': 10.0,
      'stockQty': 10000.0,
      'isHidden': 0,
      'isFrozen': 0,
      'isService': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await ReturnTestSeed.seedPostedParentPurchaseInvoice(
      db,
      originalInvoiceId: originalInvoiceId,
      parentLineId: parentLineId,
      companyId: companyId,
      branchId: branchId,
      supplierId: supplierId,
      productId: productId,
      userId: userId,
      total: total,
    );
    await ReturnTestSeed.seedPurchaseReturnDraft(
      db,
      returnId: returnId,
      returnLineId: returnLineId,
      originalInvoiceId: originalInvoiceId,
      companyId: companyId,
      branchId: branchId,
      supplierId: supplierId,
      productId: productId,
      userId: userId,
      total: total,
    );
  }

  MapTransactionAggregate draftAggregate({int transactionVersion = 0}) {
    return MapTransactionAggregate.fromParts(
      header: {
        'id': returnId,
        'company_id': companyId,
        'branch_id': branchId,
        'document_type': 'purchase_return',
        'status': 'draft',
        'transaction_version': transactionVersion,
        'row_version': 1,
        'original_invoice_id': originalInvoiceId,
        'supplier_id': supplierId,
        'total': 50,
        'line_subtotal': 50,
        'tax_percent': 0,
        'discount_amount': 0,
        'created_by_user_id': userId,
      },
      lines: [
        {
          'line_id': returnLineId,
          'product_id': productId,
          'quantity': 2,
          'unit_cost': 25,
          'line_total': 50,
        },
      ],
    );
  }

  MapTransactionAggregate postedAggregateForReplay() {
    return MapTransactionAggregate.fromParts(
      header: {
        'id': returnId,
        'company_id': companyId,
        'branch_id': branchId,
        'document_type': 'purchase_return',
        'status': 'posted',
        'transaction_version': 1,
        'row_version': 2,
        'original_invoice_id': originalInvoiceId,
        'supplier_id': supplierId,
        'total': 50,
        'line_subtotal': 50,
        'created_by_user_id': userId,
      },
      lines: [
        {
          'line_id': returnLineId,
          'product_id': productId,
          'quantity': 2,
          'unit_cost': 25,
          'line_total': 50,
        },
      ],
      metadata: {
        'payload_schema_version': 1,
        'inventory': PurchaseReturnPostEffects.inventoryJson(
          PurchaseReturnPostEffects.buildInventory(
            returnId: returnId,
            organizationId: companyId,
            branchId: branchId,
            lines: [
              {'line_id': returnLineId, 'product_id': productId, 'quantity': 2},
            ],
            createdBy: userId,
          ),
        ),
        'accounting': PurchaseReturnPostEffects.accountingJson(
          PurchaseReturnPostEffects.buildAccounting(
            returnId: returnId,
            organizationId: companyId,
            supplierId: supplierId,
            amounts: PurchaseReturnPostEffects.computeAmounts(
              lines: [
                {
                  'line_id': returnLineId,
                  'product_id': productId,
                  'quantity': 2,
                  'unit_cost': 25,
                  'line_total': 50,
                },
              ],
              discountAmount: 0,
              taxPercent: 0,
              headerTotal: 50,
            ),
            createdBy: userId,
          ),
        ),
      },
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
      where: 'entity_id = ? AND operation = ?',
      whereArgs: [returnId, 'post'],
    );
    return {
      'movements': movements.length,
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

  group('Purchase return post hardening', () {
    test('replay x10 does not duplicate effects or outbox', () async {
      final service = PurchaseReturnPostLocalService(
        databaseService: databaseService,
      );

      expect((await service.postDraft(returnId: returnId)).ok, isTrue);

      for (var i = 0; i < 10; i++) {
        final replay = await service.postDraft(returnId: returnId);
        expect(replay.ok, isTrue, reason: 'replay $i');
        expect(replay.idempotentReplay, isTrue, reason: 'replay $i');
      }

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);
      expect(counts['ledger'], 2);
      expect(counts['outbox'], 1);
    });

    test('concurrent postDraft calls produce single post effects', () async {
      final service = PurchaseReturnPostLocalService(
        databaseService: databaseService,
      );

      final results = await Future.wait([
        service.postDraft(returnId: returnId),
        service.postDraft(returnId: returnId),
        service.postDraft(returnId: returnId),
      ]);

      expect(results.where((r) => r.ok).length, 3);
      expect(results.where((r) => r.idempotentReplay).length, greaterThanOrEqualTo(2));

      final db = await databaseService.database;
      final returnDoc = await db.query(
        'purchaseReturns',
        where: 'id = ?',
        whereArgs: [returnId],
        limit: 1,
      );
      expect(returnDoc.first['returnStatus'], 'posted');

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);
      expect(counts['ledger'], 2);
      expect(counts['outbox'], 1);
    });

    test('transaction_version mismatch is rejected', () async {
      final db = await databaseService.database;
      final aggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': returnId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'purchase_return',
          'status': 'draft',
          'transaction_version': 5,
          'row_version': 1,
          'original_invoice_id': originalInvoiceId,
          'supplier_id': supplierId,
          'total': 50,
          'created_by_user_id': userId,
        },
        lines: [
          {
            'line_id': returnLineId,
            'product_id': productId,
            'quantity': 2,
            'unit_cost': 25,
          },
        ],
      );

      late PostingResult result;
      await db.transaction((txn) async {
        result = await PurchaseReturnPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: PurchaseReturnSyncConstants.entityType,
          ),
        );
      });

      expect(result.ok, isFalse);
      expect(result.failureCode, 'transaction_version_mismatch');
    });

    test('post on already posted return with stale version fails', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        await PurchaseReturnPostingPipeline.create().run(
          PostingContext(
            aggregate: draftAggregate(),
            txn: txn,
            entityType: PurchaseReturnSyncConstants.entityType,
          ),
        );
      });

      final staleAggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': returnId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'purchase_return',
          'status': 'posted',
          'transaction_version': 2,
          'row_version': 3,
          'original_invoice_id': originalInvoiceId,
          'supplier_id': supplierId,
          'total': 50,
          'created_by_user_id': userId,
        },
        lines: draftAggregate().lines.map((l) => l.toJson()).toList(),
      );

      late PostingResult result;
      await db.transaction((txn) async {
        result = await PurchaseReturnPostingPipeline.create().run(
          PostingContext(
            aggregate: staleAggregate,
            txn: txn,
            entityType: PurchaseReturnSyncConstants.entityType,
          ),
        );
      });

      expect(result.ok, isFalse);
      expect(result.failureCode, 'already_posted');
    });

    test('device B scenario — post after already posted skips duplicate outbox',
        () async {
      final service = PurchaseReturnPostLocalService(
        databaseService: databaseService,
      );
      expect((await service.postDraft(returnId: returnId)).ok, isTrue);

      final replay = await service.postDraft(returnId: returnId);
      expect(replay.ok, isTrue);
      expect(replay.idempotentReplay, isTrue);

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);
      expect(counts['outbox'], 1);
    });

    test('inventory stage failure rolls back all effects', () async {
      final db = await databaseService.database;
      final pipeline = PostingPipeline(
        stages: [
          PurchaseReturnValidationPostingStage(),
          PurchaseReturnInventoryPostingStage(),
          _FailingPostingStage('accounting'),
          PurchaseReturnIntegrityPostingStage(),
          PurchaseReturnFinalizePostingStage(),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: draftAggregate(),
              txn: txn,
              entityType: PurchaseReturnSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'accounting');
      }

      final counts = await readEffectCounts();
      expect(counts['movements'], 0);
      expect(counts['ledger'], 0);

      final returnDoc = await db.query(
        'purchaseReturns',
        where: 'id = ?',
        whereArgs: [returnId],
        limit: 1,
      );
      expect(returnDoc.first['returnStatus'], 'draft');
    });

    test('accounting stage failure rolls back inventory', () async {
      final db = await databaseService.database;
      final pipeline = PostingPipeline(
        stages: [
          PurchaseReturnValidationPostingStage(),
          PurchaseReturnInventoryPostingStage(),
          _FailingPostingStage('accounting'),
          PurchaseReturnIntegrityPostingStage(),
          PurchaseReturnFinalizePostingStage(),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: draftAggregate(),
              txn: txn,
              entityType: PurchaseReturnSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'accounting');
      }

      final counts = await readEffectCounts();
      expect(counts['movements'], 0);
      expect(counts['ledger'], 0);
    });

    test('integrity stage failure rolls back inventory and accounting', () async {
      final db = await databaseService.database;
      final badAggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': returnId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'purchase_return',
          'status': 'draft',
          'transaction_version': 0,
          'row_version': 1,
          'original_invoice_id': originalInvoiceId,
          'supplier_id': supplierId,
          'total': 999,
          'line_subtotal': 50,
          'discount_amount': 0,
          'tax_percent': 0,
          'created_by_user_id': userId,
        },
        lines: draftAggregate().lines.map((l) => l.toJson()).toList(),
      );

      try {
        await db.transaction((txn) async {
          final result = await PurchaseReturnPostingPipeline.create().run(
            PostingContext(
              aggregate: badAggregate,
              txn: txn,
              entityType: PurchaseReturnSyncConstants.entityType,
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
      expect(counts['movements'], 0);
      expect(counts['ledger'], 0);
    });

    test('crash recovery — replay pipeline after successful post is idempotent', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        await PurchaseReturnPostingPipeline.create().run(
          PostingContext(
            aggregate: draftAggregate(),
            txn: txn,
            entityType: PurchaseReturnSyncConstants.entityType,
          ),
        );
      });

      for (var i = 0; i < 3; i++) {
        await db.transaction((txn) async {
          final replay = await PurchaseReturnPostingPipeline.create().run(
            PostingContext(
              aggregate: postedAggregateForReplay(),
              txn: txn,
              entityType: PurchaseReturnSyncConstants.entityType,
            ),
          );
          expect(replay.ok, isTrue);
          expect(replay.idempotentReplay, isTrue);
        });
      }

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);
      expect(counts['ledger'], 2);

      final movementId = PurchaseReturnPostIds.stockMovementId(returnId, returnLineId);
      final movements = await db.query(
        'stockMovements',
        where: 'id = ?',
        whereArgs: [movementId],
      );
      expect(movements.length, 1);
    });

    test('finalize posting_conflict rolls back all effects', () async {
      final db = await databaseService.database;
      final pipeline = PostingPipeline(
        stages: [
          PurchaseReturnValidationPostingStage(),
          PurchaseReturnInventoryPostingStage(),
          PurchaseReturnAccountingPostingStage(),
          PurchaseReturnIntegrityPostingStage(),
          _FailingPostingStage('finalize', code: 'posting_conflict'),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: draftAggregate(),
              txn: txn,
              entityType: PurchaseReturnSyncConstants.entityType,
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
      expect(counts['movements'], 0);
      expect(counts['ledger'], 0);
    });

    test('stable outbox idempotency key prevents duplicate outbox rows', () async {
      final service = PurchaseReturnPostLocalService(
        databaseService: databaseService,
      );
      expect((await service.postDraft(returnId: returnId)).ok, isTrue);

      final db = await databaseService.database;
      final keys = await db.query(
        'sync_outbox',
        columns: const ['idempotency_key'],
        where: 'entity_id = ?',
        whereArgs: [returnId],
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
          entityType: PurchaseReturnSyncConstants.entityType,
        );
        await PurchaseReturnValidationPostingStage().run(context);
        await PurchaseReturnInventoryPostingStage().run(context);
        await PurchaseReturnAccountingPostingStage().run(context);

        final accounting = context.stageData['accounting'];
        if (accounting is List<PurchaseReturnAccountingEffect> &&
            accounting.isNotEmpty) {
          context.stageData['accounting'] = [
            accounting.first,
          ];
        }

        final result = await PurchaseReturnIntegrityPostingStage().run(context);
        expect(result.isFailure, isTrue);
        expect(result.code, 'posting_integrity_violation');
      });
    });
  });
}
