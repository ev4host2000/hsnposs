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
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_orchestrator.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/utils/app_data_paths.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:mizapos_mobile/services/database_runtime_profile.dart';

import 'isolated_test_database.dart';
import 'sync_integration_test_helpers.dart';

/// Purchase invoice sync performance — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const seedProductId = 'a100e840-e29b-41d4-a716-446655440020';
  const supplierId = 'd100e840-e29b-41d4-a716-446655440050';

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
    transactionRegistry = PurchaseInvoiceSyncRegistry.createRegistered(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
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
      entityType: PartnersSyncConstants.entityTypeSupplier,
      operation: 'create',
      entityId: supplierId,
      organizationId: companyId,
      branchId: branchId,
      payload: partnerEntityCloudPayload(
        id: supplierId,
        organizationId: companyId,
        branchId: branchId,
        name: 'Sync Bench Supplier',
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
      scopeKey: PurchaseInvoiceSyncConstants.scopeKey,
      pullPath: PurchaseInvoiceSyncConstants.pullPath,
    );
    await db.delete('purchaseInvoices');
    await db.delete('purchaseInvoiceItems');
    await db.delete('stockMovements');
    await db.delete('partnerLedger');
    await db.delete('sync_outbox');

    await db.insert('suppliers', {
      'id': supplierId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Sync Bench Supplier',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final postService = PurchaseInvoicePostLocalService(
      databaseService: databaseService,
    );
    final invoiceIds = <String>[];

    for (var i = 0; i < count; i++) {
      final invoiceId = const Uuid().v4();
      final lineId = const Uuid().v4();
      invoiceIds.add(invoiceId);

      await db.insert('purchaseInvoices', {
        'id': invoiceId,
        'organizationId': companyId,
        'branchId': branchId,
        'supplierId': supplierId,
        'invoiceDate': DateTime.now().toIso8601String(),
        'total': 20.0,
        'paymentType': 'cash',
        'invoiceStatus': 'draft',
        'createdBy': userId,
        'discountAmount': 0,
        'taxPercent': 0,
        'lineSubtotal': 20.0,
        'paidAmount': 0,
        'transactionVersion': 0,
        'rowVersion': 1,
      });
      await db.insert('purchaseInvoiceItems', {
        'id': lineId,
        'invoiceId': invoiceId,
        'productId': seedProductId,
        'quantity': 2,
        'unitCost': 10,
        'lineTotal': 20,
      });

      await TransactionSyncOutboxWriter.record(
        entityType: PurchaseInvoiceSyncConstants.entityType,
        operation: 'create',
        entityId: invoiceId,
        organizationId: companyId,
        branchId: branchId,
        payload: purchaseInvoiceDraftPushEnvelope(
          aggregateJson: purchaseInvoiceDraftAggregate(
            id: invoiceId,
            organizationId: companyId,
            branchId: branchId,
            createdBy: userId,
            supplierId: supplierId,
            lineSubtotal: 20,
            total: 20,
            lines: [
              purchaseInvoiceLinePayload(
                lineId: lineId,
                productId: seedProductId,
                quantity: 2,
                unitCost: 10,
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

      final postResult = await postService.postDraft(invoiceId: invoiceId);
      expect(postResult.ok, isTrue, reason: invoiceId);
    }

    final pushSw = Stopwatch()..start();
    await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
    pushSw.stop();

    for (final id in invoiceIds) {
      await db.delete('purchaseInvoices', where: 'id = ?', whereArgs: [id]);
      await db.delete('purchaseInvoiceItems', where: 'invoiceId = ?', whereArgs: [id]);
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
    print('\n=== Purchase Invoice Sync Performance Report ===');
    for (final entry in report.entries) {
      final data = entry.value;
      // ignore: avoid_print
      print(
        '${entry.key}: push avg=${data['pushAvgMs']?.toStringAsFixed(2)}ms '
        'pull avg=${data['pullAvgMs']?.toStringAsFixed(2)}ms',
      );
    }
    // ignore: avoid_print
    print('Compare with Sales post-only benchmark (~20ms post local, ~10ms pipeline).');
    // ignore: avoid_print
    print('This test includes HTTP push + pull + apply on live backend.\n');

    expect(report.length, 3);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
