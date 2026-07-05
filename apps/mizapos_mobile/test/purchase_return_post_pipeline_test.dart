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

MapTransactionAggregate _draftAggregate({
  required String returnId,
  required String originalInvoiceId,
  required String companyId,
  required String branchId,
  required String supplierId,
  required String userId,
  required String lineId,
  required String productId,
  int transactionVersion = 0,
  int rowVersion = 1,
  double total = 50,
}) {
  return MapTransactionAggregate.fromParts(
    header: {
      'id': returnId,
      'company_id': companyId,
      'branch_id': branchId,
      'document_type': 'purchase_return',
      'status': 'draft',
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'original_invoice_id': originalInvoiceId,
      'supplier_id': supplierId,
      'total': total,
      'line_subtotal': total,
      'tax_percent': 0,
      'discount_amount': 0,
      'created_by_user_id': userId,
    },
    lines: [
      {
        'line_id': lineId,
        'product_id': productId,
        'quantity': 2,
        'unit_cost': total / 2,
        'line_total': total,
      },
    ],
  );
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
      'name': 'Post Test Supplier',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('products', {
      'id': productId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Post Product',
      'salePrice': 25.0,
      'costPrice': 10.0,
      'stockQty': 102.0,
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
    );
  });

  group('PurchaseReturnPostingPipeline', () {
    test('posts draft with inventory, accounting, and finalize', () async {
      final db = await databaseService.database;
      await db.transaction((txn) async {
        final aggregate = _draftAggregate(
          returnId: returnId,
          originalInvoiceId: originalInvoiceId,
          companyId: companyId,
          branchId: branchId,
          supplierId: supplierId,
          userId: userId,
          lineId: returnLineId,
          productId: productId,
        );

        final result = await PurchaseReturnPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: PurchaseReturnSyncConstants.entityType,
          ),
        );

        expect(result.ok, isTrue);
      });

      final returnDoc = await db.query(
        'purchaseReturns',
        where: 'id = ?',
        whereArgs: [returnId],
        limit: 1,
      );
      expect(returnDoc.first['returnStatus'], 'posted');
      expect(returnDoc.first['transactionVersion'], 1);

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [returnId],
      );
      expect(movements.length, 1);
      expect(movements.first['movementType'], 'out');
      expect(
        movements.first['id'],
        PurchaseReturnPostIds.stockMovementId(returnId, returnLineId),
      );

      final ledger = await db.query(
        'partnerLedger',
        where: 'referenceId = ?',
        whereArgs: [returnId],
      );
      expect(ledger.length, 2);

      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect(product.first['stockQty'], 100.0);
    });

    test('local post service enqueues single post outbox event', () async {
      final service = PurchaseReturnPostLocalService(
        databaseService: databaseService,
      );
      final result = await service.postDraft(returnId: returnId);
      expect(result.ok, isTrue);

      final db = await databaseService.database;
      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: [returnId],
      );
      expect(outbox.length, 1);
      expect(outbox.first['operation'], 'post');
    });

    test('idempotent replay does not duplicate effects', () async {
      final db = await databaseService.database;
      final aggregate = _draftAggregate(
        returnId: returnId,
        originalInvoiceId: originalInvoiceId,
        companyId: companyId,
        branchId: branchId,
        supplierId: supplierId,
        userId: userId,
        lineId: returnLineId,
        productId: productId,
      );

      await db.transaction((txn) async {
        final first = await PurchaseReturnPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: PurchaseReturnSyncConstants.entityType,
          ),
        );
        abortPostingTransactionIfFailed(first);
      });

      final postedAggregate = MapTransactionAggregate.fromParts(
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
          'discount_amount': 0,
          'tax_percent': 0,
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
        metadata: {
          'payload_schema_version': 1,
          'inventory': PurchaseReturnPostEffects.inventoryJson(
            PurchaseReturnPostEffects.buildInventory(
              returnId: returnId,
              organizationId: companyId,
              branchId: branchId,
              lines: [
                {
                  'line_id': returnLineId,
                  'product_id': productId,
                  'quantity': 2,
                },
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

      await db.transaction((txn) async {
        final replay = await PurchaseReturnPostingPipeline.create().run(
          PostingContext(
            aggregate: postedAggregate,
            txn: txn,
            entityType: PurchaseReturnSyncConstants.entityType,
          ),
        );
        expect(replay.ok, isTrue);
        expect(replay.idempotentReplay, isTrue);
      });

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [returnId],
      );
      expect(movements.length, 1);

      final ledger = await db.query(
        'partnerLedger',
        where: 'referenceId = ?',
        whereArgs: [returnId],
      );
      expect(ledger.length, 2);

      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect(product.first['stockQty'], 100.0);
    });

    test('validation fails when supplier missing', () async {
      final db = await databaseService.database;
      await db.update(
        'purchaseReturns',
        {'supplierId': null},
        where: 'id = ?',
        whereArgs: [returnId],
      );

      final aggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': returnId,
          'company_id': companyId,
          'branch_id': branchId,
          'document_type': 'purchase_return',
          'status': 'draft',
          'transaction_version': 0,
          'row_version': 1,
          'original_invoice_id': originalInvoiceId,
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

      await db.transaction((txn) async {
        final result = await PurchaseReturnPostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: PurchaseReturnSyncConstants.entityType,
          ),
        );
        expect(result.ok, isFalse);
        expect(result.failureCode, 'missing_supplier');
      });
    });

    test('inventory stage failure aborts pipeline', () async {
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
              aggregate: _draftAggregate(
                returnId: returnId,
                originalInvoiceId: originalInvoiceId,
                companyId: companyId,
                branchId: branchId,
                supplierId: supplierId,
                userId: userId,
                lineId: returnLineId,
                productId: productId,
              ),
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

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [returnId],
      );
      expect(movements, isEmpty);
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
              aggregate: _draftAggregate(
                returnId: returnId,
                originalInvoiceId: originalInvoiceId,
                companyId: companyId,
                branchId: branchId,
                supplierId: supplierId,
                userId: userId,
                lineId: returnLineId,
                productId: productId,
              ),
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

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [returnId],
      );
      expect(movements, isEmpty);
      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      expect(product.first['stockQty'], 102.0);
    });

    test('integrity stage failure rolls back effects', () async {
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

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [returnId],
      );
      expect(movements, isEmpty);
    });

    test('finalize stage failure rolls back prior stages', () async {
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
              aggregate: _draftAggregate(
                returnId: returnId,
                originalInvoiceId: originalInvoiceId,
                companyId: companyId,
                branchId: branchId,
                supplierId: supplierId,
                userId: userId,
                lineId: returnLineId,
                productId: productId,
              ),
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

      final returnDoc = await db.query(
        'purchaseReturns',
        where: 'id = ?',
        whereArgs: [returnId],
        limit: 1,
      );
      expect(returnDoc.first['returnStatus'], 'draft');

      final movements = await db.query(
        'stockMovements',
        where: 'referenceId = ?',
        whereArgs: [returnId],
      );
      expect(movements, isEmpty);
    });
  });
}
