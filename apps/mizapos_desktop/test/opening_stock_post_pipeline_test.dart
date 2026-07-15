import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_desktop/services/cloud/sync/opening_stock_post_local_service.dart';
import 'package:mizapos_desktop/services/cloud/sync/opening_stock_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/opening_stock_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/opening_stock_post_ids.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/opening_stock/opening_stock_posting_pipeline.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_opening_stock_sync_service.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/database_runtime_profile.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/utils/app_data_paths.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

Directory? _testDir;

Future<void> setUpIsolatedDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _testDir = await Directory.systemTemp.createTemp('mizapos_desktop_test_');
  DatabaseRuntimeConfig.configureForTesting(
    profile: DatabaseRuntimeProfile.integrationTest,
    directory: _testDir!.path,
  );
  await initAppDataDirectory();
  await DatabaseService().database;
}

Future<void> tearDownIsolatedDb() async {
  await DatabaseService().closeDatabase();
  DatabaseRuntimeConfig.resetForTesting();
  if (_testDir != null) {
    try {
      await _testDir!.delete(recursive: true);
    } on Object {
      /* ignore */
    }
    _testDir = null;
  }
}

Future<void> seedProduct(
  DatabaseService dbService, {
  required String productId,
  required String orgId,
  required String branchId,
  String name = 'Test product',
}) async {
  final db = await dbService.database;
  await db.insert('products', {
    'id': productId,
    'organizationId': orgId,
    'branchId': branchId,
    'name': name,
    'salePrice': 10.0,
    'costPrice': 5.0,
    'stockQty': 0.0,
    'sortOrder': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orgId = 'org-test';
  const branchId = 'branch-test';
  const userId = 'user-test';
  const productId = 'product-test';
  const openingStockId = 'opening-test';

  late DatabaseService databaseService;

  setUp(() async {
    await setUpIsolatedDb();
    databaseService = DatabaseService();
    await seedProduct(
      databaseService,
      productId: productId,
      orgId: orgId,
      branchId: branchId,
    );
    final db = await databaseService.database;
    await db.insert('openingStocks', {
      'id': openingStockId,
      'organizationId': orgId,
      'branchId': branchId,
      'productId': productId,
      'openingQuantity': 5.0,
      'openingDate': DateTime.now().toIso8601String(),
      'openingStatus': 'draft',
      'createdBy': userId,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
  });

  tearDown(() async {
    await tearDownIsolatedDb();
  });

  test('opening stock pipeline posts draft successfully', () async {
    final aggregate = MapTransactionAggregate.fromParts(
      header: {
        'id': openingStockId,
        'company_id': orgId,
        'branch_id': branchId,
        'document_type': 'opening_stock',
        'status': 'draft',
        'transaction_version': 0,
        'row_version': 1,
        'product_id': productId,
        'opening_quantity': 5.0,
        'created_by_user_id': userId,
      },
      lines: const [],
      metadata: {'payload_schema_version': 1},
    );

    final db = await databaseService.database;
    PostingContext? ctx;
    await db.transaction((txn) async {
      ctx = PostingContext(
        aggregate: aggregate,
        txn: txn,
        entityType: OpeningStockSyncConstants.entityType,
      );
      final result = await OpeningStockPostingPipeline.create().run(ctx!);
      expect(result.ok, true, reason: result.failureMessage ?? result.failureCode);
    });

    final stock = await db.query('products', where: 'id = ?', whereArgs: [productId]);
    expect((stock.first['stockQty'] as num).toDouble(), 5.0);
  });

  test('createOpeningStockDraftAndPost end-to-end', () async {
    const uuid = Uuid();
    final newOpeningId = uuid.v4();
    final newProductId = uuid.v4();
    await seedProduct(
      databaseService,
      productId: newProductId,
      orgId: orgId,
      branchId: branchId,
      name: 'Product ${newProductId.substring(0, 8)}',
    );

    final result = await TransactionOpeningStockSyncService(
      databaseService: databaseService,
    ).createOpeningStockDraftAndPost(
      openingStockId: newOpeningId,
      organizationId: orgId,
      branchId: branchId,
      userId: userId,
      productId: newProductId,
      openingQuantity: 3.0,
    );

    expect(result.ok, true, reason: result.failureMessage ?? result.failureCode);
    final db = await databaseService.database;
    final stock = await db.query('products', where: 'id = ?', whereArgs: [newProductId]);
    expect((stock.first['stockQty'] as num).toDouble(), 3.0);
  });
}
