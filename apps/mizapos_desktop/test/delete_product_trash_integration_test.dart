import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_desktop/models/entities.dart';
import 'package:mizapos_desktop/security/password_crypto.dart';
import 'package:mizapos_desktop/services/accounting_service.dart';
import 'package:mizapos_desktop/services/database_runtime_profile.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/utils/app_data_paths.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

Directory? _testDir;

Future<void> setUpIsolatedDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _testDir = await Directory.systemTemp.createTemp('mizapos_desktop_del_');
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

Future<void> seedTenant(DatabaseService dbService) async {
  const orgId = 'org-del-test';
  const branchId = 'branch-del-test';
  const ownerId = 'owner-del-test';
  final db = await dbService.database;
  await db.insert(
    'organizations',
    {
      'id': orgId,
      'name': 'Test Org',
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  await db.insert(
    'branches',
    {
      'id': branchId,
      'organizationId': orgId,
      'name': 'Main',
      'code': 'MAIN',
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  await db.insert(
    'users',
    {
      'id': ownerId,
      'organizationId': orgId,
      'branchId': branchId,
      'fullName': 'Owner',
      'username': 'owner@test.com',
      'email': 'owner@test.com',
      'password': PasswordCrypto.hash('TestPass123!'),
      'role': 'owner',
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService databaseService;
  late AccountingService accountingService;

  setUp(() async {
    await setUpIsolatedDb();
    databaseService = DatabaseService();
    accountingService = AccountingService(databaseService);
    await seedTenant(databaseService);
    final session = await accountingService.login('owner@test.com', 'TestPass123!');
    expect(session, isNotNull);
  });

  tearDown(() async {
    await tearDownIsolatedDb();
  });

  test('deleteProduct moves favorite product to trash', () async {
    const uuid = Uuid();
    final productId = uuid.v4();
    final session = accountingService.session!;
    await accountingService.addProduct(
      ProductEntity(
        id: productId,
        organizationId: session.organizationId,
        branchId: session.branchId,
        name: 'Favorite item ${productId.substring(0, 6)}',
        salePrice: 5,
        costPrice: 2,
        stockQty: 0,
      ),
    );
    await accountingService.setProductFavorite(
      productId: productId,
      isFavorite: true,
    );

    await accountingService.deleteProduct(productId);

    final db = await databaseService.database;
    final active = await db.query('products', where: 'id = ?', whereArgs: [productId]);
    expect(active, isEmpty);
    final trashed = await db.query('product_trash', where: 'id = ?', whereArgs: [productId]);
    expect(trashed, isNotEmpty);
    expect(trashed.first['isFavorite'], 1);
  });
}
