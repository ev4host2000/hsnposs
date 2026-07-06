import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mizapos_mobile/models/entities.dart';
import 'package:mizapos_mobile/security/password_crypto.dart';
import 'package:mizapos_mobile/services/accounting_service.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_client_io.dart';
import 'package:mizapos_mobile/services/cloud/auth/auth_api.dart';
import 'package:mizapos_mobile/services/cloud/auth/auth_manager.dart';
import 'package:mizapos_mobile/services/cloud/auth/auth_repository.dart';
import 'package:mizapos_mobile/services/cloud/auth/auth_service.dart';
import 'package:mizapos_mobile/services/cloud/auth/requests/login_request.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/devices/device_api.dart';
import 'package:mizapos_mobile/services/cloud/devices/device_manager.dart';
import 'package:mizapos_mobile/services/cloud/devices/device_repository.dart';
import 'package:mizapos_mobile/services/cloud/devices/device_service.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/utils/app_data_paths.dart';

import 'isolated_test_database.dart';
import 'package:uuid/uuid.dart';

/// UI → AccountingService.addProduct → sync_outbox → push → pull.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const ownerPassword = 'MizaTest123!';

  late DatabaseService databaseService;
  late AccountingService accountingService;
  late CloudSecureStoragePlaceholder storage;
  late ProductsSyncRepository syncRepository;
  late ProductsPushWorker pushWorker;
  late ProductsPullWorker pullWorker;

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
    await File(appDataFilePath('.mizapos_device_id'))
        .writeAsString(installationId);
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    accountingService = AccountingService(databaseService);
    storage = CloudSecureStoragePlaceholder();
    ProductSyncOutboxWriter.bindStorage(storage);

    await _seedLocalTenant(databaseService, companyId, branchId, ownerPassword);

    final config = CloudConfig.development();
    final apiClient = CloudApiClient(
      httpClient: const CloudHttpClientIo(),
      config: config,
      storage: storage,
    );

    final authManager = AuthManager(
      authService: AuthService(
        repository: AuthRepository(
          authApi: AuthApi(apiClient: apiClient, config: config),
          storage: storage,
        ),
        config: config,
      ),
    );

    await authManager.login(
      const LoginRequest(
        username: 'owner@store.com',
        password: ownerPassword,
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
        installationId: installationId,
      ),
    );

    await DeviceManager(
      deviceService: DeviceService(
        repository: DeviceRepository(
          deviceApi: DeviceApi(apiClient: apiClient, config: config),
          storage: storage,
        ),
        storage: storage,
      ),
    ).register(companyId: companyId, branchId: branchId);

    syncRepository = ProductsSyncRepository(
      productsSyncApi: ProductsSyncApi(apiClient: apiClient, config: config),
      databaseService: databaseService,
    );
    pushWorker = ProductsPushWorker(repository: syncRepository);
    pullWorker = ProductsPullWorker(repository: syncRepository);

    final loggedIn = await accountingService.login(
      'owner@store.com',
      ownerPassword,
    );
    expect(loggedIn, isNotNull);
  });

  test('addProduct writes outbox then push/pull syncs product', () async {
    final productId = const Uuid().v4();
    final product = ProductEntity(
      id: productId,
      organizationId: companyId,
      branchId: branchId,
      name: 'منتج من الواجهة',
      salePrice: 12.5,
      costPrice: 9,
      stockQty: 20,
    );

    await accountingService.addProduct(product);

    final db = await databaseService.database;
    final outbox = await db.query(
      'sync_outbox',
      where: 'entity_id = ? AND sync_state = ?',
      whereArgs: [productId, 'pending'],
    );
    expect(outbox, isNotEmpty);
    expect(outbox.first['operation'], 'create');

    final push = await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
    expect(
      push.pushed >= 1 || push.response?.status == 'duplicate',
      isTrue,
    );

    await db.delete('products', where: 'id = ?', whereArgs: [productId]);

    final pull = await pullWorker.run(
      companyId: companyId,
      branchId: branchId,
    );
    expect(pull.applied, greaterThanOrEqualTo(1));

    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    );
    expect(rows, isNotEmpty);
    expect(rows.first['name'], 'منتج من الواجهة');
  });
}

Future<void> _seedLocalTenant(
  DatabaseService dbService,
  String organizationId,
  String branchId,
  String ownerPassword,
) async {
  final db = await dbService.database;
  final ownerId = '990e8400-e29b-41d4-a716-446655440004';

  await db.insert(
    'organizations',
    {
      'id': organizationId,
      'name': 'Demo Store',
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  await db.insert(
    'branches',
    {
      'id': branchId,
      'organizationId': organizationId,
      'name': 'Main Branch',
      'code': 'MAIN',
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  await db.insert(
    'users',
    {
      'id': ownerId,
      'organizationId': organizationId,
      'branchId': branchId,
      'fullName': 'Store Owner',
      'username': 'owner@store.com',
      'email': 'owner@store.com',
      'password': PasswordCrypto.hash(ownerPassword),
      'role': 'owner',
      'accountStatus': 'active',
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
