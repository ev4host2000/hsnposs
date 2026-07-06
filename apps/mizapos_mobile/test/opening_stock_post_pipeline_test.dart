import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/sync/opening_stock_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/opening_stock_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_stage_result.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/opening_stock_post_effects.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/opening_stock_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/opening_stock_posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/stages/opening_stock_finalize_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/stages/opening_stock_integrity_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/stages/opening_stock_inventory_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/opening_stock/stages/opening_stock_validation_posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_stage.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/posting_transaction_guard.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';
import 'opening_stock_test_seed.dart';

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
  required String openingStockId,
  required String companyId,
  required String branchId,
  required String productId,
  required String userId,
  int transactionVersion = 0,
  int rowVersion = 1,
  double openingQuantity = 5,
  Map<String, dynamic>? metadataExtra,
}) {
  return MapTransactionAggregate.fromParts(
    header: {
      'id': openingStockId,
      'company_id': companyId,
      'branch_id': branchId,
      'document_type': 'opening_stock',
      'status': 'draft',
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'product_id': productId,
      'opening_quantity': openingQuantity,
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
  const openingStockId = 'b100e840-e29b-41d4-a716-446655440030';

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
      'openingStocks',
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
    await OpeningStockTestSeed.seedOpeningStockDraft(
      db,
      openingStockId: openingStockId,
      companyId: companyId,
      branchId: branchId,
      productId: productId,
      userId: userId,
    );
  });

  group('OpeningStockPostingPipeline', () {
    test('posts draft with inventory and finalize', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        final aggregate = _draftAggregate(
          openingStockId: openingStockId,
          companyId: companyId,
          branchId: branchId,
          productId: productId,
          userId: userId,
        );

        final result = await OpeningStockPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: OpeningStockSyncConstants.entityType,
          ),
        );

        expect(result.ok, isTrue);
      });

      final openingStockDoc = await db.query(
        'openingStocks',
        where: 'id = ?',
        whereArgs: [openingStockId],
        limit: 1,
      );
      expect(openingStockDoc.first['openingStatus'], 'posted');
      expect(openingStockDoc.first['transactionVersion'], 1);

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
    });

    test('local post service enqueues single post outbox event', () async {
      final service = OpeningStockPostLocalService(
        databaseService: databaseService,
      );
      final result = await service.postDraft(openingStockId: openingStockId);
      expect(result.ok, isTrue);

      final db = await databaseService.database;
      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [openingStockId],
      );
      expect(outbox.length, 1);
      expect(outbox.first['operation'], 'post');
    });

    test('idempotent replay does not duplicate effects', () async {
      final db = await databaseService.database;
      final aggregate = _draftAggregate(
        openingStockId: openingStockId,
        companyId: companyId,
        branchId: branchId,
        productId: productId,
        userId: userId,
      );

      await db.transaction((txn) async {
        final first = await OpeningStockPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: OpeningStockSyncConstants.entityType,
          ),
        );
        abortPostingTransactionIfFailed(first);
      });

      final postedAggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': openingStockId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'opening_stock',
          'status': 'posted',
          'transaction_version': 1,
          'row_version': 2,
          'product_id': productId,
          'opening_quantity': 5,
          'created_by_user_id': userId,
        },
        lines: const [],
        metadata: {
          'payload_schema_version': 1,
          'inventory': OpeningStockPostEffects.inventoryJson(
            OpeningStockPostEffects.buildInventory(
              openingStockId: openingStockId,
              productId: productId,
              openingQuantity: 5,
              createdBy: userId,
            ),
          ),
        },
      );

      await db.transaction((txn) async {
        final replay = await OpeningStockPostingPipeline.create().run(
          PostingContext(
            aggregate: postedAggregate,
            txn: txn,
            entityType: OpeningStockSyncConstants.entityType,
          ),
        );
        expect(replay.ok, isTrue);
        expect(replay.idempotentReplay, isTrue);
      });

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [openingStockId],
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
          'id': openingStockId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'opening_stock',
          'status': 'draft',
          'transaction_version': 0,
          'row_version': 1,
          'product_id': productId,
          'opening_quantity': 5,
          'created_by_user_id': userId,
        },
        lines: const [],
      );

      await db.transaction((txn) async {
        final result = await OpeningStockPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: OpeningStockSyncConstants.entityType,
          ),
        );
        expect(result.ok, isFalse);
        expect(result.failureCode, 'product_not_found');
      });
    });

    test('validation fails when opening quantity invalid', () async {
      final db = await databaseService.database;
      await db.update(
        'openingStocks',
        {'openingQuantity': 0.0},
        where: 'id = ?',
        whereArgs: [openingStockId],
      );

      try {
        await db.transaction((txn) async {
          final result = await OpeningStockPostingPipeline.create().run(
            PostingContext(
              aggregate: _draftAggregate(
                openingStockId: openingStockId,
                companyId: companyId,
                branchId: branchId,
                productId: productId,
                userId: userId,
                openingQuantity: 0,
              ),
              txn: txn,
              entityType: OpeningStockSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'validation');
        expect(e.result.failureCode, 'invalid_opening_quantity');
      }

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [openingStockId],
      );
      expect(movements, isEmpty);
    });

    test('inventory stage failure rolls back stock effects', () async {
      final db = await databaseService.database;
      final pipeline = PostingPipeline(
        stages: [
          OpeningStockValidationPostingStage(),
          OpeningStockInventoryPostingStage(),
          _FailingPostingStage('integrity'),
          OpeningStockFinalizePostingStage(),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: _draftAggregate(
                openingStockId: openingStockId,
                companyId: companyId,
                branchId: branchId,
                productId: productId,
                userId: userId,
              ),
              txn: txn,
              entityType: OpeningStockSyncConstants.entityType,
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
        whereArgs: [openingStockId],
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
          OpeningStockValidationPostingStage(),
          OpeningStockInventoryPostingStage(),
          _FailingPostingStage(
            'integrity',
            code: 'posting_integrity_violation',
          ),
          OpeningStockFinalizePostingStage(),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: _draftAggregate(
                openingStockId: openingStockId,
                companyId: companyId,
                branchId: branchId,
                productId: productId,
                userId: userId,
              ),
              txn: txn,
              entityType: OpeningStockSyncConstants.entityType,
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
        whereArgs: [openingStockId],
      );
      expect(movements, isEmpty);
    });

    test('finalize stage failure rolls back prior stages', () async {
      final db = await databaseService.database;
      final pipeline = PostingPipeline(
        stages: [
          OpeningStockValidationPostingStage(),
          OpeningStockInventoryPostingStage(),
          OpeningStockIntegrityPostingStage(),
          _FailingPostingStage('finalize', code: 'posting_conflict'),
        ],
      );

      try {
        await db.transaction((txn) async {
          final result = await pipeline.run(
            PostingContext(
              aggregate: _draftAggregate(
                openingStockId: openingStockId,
                companyId: companyId,
                branchId: branchId,
                productId: productId,
                userId: userId,
              ),
              txn: txn,
              entityType: OpeningStockSyncConstants.entityType,
            ),
          );
          abortPostingTransactionIfFailed(result);
        });
        fail('expected rollback');
      } on PostingPipelineAbortException catch (e) {
        expect(e.result.failedStageId, 'finalize');
        expect(e.result.failureCode, 'posting_conflict');
      }

      final openingStockDoc = await db.query(
        'openingStocks',
        where: 'id = ?',
        whereArgs: [openingStockId],
        limit: 1,
      );
      expect(openingStockDoc.first['openingStatus'], 'draft');

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [openingStockId],
      );
      expect(movements, isEmpty);
    });
  });
}
