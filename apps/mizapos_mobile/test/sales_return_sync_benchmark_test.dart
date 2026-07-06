import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_sync_registry.dart';
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
import 'return_test_seed.dart';
import 'return_sync_test_helpers.dart';

/// Sales return sync performance — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const seedProductId = 'a100e840-e29b-41d4-a716-446655440020';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';

  late DatabaseService databaseService;
  late CloudSecureStoragePlaceholder storage;
  late CloudApiClient apiClient;
  late ProductsPushWorker pushWorker;
  late TransactionRegistry transactionRegistry;

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
    storage = CloudSecureStoragePlaceholder();
    TransactionSyncOutboxWriter.bindStorage(storage);
    CatalogSyncOutboxWriter.bindStorage(storage);

    final config = CloudConfig.development();
    const httpClient = CloudHttpClientIo();
    apiClient = CloudApiClient(
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

    final partnersRegistry = PartnersSyncRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    transactionRegistry = TransactionRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    SalesInvoiceSyncRegistry.registerWith(registry: transactionRegistry);
    SalesReturnSyncRegistry.registerWith(registry: transactionRegistry);
    final productsRepository = ProductsSyncRepository(
      productsSyncApi: ProductsSyncApi(apiClient: apiClient, config: config),
      databaseService: databaseService,
    );
    pushWorker = ProductsPushWorker(
      repository: productsRepository,
      partnersRegistry: partnersRegistry,
      transactionRegistry: transactionRegistry,
    );

    await CatalogSyncOutboxWriter.record(
      entityType: PartnersSyncConstants.entityTypeCustomer,
      operation: 'create',
      entityId: customerId,
      organizationId: companyId,
      branchId: branchId,
      payload: partnerEntityCloudPayload(
        id: customerId,
        organizationId: companyId,
        branchId: branchId,
        name: 'Sync Bench Customer',
      ),
      databaseService: databaseService,
      storage: storage,
    );
    await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
  });

  Future<void> seedProductOnce() async {
    await ensureTestProductOnCloud(
      databaseService: databaseService,
      storage: storage,
      pushWorker: pushWorker,
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
      productId: seedProductId,
    );
  }

  Future<Map<String, double>> benchmarkFullCycle(int count) async {
    await seedProductOnce();
    final db = await databaseService.database;
    await advanceSyncMetaToCloudTail(
      apiClient: apiClient,
      db: db,
      organizationId: companyId,
      branchId: branchId,
      scopeKey: SalesInvoiceSyncConstants.scopeKey,
      pullPath: SalesInvoiceSyncConstants.pullPath,
    );
    await advanceSyncMetaToCloudTail(
      apiClient: apiClient,
      db: db,
      organizationId: companyId,
      branchId: branchId,
      scopeKey: SalesReturnSyncConstants.scopeKey,
      pullPath: SalesReturnSyncConstants.pullPath,
    );
    await db.delete('salesReturns');
    await db.delete('salesReturnItems');
    await db.delete('salesInvoices');
    await db.delete('salesInvoiceItems');
    await db.delete('stockMovements');
    await db.delete('partnerLedger');
    await db.delete('sync_outbox');

    await db.insert('customers', {
      'id': customerId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Sync Bench Customer',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final postService = SalesReturnPostLocalService(
      databaseService: databaseService,
    );
    final returnIds = <String>[];

    for (var i = 0; i < count; i++) {
      final originalInvoiceId = const Uuid().v4();
      final parentLineId = const Uuid().v4();
      final returnId = const Uuid().v4();
      final returnLineId = const Uuid().v4();
      returnIds.add(returnId);

      await stagePostedSalesInvoiceForSync(
        databaseService: databaseService,
        storage: storage,
        originalInvoiceId: originalInvoiceId,
        parentLineId: parentLineId,
        companyId: companyId,
        branchId: branchId,
        customerId: customerId,
        productId: seedProductId,
        userId: userId,
        deviceId: seedDeviceId,
        total: 20,
      );
      await ReturnTestSeed.seedSalesReturnDraft(
        db,
        returnId: returnId,
        returnLineId: returnLineId,
        originalInvoiceId: originalInvoiceId,
        companyId: companyId,
        branchId: branchId,
        customerId: customerId,
        productId: seedProductId,
        userId: userId,
        total: 20,
      );

      await TransactionSyncOutboxWriter.record(
        entityType: SalesReturnSyncConstants.entityType,
        operation: 'create',
        entityId: returnId,
        organizationId: companyId,
        branchId: branchId,
        payload: salesReturnDraftPushEnvelope(
          aggregateJson: salesReturnDraftAggregate(
            id: returnId,
            organizationId: companyId,
            branchId: branchId,
            createdBy: userId,
            originalInvoiceId: originalInvoiceId,
            customerId: customerId,
            lineSubtotal: 20,
            total: 20,
            lines: [
              salesReturnLinePayload(
                lineId: returnLineId,
                productId: seedProductId,
                quantity: 2,
                unitPrice: 10,
              ),
            ],
            originDeviceId: seedDeviceId,
          ),
          operation: 'create',
          clientRowVersion: 1,
        ),
        databaseService: databaseService,
        storage: storage,
      );

      final postResult = await postService.postDraft(returnId: returnId);
      expect(postResult.ok, isTrue, reason: returnId);
    }

    final pushSw = Stopwatch()..start();
    await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
    pushSw.stop();

    for (final id in returnIds) {
      await db.delete('salesReturns', where: 'id = ?', whereArgs: [id]);
      await db.delete('salesReturnItems', where: 'returnId = ?', whereArgs: [id]);
    }
    await db.delete('stockMovements');
    await db.delete('partnerLedger');

    final pullSw = Stopwatch()..start();
    await TransactionOrchestrator.runPullWorkers(
      workers: transactionRegistry.pullWorkers,
      companyId: companyId,
      branchId: branchId,
    );
    pullSw.stop();

    return {
      'count': count.toDouble(),
      'pushTotalMs': pushSw.elapsedMilliseconds.toDouble(),
      'pushAvgMs': pushSw.elapsedMilliseconds / count,
      'pullTotalMs': pullSw.elapsedMilliseconds.toDouble(),
      'pullAvgMs': pullSw.elapsedMilliseconds / count,
    };
  }

  test('performance report — push + pull sync cycle', () async {
    final report = <String, Map<String, double>>{};
    for (final n in [100, 500, 1000]) {
      report['sync_$n'] = await benchmarkFullCycle(n);
    }

    // ignore: avoid_print
    print('\n=== Sales Return Sync Performance Report ===');
    for (final entry in report.entries) {
      final data = entry.value;
      // ignore: avoid_print
      print(
        '${entry.key}: push avg=${data['pushAvgMs']?.toStringAsFixed(2)}ms '
        'pull avg=${data['pullAvgMs']?.toStringAsFixed(2)}ms',
      );
    }
    // ignore: avoid_print
    print('Compare with Sales/Purchase Invoice sync benchmark for baseline.');
    // ignore: avoid_print
    print('This test includes HTTP push + pull + apply on live backend.\n');

    expect(report.length, 3);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
