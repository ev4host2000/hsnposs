import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_effects.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/inventory_adjustment/stages/inventory_adjustment_finalize_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/inventory_adjustment/stages/inventory_adjustment_integrity_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/inventory_adjustment/stages/inventory_adjustment_inventory_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/inventory_adjustment/stages/inventory_adjustment_validation_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'adjustment_test_seed.dart';
import 'isolated_test_database.dart';

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
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const adjustmentId = 'b100e840-e29b-41d4-a716-446655440030';

  late DatabaseService databaseService;

  Future<void> seedDraft({double quantityDelta = 5}) async {
    final db = await databaseService.database;
    for (final table in [
      'inventoryAdjustments',
      'stockMovements',
      'sync_outbox',
    ]) {
      await db.delete(table);
    }
    await db.delete('products', where: 'id = ?', whereArgs: [productId]);

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
    await AdjustmentTestSeed.seedInventoryAdjustmentDraft(
      db,
      adjustmentId: adjustmentId,
      companyId: companyId,
      branchId: branchId,
      productId: productId,
      userId: userId,
      quantityDelta: quantityDelta,
    );
  }

  MapTransactionAggregate draftAggregate({int transactionVersion = 0}) {
    return MapTransactionAggregate.fromParts(
      header: {
        'id': adjustmentId,
        'company_id': companyId,
        'branch_id': branchId,
        'document_type': 'inventory_adjustment',
        'status': 'draft',
        'transaction_version': transactionVersion,
        'row_version': 1,
        'product_id': productId,
        'quantity_delta': 5,
        'adjustment_reason': 'correction',
        'created_by_user_id': userId,
      },
      lines: const [],
    );
  }

  MapTransactionAggregate postedAggregateForReplay() {
    return MapTransactionAggregate.fromParts(
      header: {
        'id': adjustmentId,
        'company_id': companyId,
        'branch_id': branchId,
        'document_type': 'inventory_adjustment',
        'status': 'posted',
        'transaction_version': 1,
        'row_version': 2,
        'product_id': productId,
        'quantity_delta': 5,
        'adjustment_reason': 'correction',
        'created_by_user_id': userId,
      },
      lines: const [],
      metadata: {
        'payload_schema_version': 1,
        'inventory': InventoryAdjustmentPostEffects.inventoryJson(
          InventoryAdjustmentPostEffects.buildInventory(
            adjustmentId: adjustmentId,
            productId: productId,
            quantityDelta: 5,
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
      whereArgs: [adjustmentId],
    );
    final outbox = await db.query(
      'sync_outbox',
      where: 'entity_id = ? AND operation = ?',
      whereArgs: [adjustmentId, 'post'],
    );
    return {
      'movements': movements.length,
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

  group('Inventory adjustment post hardening', () {
    test('replay x10 does not duplicate effects or outbox', () async {
      final service = InventoryAdjustmentPostLocalService(
        databaseService: databaseService,
      );

      expect((await service.postDraft(adjustmentId: adjustmentId)).ok, isTrue);

      for (var i = 0; i < 10; i++) {
        final replay = await service.postDraft(adjustmentId: adjustmentId);
        expect(replay.ok, isTrue, reason: 'replay $i');
        expect(replay.idempotentReplay, isTrue, reason: 'replay $i');
      }

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);
      expect(counts['outbox'], 1);
    });

    test('concurrent postDraft calls produce single post effects', () async {
      final service = InventoryAdjustmentPostLocalService(
        databaseService: databaseService,
      );

      final results = await Future.wait([
        service.postDraft(adjustmentId: adjustmentId),
        service.postDraft(adjustmentId: adjustmentId),
        service.postDraft(adjustmentId: adjustmentId),
      ]);

      expect(results.where((r) => r.ok).length, 3);
      expect(
        results.where((r) => r.idempotentReplay).length,
        greaterThanOrEqualTo(2),
      );

      final db = await databaseService.database;
      final adjustmentDoc = await db.query(
        'inventoryAdjustments',
        where: 'id = ?',
        whereArgs: [adjustmentId],
        limit: 1,
      );
      expect(adjustmentDoc.first['adjustmentStatus'], 'posted');

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);
      expect(counts['outbox'], 1);
    });

    test('transaction_version mismatch is rejected', () async {
      final db = await databaseService.database;
      final aggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': adjustmentId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'inventory_adjustment',
          'status': 'draft',
          'transaction_version': 5,
          'row_version': 1,
          'product_id': productId,
          'quantity_delta': 5,
          'adjustment_reason': 'correction',
          'created_by_user_id': userId,
        },
        lines: const [],
      );

      late PostingResult result;
      await db.transaction((txn) async {
        result = await InventoryAdjustmentPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: InventoryAdjustmentSyncConstants.entityType,
          ),
        );
      });

      expect(result.ok, isFalse);
      expect(result.failureCode, 'transaction_version_mismatch');
    });

    test('post on already posted adjustment with stale version fails', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        await InventoryAdjustmentPostingPipeline.create().run(
          PostingContext(
            aggregate: draftAggregate(),
            txn: txn,
            entityType: InventoryAdjustmentSyncConstants.entityType,
          ),
        );
      });

      final staleAggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': adjustmentId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'inventory_adjustment',
          'status': 'posted',
          'transaction_version': 2,
          'row_version': 3,
          'product_id': productId,
          'quantity_delta': 5,
          'adjustment_reason': 'correction',
          'created_by_user_id': userId,
        },
        lines: const [],
      );

      late PostingResult result;
      await db.transaction((txn) async {
        result = await InventoryAdjustmentPostingPipeline.create().run(
          PostingContext(
            aggregate: staleAggregate,
            txn: txn,
            entityType: InventoryAdjustmentSyncConstants.entityType,
          ),
        );
      });

      expect(result.ok, isFalse);
      expect(result.failureCode, 'already_posted');
    });

    test('device B scenario — post after already posted skips duplicate outbox',
        () async {
      final service = InventoryAdjustmentPostLocalService(
        databaseService: databaseService,
      );
      expect((await service.postDraft(adjustmentId: adjustmentId)).ok, isTrue);

      final replay = await service.postDraft(adjustmentId: adjustmentId);
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
          InventoryAdjustmentValidationPostingStage(),
          InventoryAdjustmentInventoryPostingStage(),
          _FailingPostingStage('integrity'),
          InventoryAdjustmentFinalizePostingStage(),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: draftAggregate(),
              txn: txn,
              entityType: InventoryAdjustmentSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'integrity');
      }

      final counts = await readEffectCounts();
      expect(counts['movements'], 0);

      final adjustmentDoc = await db.query(
        'inventoryAdjustments',
        where: 'id = ?',
        whereArgs: [adjustmentId],
        limit: 1,
      );
      expect(adjustmentDoc.first['adjustmentStatus'], 'draft');
    });

    test('integrity stage failure rolls back inventory', () async {
      final db = await databaseService.database;
      final pipeline = PostingPipeline(
        stages: [
          InventoryAdjustmentValidationPostingStage(),
          InventoryAdjustmentInventoryPostingStage(),
          _FailingPostingStage(
            'integrity',
            code: 'posting_integrity_violation',
          ),
          InventoryAdjustmentFinalizePostingStage(),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: draftAggregate(),
              txn: txn,
              entityType: InventoryAdjustmentSyncConstants.entityType,
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
    });

    test('crash recovery — replay pipeline after successful post is idempotent', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        await InventoryAdjustmentPostingPipeline.create().run(
          PostingContext(
            aggregate: draftAggregate(),
            txn: txn,
            entityType: InventoryAdjustmentSyncConstants.entityType,
          ),
        );
      });

      for (var i = 0; i < 3; i++) {
        await db.transaction((txn) async {
          final replay = await InventoryAdjustmentPostingPipeline.create().run(
            PostingContext(
              aggregate: postedAggregateForReplay(),
              txn: txn,
              entityType: InventoryAdjustmentSyncConstants.entityType,
            ),
          );
          expect(replay.ok, isTrue);
          expect(replay.idempotentReplay, isTrue);
        });
      }

      final counts = await readEffectCounts();
      expect(counts['movements'], 1);

      final movementId =
          InventoryAdjustmentPostIds.stockMovementId(adjustmentId);
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
          InventoryAdjustmentValidationPostingStage(),
          InventoryAdjustmentInventoryPostingStage(),
          InventoryAdjustmentIntegrityPostingStage(),
          _FailingPostingStage('finalize', code: 'posting_conflict'),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: draftAggregate(),
              txn: txn,
              entityType: InventoryAdjustmentSyncConstants.entityType,
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
    });

    test('stable outbox idempotency key prevents duplicate outbox rows', () async {
      final service = InventoryAdjustmentPostLocalService(
        databaseService: databaseService,
      );
      expect((await service.postDraft(adjustmentId: adjustmentId)).ok, isTrue);

      final db = await databaseService.database;
      final keys = await db.query(
        'sync_outbox',
        columns: const ['idempotency_key'],
        where: 'entity_id = ?',
        whereArgs: [adjustmentId],
      );
      expect(keys.length, 1);
      expect(keys.first['idempotency_key'], contains(':post'));
    });

    test('integrity stage rejects unexpected accounting effects', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        final context = PostingContext(
          aggregate: draftAggregate(),
          txn: txn,
          entityType: InventoryAdjustmentSyncConstants.entityType,
        );
        await InventoryAdjustmentValidationPostingStage().run(context);
        await InventoryAdjustmentInventoryPostingStage().run(context);
        context.stageData['accounting'] = {'entry_id': 'should-not-exist'};

        final result = await InventoryAdjustmentIntegrityPostingStage().run(context);
        expect(result.isFailure, isTrue);
        expect(result.code, 'posting_integrity_violation');
      });
    });
  });
}
