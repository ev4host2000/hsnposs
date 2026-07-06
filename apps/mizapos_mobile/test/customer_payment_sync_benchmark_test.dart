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
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/customer_payment_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_registry.dart';
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
import 'payment_test_seed.dart';

/// Customer payment sync performance — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';

  late DatabaseService databaseService;
  late CloudSecureStoragePlaceholder storage;
  late ProductsPushWorker pushWorker;
  late TransactionRegistry transactionRegistry;
  late bool backendAvailable;

  setUpAll(() async {
    await setUpIsolatedTestDatabase(
      profile: DatabaseRuntimeProfile.integrationTest,
    );
    await File(appDataFilePath('.mizapos_device_id'))
        .writeAsString(installationId);

    backendAvailable = false;
    try {
      final ping = await HttpClient()
          .getUrl(Uri.parse('http://127.0.0.1:8787/health/ping'))
          .timeout(const Duration(seconds: 3))
          .then((r) => r.close());
      backendAvailable = ping.statusCode == 200;
    } on Object {
      backendAvailable = false;
    }
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    if (!backendAvailable) return;

    databaseService = DatabaseService();
    storage = CloudSecureStoragePlaceholder();
    TransactionSyncOutboxWriter.bindStorage(storage);
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

    final partnersRegistry = PartnersSyncRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    transactionRegistry = CustomerPaymentSyncRegistry.createRegistered(
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

  Future<Map<String, double>> benchmarkFullCycle(int count) async {
    final db = await databaseService.database;
    await db.delete('customerPayments');
    await db.delete('cashTransactions');
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

    final postService = CustomerPaymentPostLocalService(
      databaseService: databaseService,
    );
    final paymentIds = <String>[];

    for (var i = 0; i < count; i++) {
      final paymentId = const Uuid().v4();
      paymentIds.add(paymentId);

      await PaymentTestSeed.seedCustomerPaymentDraft(
        db,
        paymentId: paymentId,
        companyId: companyId,
        branchId: branchId,
        customerId: customerId,
        userId: userId,
        amount: 20,
      );

      await TransactionSyncOutboxWriter.record(
        entityType: CustomerPaymentSyncConstants.entityType,
        operation: 'create',
        entityId: paymentId,
        organizationId: companyId,
        branchId: branchId,
        payload: customerPaymentDraftPushEnvelope(
          aggregateJson: customerPaymentDraftAggregate(
            id: paymentId,
            organizationId: companyId,
            branchId: branchId,
            createdBy: userId,
            customerId: customerId,
            amount: 20,
            originDeviceId: seedDeviceId,
          ),
          operation: 'create',
          clientRowVersion: 1,
        ),
        databaseService: databaseService,
        storage: storage,
      );

      final postResult = await postService.postDraft(paymentId: paymentId);
      expect(postResult.ok, isTrue, reason: paymentId);
    }

    final pushSw = Stopwatch()..start();
    await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
    pushSw.stop();

    for (final id in paymentIds) {
      await db.delete('customerPayments', where: 'id = ?', whereArgs: [id]);
    }
    await db.delete('cashTransactions');
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
    if (!backendAvailable) {
      // ignore: avoid_print
      print('\n=== Customer Payment Sync Benchmark SKIPPED (backend unavailable) ===\n');
      return;
    }

    final report = <String, Map<String, double>>{};
    for (final n in [100, 500, 1000]) {
      report['sync_$n'] = await benchmarkFullCycle(n);
    }

    // ignore: avoid_print
    print('\n=== Customer Payment Sync Performance Report ===');
    for (final entry in report.entries) {
      final data = entry.value;
      // ignore: avoid_print
      print(
        '${entry.key}: push avg=${data['pushAvgMs']?.toStringAsFixed(2)}ms '
        'pull avg=${data['pullAvgMs']?.toStringAsFixed(2)}ms',
      );
    }
    // ignore: avoid_print
    print('Compare with Sales Return sync benchmark for baseline.');
    // ignore: avoid_print
    print('This test includes HTTP push + pull + apply on live backend.\n');

    expect(report.length, 3);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
