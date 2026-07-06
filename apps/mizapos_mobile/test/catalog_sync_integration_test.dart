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
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/utils/app_data_paths.dart';

import 'package:mizapos_mobile/services/database_runtime_profile.dart';

import 'isolated_test_database.dart';
import 'sync_integration_test_helpers.dart';

/// Full catalog sync: categories, units, taxes, price lists, products.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const categoryId = 'b100e840-e29b-41d4-a716-446655440030';
  const unitId = 'b200e840-e29b-41d4-a716-446655440031';
  const taxId = 'b300e840-e29b-41d4-a716-446655440032';
  const priceListId = 'b400e840-e29b-41d4-a716-446655440033';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';

  late DatabaseService databaseService;
  late CloudSecureStoragePlaceholder storage;
  late ProductsSyncRepository productsRepository;
  late CatalogSyncRegistry catalogRegistry;
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
    for (final table in [
      'products',
      'product_categories',
      'product_units',
      'taxes',
      'price_lists',
      'price_list_items',
      'sync_outbox',
      'sync_meta',
    ]) {
      await db.delete(table);
    }

    storage = CloudSecureStoragePlaceholder();
    CatalogSyncOutboxWriter.bindStorage(storage);
    final config = CloudConfig.development();
    const httpClient = CloudHttpClientIo();
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

    catalogRegistry = CatalogSyncRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    productsRepository = ProductsSyncRepository(
      productsSyncApi: ProductsSyncApi(apiClient: apiClient, config: config),
      databaseService: databaseService,
    );
    pushWorker = ProductsPushWorker(
      repository: productsRepository,
      catalogRegistry: catalogRegistry,
    );
    pullWorker = ProductsPullWorker(
      repository: productsRepository,
      catalogRegistry: catalogRegistry,
    );
  });

  test('device A push full catalog then device B pull receives all entities', () async {
    final db = await databaseService.database;
    final now = DateTime.now().toIso8601String();

    await db.insert('product_categories', {
      'id': categoryId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Dairy',
      'sortOrder': 1,
      'createdAt': now,
    });
    await catalogRegistry.productCategories.enqueue(
      operation: 'create',
      entityId: categoryId,
      organizationId: companyId,
      branchId: branchId,
      payload: namedEntityCloudPayload(
        id: categoryId,
        organizationId: companyId,
        branchId: branchId,
        name: 'Dairy',
        sortOrder: 1,
      ),
    );

    await db.insert('product_units', {
      'id': unitId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'kg',
      'createdAt': now,
    });
    await catalogRegistry.productUnits.enqueue(
      operation: 'create',
      entityId: unitId,
      organizationId: companyId,
      branchId: branchId,
      payload: namedEntityCloudPayload(
        id: unitId,
        organizationId: companyId,
        branchId: branchId,
        name: 'kg',
      ),
    );

    await db.insert('taxes', {
      'id': taxId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'VAT',
      'percent': 15,
      'isDefault': 1,
      'sortOrder': 1,
      'createdAt': now,
    });
    await catalogRegistry.taxes.enqueue(
      operation: 'create',
      entityId: taxId,
      organizationId: companyId,
      branchId: branchId,
      payload: taxEntityCloudPayload(
        id: taxId,
        organizationId: companyId,
        branchId: branchId,
        name: 'VAT',
        percent: 15,
        isDefault: true,
      ),
    );

    await db.insert('price_lists', {
      'id': priceListId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Retail',
      'isDefault': 1,
      'sortOrder': 1,
      'createdAt': now,
    });
    await catalogRegistry.priceLists.enqueue(
      operation: 'create',
      entityId: priceListId,
      organizationId: companyId,
      branchId: branchId,
      payload: priceListEntityCloudPayload(
        id: priceListId,
        organizationId: companyId,
        branchId: branchId,
        name: 'Retail',
        isDefault: true,
        items: [
          {'product_id': productId, 'sale_price': 7.5},
        ],
      ),
    );

    final product = ProductEntity(
      id: productId,
      organizationId: companyId,
      branchId: branchId,
      name: 'Milk',
      salePrice: 6.5,
      costPrice: 5,
      stockQty: 48,
      categoryId: categoryId,
      unitName: 'kg',
    );
    await productsRepository.upsertLocalProductFromEntity(product);
    await productsRepository.enqueueProductCreate(
      product: product,
      deviceId: seedDeviceId,
      installationId: installationId,
    );

    final push = await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
    expect(push.pushed, greaterThanOrEqualTo(1));

    await db.delete('products');
    await db.delete('product_categories');
    await db.delete('product_units');
    await db.delete('taxes');
    await db.delete('price_lists');
    await db.delete('price_list_items');
    for (final scope in CatalogSyncConstants.catalogPullScopes) {
      await db.delete(
        'sync_meta',
        where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
        whereArgs: [companyId, branchId, scope],
      );
    }

    final pull = await pullWorker.run(
      companyId: companyId,
      branchId: branchId,
    );
    expect(pull.applied, greaterThanOrEqualTo(4));

    expect(await catalogRegistry.productCategories.localRowExists('product_categories', categoryId), isTrue);
    expect(await catalogRegistry.productUnits.localRowExists('product_units', unitId), isTrue);
    expect(await catalogRegistry.taxes.localRowExists('taxes', taxId), isTrue);
    expect(await catalogRegistry.priceLists.localRowExists('price_lists', priceListId), isTrue);
    expect(await productsRepository.localProductExists(productId), isTrue);
  });
}
