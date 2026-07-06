import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/models/entities.dart';
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
import 'package:mizapos_mobile/services/cloud/sync/products_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/services/device_binding.dart';
import 'package:mizapos_mobile/utils/app_data_paths.dart';

import 'package:mizapos_mobile/services/database_runtime_profile.dart';

import 'isolated_test_database.dart';
import 'sync_integration_test_helpers.dart';

/// A → add product → push → B → pull → product visible.
///
/// Requires backend on 127.0.0.1:8787 + PostgreSQL.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';

  late DatabaseService databaseService;
  late CloudSecureStoragePlaceholder storage;
  late ProductsSyncRepository syncRepository;
  late ProductsPushWorker pushWorker;
  late ProductsPullWorker pullWorker;

  setUpAll(() async {
    await setUpIsolatedTestDatabase(
      profile: DatabaseRuntimeProfile.integrationTest,
    );
    await File(appDataFilePath('.mizapos_device_id'))
        .writeAsString(installationId);
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    await prepareSyncIntegrationTest(databaseService: databaseService);
    final db = await databaseService.database;
    await db.delete('products', where: 'id = ?', whereArgs: [productId]);
    await db.delete(
      'sync_outbox',
      where: 'entity_id = ?',
      whereArgs: [productId],
    );
    await db.delete(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [companyId, branchId, 'products'],
    );

    storage = CloudSecureStoragePlaceholder();
    final config = CloudConfig.development();
    final httpClient = const CloudHttpClientIo();
    final apiClient = CloudApiClient(
      httpClient: httpClient,
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
        password: 'MizaTest123!',
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
        installationId: installationId,
      ),
    );

    final deviceManager = DeviceManager(
      deviceService: DeviceService(
        repository: DeviceRepository(
          deviceApi: DeviceApi(apiClient: apiClient, config: config),
          storage: storage,
        ),
        storage: storage,
      ),
    );
    await deviceManager.register(companyId: companyId, branchId: branchId);

    syncRepository = ProductsSyncRepository(
      productsSyncApi: ProductsSyncApi(apiClient: apiClient, config: config),
      databaseService: databaseService,
    );
    pushWorker = ProductsPushWorker(repository: syncRepository);
    pullWorker = ProductsPullWorker(repository: syncRepository);
  });

  test('device A push then device B pull shows product', () async {
    final product = ProductEntity(
      id: productId,
      organizationId: companyId,
      branchId: branchId,
      name: 'حليب',
      salePrice: 6.5,
      costPrice: 5,
      stockQty: 48,
    );

    await syncRepository.upsertLocalProductFromEntity(product);
    await syncRepository.enqueueProductCreate(
      product: product,
      deviceId: seedDeviceId,
      installationId: installationId,
    );

    final push = await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
    expect(
      push.pushed >= 1 || push.response?.status == 'duplicate',
      isTrue,
      reason: 'push or idempotent duplicate',
    );

    final db = await databaseService.database;
    await db.delete('products', where: 'id = ?', whereArgs: [productId]);

    final pull = await pullWorker.run(
      companyId: companyId,
      branchId: branchId,
    );
    expect(pull.entryCount, greaterThanOrEqualTo(1));
    expect(pull.applied, greaterThanOrEqualTo(1));

    expect(await syncRepository.localProductExists(productId), isTrue);
  });
}
