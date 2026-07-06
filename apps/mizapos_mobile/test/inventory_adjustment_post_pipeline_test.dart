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

MapTransactionAggregate _draftAggregate({
  required String adjustmentId,
  required String companyId,
  required String branchId,
  required String productId,
  required String userId,
  int transactionVersion = 0,
  int rowVersion = 1,
  double quantityDelta = 5,
  Map<String, dynamic>? metadataExtra,
}) {
  return MapTransactionAggregate.fromParts(
    header: {
      'id': adjustmentId,
      'company_id': companyId,
      'branch_id': branchId,
      'document_type': 'inventory_adjustment',
      'status': 'draft',
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'product_id': productId,
      'quantity_delta': quantityDelta,
      'adjustment_reason': 'correction',
      'created_by_user_id': userId,
    },
    lines: const [],
    metadata: {
      'payload_schema_version': 1,
      if (metadataExtra != null) ...metadataExtra,
    },
  );
}

Future<void> _seedProduct(
  Database db, {
  required String productId,
  required String companyId,
  required String branchId,
  double stockQty = 10,
}) async {
  await db.delete('products', where: 'id = ?', whereArgs: [productId]);
  await db.insert('products', {
    'id': productId,
    'organizationId': companyId,
    'branchId': branchId,
    'name': 'Post Test Product',
    'salePrice': 25.0,
    'costPrice': 10.0,
    'stockQty': stockQty,
    'isHidden': 0,
    'isFrozen': 0,
    'isService': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const adjustmentId = 'b100e840-e29b-41d4-a716-446655440030';

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
      'inventoryAdjustments',
      'stockMovements',
      'sync_outbox',
    ]) {
      await db.delete(table);
    }
    await _seedProduct(
      db,
      productId: productId,
      companyId: companyId,
      branchId: branchId,
    );
    await AdjustmentTestSeed.seedInventoryAdjustmentDraft(
      db,
      adjustmentId: adjustmentId,
      companyId: companyId,
      branchId: branchId,
      productId: productId,
      userId: userId,
    );
  });

  group('InventoryAdjustmentPostingPipeline', () {
    test('posts draft with inventory and finalize', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        final aggregate = _draftAggregate(
          adjustmentId: adjustmentId,
          companyId: companyId,
          branchId: branchId,
          productId: productId,
          userId: userId,
        );

        final result = await InventoryAdjustmentPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: InventoryAdjustmentSyncConstants.entityType,
          ),
        );

        expect(result.ok, isTrue);
      });

      final adjustmentDoc = await db.query(
        'inventoryAdjustments',
        where: 'id = ?',
        whereArgs: [adjustmentId],
        limit: 1,
      );
      expect(adjustmentDoc.first['adjustmentStatus'], 'posted');
      expect(adjustmentDoc.first['transactionVersion'], 1);

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
    });

    test('local post service enqueues single post outbox event', () async {
      final service = InventoryAdjustmentPostLocalService(
        databaseService: databaseService,
      );
      final result = await service.postDraft(adjustmentId: adjustmentId);
      expect(result.ok, isTrue);

      final db = await databaseService.database;
      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [adjustmentId],
      );
      expect(outbox.length, 1);
      expect(outbox.first['operation'], 'post');
    });

    test('idempotent replay does not duplicate effects', () async {
      final db = await databaseService.database;
      final aggregate = _draftAggregate(
        adjustmentId: adjustmentId,
        companyId: companyId,
        branchId: branchId,
        productId: productId,
        userId: userId,
      );

      await db.transaction((txn) async {
        final first = await InventoryAdjustmentPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: InventoryAdjustmentSyncConstants.entityType,
          ),
        );
        abortPostingTransactionIfFailed(first);
      });

      final postedAggregate = MapTransactionAggregate.fromParts(
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

      await db.transaction((txn) async {
        final replay = await InventoryAdjustmentPostingPipeline.create().run(
          PostingContext(
            aggregate: postedAggregate,
            txn: txn,
            entityType: InventoryAdjustmentSyncConstants.entityType,
          ),
        );
        expect(replay.ok, isTrue);
        expect(replay.idempotentReplay, isTrue);
      });

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [adjustmentId],
      );
      expect(movements.length, 1);

      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect(product.first['stockQty'], 15.0);
    });

    test('validation fails when product missing', () async {
      final db = await databaseService.database;
      await db.delete('products', where: 'id = ?', whereArgs: [productId]);

      final aggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': adjustmentId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'inventory_adjustment',
          'status': 'draft',
          'transaction_version': 0,
          'row_version': 1,
          'product_id': productId,
          'quantity_delta': 5,
          'adjustment_reason': 'correction',
          'created_by_user_id': userId,
        },
        lines: const [],
      );

      await db.transaction((txn) async {
        final result = await InventoryAdjustmentPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: InventoryAdjustmentSyncConstants.entityType,
          ),
        );
        expect(result.ok, isFalse);
        expect(result.failureCode, 'product_not_found');
      });
    });

    test('inventory stage failure aborts pipeline', () async {
      final db = await databaseService.database;
      await db.update(
        'products',
        {'stockQty': 1.0},
        where: 'id = ?',
        whereArgs: [productId],
      );
      await db.update(
        'inventoryAdjustments',
        {'quantityDelta': -5.0},
        where: 'id = ?',
        whereArgs: [adjustmentId],
      );

      try {
        await db.transaction((txn) async {
          final result = await InventoryAdjustmentPostingPipeline.create().run(
            PostingContext(
              aggregate: _draftAggregate(
                adjustmentId: adjustmentId,
                companyId: companyId,
                branchId: branchId,
                productId: productId,
                userId: userId,
                quantityDelta: -5,
              ),
              txn: txn,
              entityType: InventoryAdjustmentSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'inventory');
        expect(e.result.failureCode, 'insufficient_stock');
      }

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [adjustmentId],
      );
      expect(movements, isEmpty);
    });

    test('inventory stage failure rolls back stock effects', () async {
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
              aggregate: _draftAggregate(
                adjustmentId: adjustmentId,
                companyId: companyId,
                branchId: branchId,
                productId: productId,
                userId: userId,
              ),
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

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [adjustmentId],
      );
      expect(movements, isEmpty);
      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect(product.first['stockQty'], 10.0);
    });

    test('integrity stage failure rolls back effects', () async {
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
              aggregate: _draftAggregate(
                adjustmentId: adjustmentId,
                companyId: companyId,
                branchId: branchId,
                productId: productId,
                userId: userId,
              ),
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

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [adjustmentId],
      );
      expect(movements, isEmpty);
    });

    test('finalize stage failure rolls back prior stages', () async {
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
              aggregate: _draftAggregate(
                adjustmentId: adjustmentId,
                companyId: companyId,
                branchId: branchId,
                productId: productId,
                userId: userId,
              ),
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

      final adjustmentDoc = await db.query(
        'inventoryAdjustments',
        where: 'id = ?',
        whereArgs: [adjustmentId],
        limit: 1,
      );
      expect(adjustmentDoc.first['adjustmentStatus'], 'draft');

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [adjustmentId],
      );
      expect(movements, isEmpty);
    });
  });
}
