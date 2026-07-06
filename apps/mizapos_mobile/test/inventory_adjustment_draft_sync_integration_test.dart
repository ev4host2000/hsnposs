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
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_orchestrator.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_mobile/services/database_runtime_profile.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/utils/app_data_paths.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'isolated_test_database.dart';
import 'sync_integration_test_helpers.dart';

/// Inventory adjustment draft sync — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  late String adjustmentId;

  late DatabaseService databaseService;
  late CloudSecureStoragePlaceholder storage;
  late ProductsSyncRepository productsRepository;
  late TransactionRegistry transactionRegistry;
  late ProductsPushWorker pushWorker;

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
    adjustmentId = const Uuid().v4();
    databaseService = DatabaseService();
    await prepareSyncIntegrationTest(databaseService: databaseService);
    final db = await databaseService.database;
    for (final table in [
      'inventoryAdjustments',
      'sync_outbox',
      'products',
    ]) {
      await db.delete(table);
    }

    await db.insert(
      'products',
      {
        'id': productId,
        'organizationId': companyId,
        'branchId': branchId,
        'name': 'Draft Sync Product $adjustmentId',
        'salePrice': 25.0,
        'costPrice': 10.0,
        'stockQty': 10.0,
        'isHidden': 0,
        'isFrozen': 0,
        'isService': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    storage = CloudSecureStoragePlaceholder();
    TransactionSyncOutboxWriter.bindStorage(storage);
    ProductSyncOutboxWriter.bindStorage(storage);
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

    transactionRegistry = TransactionRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    InventoryAdjustmentSyncRegistry.registerWith(registry: transactionRegistry);
    productsRepository = ProductsSyncRepository(
      productsSyncApi: ProductsSyncApi(apiClient: apiClient, config: config),
      databaseService: databaseService,
    );
    pushWorker = ProductsPushWorker(
      repository: productsRepository,
      transactionRegistry: transactionRegistry,
    );
  });

  Future<void> pullAdjustmentsOnly() {
    final workers = transactionRegistry.pullWorkers
        .where(
          (w) =>
              w.repository.entityType ==
              InventoryAdjustmentSyncConstants.entityType,
        )
        .toList();
    return TransactionOrchestrator.runPullWorkers(
      workers: workers,
      companyId: companyId,
      branchId: branchId,
    );
  }

  Future<void> pushAdjustments() {
    return TransactionOrchestrator.runPushWorkers(
      workers: transactionRegistry.pushWorkers,
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
  }

  Future<void> pushProduct() async {
    final product = ProductEntity(
      id: productId,
      organizationId: companyId,
      branchId: branchId,
      name: 'Draft Sync Product $adjustmentId',
      salePrice: 25.0,
      costPrice: 10.0,
      stockQty: 10.0,
    );
    await productsRepository.upsertLocalProductFromEntity(product);
    await productsRepository.enqueueProductCreate(
      product: product,
      deviceId: seedDeviceId,
      installationId: installationId,
    );
    await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
  }

  Map<String, dynamic> draftAggregate({
    int transactionVersion = 0,
    int rowVersion = 1,
    double quantityDelta = 5,
    String? notes,
  }) {
    return inventoryAdjustmentDraftAggregate(
      id: adjustmentId,
      organizationId: companyId,
      branchId: branchId,
      createdBy: userId,
      productId: productId,
      quantityDelta: quantityDelta,
      adjustmentReason: 'correction',
      transactionVersion: transactionVersion,
      rowVersion: rowVersion,
      notes: notes,
      originDeviceId: seedDeviceId,
    );
  }

  Future<void> enqueueDraft({
    required String operation,
    required Map<String, dynamic> aggregate,
  }) async {
    final envelope = inventoryAdjustmentDraftPushEnvelope(
      aggregateJson: aggregate,
      operation: operation,
      clientRowVersion: aggregate['header']['row_version'] as int? ?? 1,
    );
    await TransactionSyncOutboxWriter.record(
      entityType: InventoryAdjustmentSyncConstants.entityType,
      operation: operation,
      entityId: adjustmentId,
      organizationId: companyId,
      branchId: branchId,
      payload: envelope,
      databaseService: databaseService,
      storage: storage,
    );
  }

  Future<Map<String, Object?>?> readAdjustmentHeader() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'inventoryAdjustments',
      where: 'id = ?',
      whereArgs: [adjustmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> readAdjustmentSyncSequence() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [
        companyId,
        branchId,
        InventoryAdjustmentSyncConstants.scopeKey,
      ],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['last_pulled_sequence'] as int?) ?? 0;
  }

  Future<void> rewindAdjustmentSyncSequence(int sequence) async {
    final db = await databaseService.database;
    final rows = await db.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [
        companyId,
        branchId,
        InventoryAdjustmentSyncConstants.scopeKey,
      ],
    );
    if (rows.isEmpty) {
      await db.insert('sync_meta', {
        'organization_id': companyId,
        'branch_id': branchId,
        'scope_key': InventoryAdjustmentSyncConstants.scopeKey,
        'last_pulled_sequence': sequence,
        'last_pulled_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      return;
    }
    await db.update(
      'sync_meta',
      {
        'last_pulled_sequence': sequence,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [
        companyId,
        branchId,
        InventoryAdjustmentSyncConstants.scopeKey,
      ],
    );
  }

  test('device A create draft → push → device B pull → update → delete', () async {
    await pushProduct();
    final db = await databaseService.database;
    await db.delete('inventoryAdjustments');

    final seqBeforeCreate = await readAdjustmentSyncSequence();
    await enqueueDraft(
      operation: 'create',
      aggregate: draftAggregate(notes: 'Draft v1'),
    );
    await pushAdjustments();

    await db.delete(
      'inventoryAdjustments',
      where: 'id = ?',
      whereArgs: [adjustmentId],
    );

    await rewindAdjustmentSyncSequence(seqBeforeCreate);
    await pullAdjustmentsOnly();

    final pulled = await readAdjustmentHeader();
    expect(pulled, isNotNull);
    expect(pulled!['adjustmentStatus'], 'draft');
    expect(pulled['notes'], 'Draft v1');
    expect(pulled['productId'], productId);
    expect(pulled['quantityDelta'], 5.0);

    await enqueueDraft(
      operation: 'update',
      aggregate: draftAggregate(
        transactionVersion: 1,
        rowVersion: 2,
        quantityDelta: 8,
        notes: 'Draft v2',
      ),
    );
    final seqBeforeUpdate = await readAdjustmentSyncSequence();
    await pushAdjustments();
    await db.delete(
      'inventoryAdjustments',
      where: 'id = ?',
      whereArgs: [adjustmentId],
    );
    await rewindAdjustmentSyncSequence(seqBeforeUpdate);
    await pullAdjustmentsOnly();

    final updated = await readAdjustmentHeader();
    expect(updated?['notes'], 'Draft v2');
    expect(updated?['quantityDelta'], 8.0);

    final cancelEnvelope = inventoryAdjustmentDraftPushEnvelope(
      aggregateJson: inventoryAdjustmentDraftAggregate(
        id: adjustmentId,
        organizationId: companyId,
        branchId: branchId,
        createdBy: userId,
        productId: productId,
        quantityDelta: 8,
        adjustmentReason: 'correction',
        transactionVersion: 1,
        rowVersion: 3,
        status: 'cancelled',
      ),
      operation: 'cancel',
      clientRowVersion: 3,
    );
    await TransactionSyncOutboxWriter.record(
      entityType: InventoryAdjustmentSyncConstants.entityType,
      operation: 'cancel',
      entityId: adjustmentId,
      organizationId: companyId,
      branchId: branchId,
      payload: cancelEnvelope,
      databaseService: databaseService,
      storage: storage,
    );
    final seqBeforeCancel = await readAdjustmentSyncSequence();
    await pushAdjustments();

    await db.delete(
      'inventoryAdjustments',
      where: 'id = ?',
      whereArgs: [adjustmentId],
    );
    await db.insert('inventoryAdjustments', {
      'id': adjustmentId,
      'organizationId': companyId,
      'branchId': branchId,
      'productId': productId,
      'quantityDelta': 8.0,
      'adjustmentReason': 'correction',
      'adjustmentDate': DateTime.now().toIso8601String(),
      'adjustmentStatus': 'draft',
      'createdBy': userId,
    });
    await rewindAdjustmentSyncSequence(seqBeforeCancel);
    await pullAdjustmentsOnly();
    expect(await readAdjustmentHeader(), isNull);
  });
}
