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
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/utils/app_data_paths.dart';
import 'package:sqflite/sqflite.dart';

import 'package:mizapos_mobile/services/database_runtime_profile.dart';

import 'isolated_test_database.dart';
import 'sync_integration_test_helpers.dart';

/// Customers & suppliers cloud sync — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  const supplierId = 'c200e840-e29b-41d4-a716-446655440041';

  late DatabaseService databaseService;
  late CloudSecureStoragePlaceholder storage;
  late ProductsSyncRepository productsRepository;
  late PartnersSyncRegistry partnersRegistry;
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
      'customers',
      'suppliers',
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

    partnersRegistry = PartnersSyncRegistry.create(
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
      partnersRegistry: partnersRegistry,
    );
    pullWorker = ProductsPullWorker(
      repository: productsRepository,
      partnersRegistry: partnersRegistry,
    );
  });

  Future<void> enqueuePartner({
    required String entityType,
    required String operation,
    required String entityId,
    required Map<String, dynamic> payload,
  }) {
    return CatalogSyncOutboxWriter.record(
      entityType: entityType,
      operation: operation,
      entityId: entityId,
      organizationId: companyId,
      branchId: branchId,
      payload: payload,
      databaseService: databaseService,
      storage: storage,
    );
  }

  Future<Map<String, Object?>?> readCustomer() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> readSupplier() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [supplierId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  group('customer sync', () {
    test('device A add → device B pull', () async {
      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeCustomer,
        operation: 'create',
        entityId: customerId,
        payload: partnerEntityCloudPayload(
          id: customerId,
          organizationId: companyId,
          branchId: branchId,
          name: 'محل الأمل',
          partnerNumber: 'C-100',
          phone: '+970599111111',
          creditLimit: 5000,
        ),
      );

      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );

      final db = await databaseService.database;
      await db.delete('customers', where: 'id = ?', whereArgs: [customerId]);

      await pullWorker.run(companyId: companyId, branchId: branchId);

      final row = await readCustomer();
      expect(row, isNotNull);
      expect(row!['name'], 'محل الأمل');
      expect(row['customerNumber'], 'C-100');
    });

    test('update, delete, restore via pull', () async {
      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeCustomer,
        operation: 'create',
        entityId: customerId,
        payload: partnerEntityCloudPayload(
          id: customerId,
          organizationId: companyId,
          branchId: branchId,
          name: 'Old Name',
          creditLimit: 100,
        ),
      );
      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );
      final db = await databaseService.database;
      await db.delete('customers');
      await pullWorker.run(companyId: companyId, branchId: branchId);

      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeCustomer,
        operation: 'update',
        entityId: customerId,
        payload: partnerEntityCloudPayload(
          id: customerId,
          organizationId: companyId,
          branchId: branchId,
          name: 'New Name',
          creditLimit: 2500,
        ),
      );
      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );
      await db.delete('customers', where: 'id = ?', whereArgs: [customerId]);
      await pullWorker.run(companyId: companyId, branchId: branchId);
      expect((await readCustomer())?['name'], 'New Name');

      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeCustomer,
        operation: 'delete',
        entityId: customerId,
        payload: partnerEntityCloudPayload(
          id: customerId,
          organizationId: companyId,
          branchId: branchId,
          name: 'New Name',
          deleted: true,
        ),
      );
      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );
      await db.delete('customers', where: 'id = ?', whereArgs: [customerId]);
      await db.insert('customers', {
        'id': customerId,
        'organizationId': companyId,
        'branchId': branchId,
        'name': 'Stale',
        'creditLimit': 0,
        'createdAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await pullWorker.run(companyId: companyId, branchId: branchId);
      expect(await readCustomer(), isNull);

      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeCustomer,
        operation: 'update',
        entityId: customerId,
        payload: partnerEntityCloudPayload(
          id: customerId,
          organizationId: companyId,
          branchId: branchId,
          name: 'Restored Customer',
          creditLimit: 900,
        ),
      );
      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );
      await pullWorker.run(companyId: companyId, branchId: branchId);
      final restored = await readCustomer();
      expect(restored, isNotNull);
      expect(restored!['name'], 'Restored Customer');
    });
  });

  group('supplier sync', () {
    test('device A add → device B pull', () async {
      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeSupplier,
        operation: 'create',
        entityId: supplierId,
        payload: partnerEntityCloudPayload(
          id: supplierId,
          organizationId: companyId,
          branchId: branchId,
          name: 'مورد الحليب',
          partnerNumber: 'S-200',
        ),
      );
      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );

      final db = await databaseService.database;
      await db.delete('suppliers', where: 'id = ?', whereArgs: [supplierId]);
      await pullWorker.run(companyId: companyId, branchId: branchId);

      final row = await readSupplier();
      expect(row, isNotNull);
      expect(row!['name'], 'مورد الحليب');
    });

    test('update, delete, restore via pull', () async {
      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeSupplier,
        operation: 'create',
        entityId: supplierId,
        payload: partnerEntityCloudPayload(
          id: supplierId,
          organizationId: companyId,
          branchId: branchId,
          name: 'Supplier Old',
        ),
      );
      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );
      final db = await databaseService.database;
      await db.delete('suppliers');
      await pullWorker.run(companyId: companyId, branchId: branchId);

      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeSupplier,
        operation: 'update',
        entityId: supplierId,
        payload: partnerEntityCloudPayload(
          id: supplierId,
          organizationId: companyId,
          branchId: branchId,
          name: 'Supplier New',
          phone: '+970599222222',
        ),
      );
      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );
      await db.delete('suppliers', where: 'id = ?', whereArgs: [supplierId]);
      await pullWorker.run(companyId: companyId, branchId: branchId);
      expect((await readSupplier())?['name'], 'Supplier New');

      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeSupplier,
        operation: 'delete',
        entityId: supplierId,
        payload: partnerEntityCloudPayload(
          id: supplierId,
          organizationId: companyId,
          branchId: branchId,
          name: 'Supplier New',
          deleted: true,
        ),
      );
      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );
      await db.delete('suppliers', where: 'id = ?', whereArgs: [supplierId]);
      await db.insert('suppliers', {
        'id': supplierId,
        'organizationId': companyId,
        'branchId': branchId,
        'name': 'Stale Supplier',
        'creditLimit': 0,
        'createdAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await pullWorker.run(companyId: companyId, branchId: branchId);
      expect(await readSupplier(), isNull);

      await enqueuePartner(
        entityType: PartnersSyncConstants.entityTypeSupplier,
        operation: 'update',
        entityId: supplierId,
        payload: partnerEntityCloudPayload(
          id: supplierId,
          organizationId: companyId,
          branchId: branchId,
          name: 'Restored Supplier',
        ),
      );
      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: seedDeviceId,
      );
      await pullWorker.run(companyId: companyId, branchId: branchId);
      expect((await readSupplier())?['name'], 'Restored Supplier');
    });
  });
}
