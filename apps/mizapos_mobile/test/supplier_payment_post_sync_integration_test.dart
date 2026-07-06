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
import 'package:mizapos_mobile/services/cloud/sync/posting/supplier_payment/supplier_payment_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_sync_registry.dart';
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

/// Supplier payment post sync — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const supplierId = 'd100e840-e29b-41d4-a716-446655440050';
  late String paymentId;

  late DatabaseService databaseService;
  late CloudSecureStoragePlaceholder storage;
  late ProductsSyncRepository productsRepository;
  late PartnersSyncRegistry partnersRegistry;
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
    paymentId = const Uuid().v4();
    databaseService = DatabaseService();
    await prepareSyncIntegrationTest(databaseService: databaseService);
    final db = await databaseService.database;
    for (final table in [
      'supplierPayments',
      'cashTransactions',
      'partnerLedger',
      'sync_outbox',
      'suppliers',
    ]) {
      await db.delete(table);
    }

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

    partnersRegistry = PartnersSyncRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    transactionRegistry = TransactionRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    SupplierPaymentSyncRegistry.registerWith(registry: transactionRegistry);
    productsRepository = ProductsSyncRepository(
      productsSyncApi: ProductsSyncApi(apiClient: apiClient, config: config),
      databaseService: databaseService,
    );
    pushWorker = ProductsPushWorker(
      repository: productsRepository,
      partnersRegistry: partnersRegistry,
      transactionRegistry: transactionRegistry,
    );
  });

  Future<void> pullPaymentsOnly() {
    final workers = transactionRegistry.pullWorkers
        .where(
          (w) => w.repository.entityType == SupplierPaymentSyncConstants.entityType,
        )
        .toList();
    return TransactionOrchestrator.runPullWorkers(
      workers: workers,
      companyId: companyId,
      branchId: branchId,
    );
  }

  Future<void> pushAll() {
    return pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
  }

  Future<void> pushSupplier() async {
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
        name: 'Post Sync Supplier',
      ),
      databaseService: databaseService,
      storage: storage,
    );
    await pushAll();
  }

  Future<void> seedLocalPaymentDraft() async {
    final db = await databaseService.database;
    await db.insert('suppliers', {
      'id': supplierId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Post Sync Supplier',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('supplierPayments', {
      'id': paymentId,
      'organizationId': companyId,
      'branchId': branchId,
      'supplierId': supplierId,
      'amount': 50.0,
      'paymentDate': DateTime.now().toIso8601String(),
      'paymentMethod': 'cash',
      'paymentStatus': 'draft',
      'createdBy': userId,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
  }

  Future<void> enqueuePaymentDraftCreate() async {
    await TransactionSyncOutboxWriter.record(
      entityType: SupplierPaymentSyncConstants.entityType,
      operation: 'create',
      entityId: paymentId,
      organizationId: companyId,
      branchId: branchId,
      payload: supplierPaymentDraftPushEnvelope(
        aggregateJson: supplierPaymentDraftAggregate(
          id: paymentId,
          organizationId: companyId,
          branchId: branchId,
          createdBy: userId,
          supplierId: supplierId,
          amount: 50,
          originDeviceId: seedDeviceId,
        ),
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: databaseService,
      storage: storage,
    );
  }

  Future<int> readPaymentSyncSequence() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [companyId, branchId, SupplierPaymentSyncConstants.scopeKey],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['last_pulled_sequence'] as int?) ?? 0;
  }

  Future<void> rewindPaymentSyncSequence(int sequence) async {
    final db = await databaseService.database;
    final rows = await db.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [companyId, branchId, SupplierPaymentSyncConstants.scopeKey],
    );
    if (rows.isEmpty) {
      await db.insert('sync_meta', {
        'organization_id': companyId,
        'branch_id': branchId,
        'scope_key': SupplierPaymentSyncConstants.scopeKey,
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
      whereArgs: [companyId, branchId, SupplierPaymentSyncConstants.scopeKey],
    );
  }

  test('device A draft → post → push → cloud → pull → device B', () async {
    await pushSupplier();

    await seedLocalPaymentDraft();
    final seqBeforeCreate = await readPaymentSyncSequence();
    await enqueuePaymentDraftCreate();
    await pushAll();

    final postService = SupplierPaymentPostLocalService(
      databaseService: databaseService,
    );
    final postResult = await postService.postDraft(paymentId: paymentId);
    expect(postResult.ok, isTrue);

    final db = await databaseService.database;
    final postOutbox = await db.query(
      'sync_outbox',
      where: 'entity_id = ? AND operation = ?',
      whereArgs: [paymentId, 'post'],
    );
    expect(postOutbox.length, 1);

    await pushAll();

    await db.delete('cashTransactions', where: 'referenceId = ?', whereArgs: [paymentId]);
    await db.delete('partnerLedger', where: 'referenceId = ?', whereArgs: [paymentId]);
    await db.delete('supplierPayments', where: 'id = ?', whereArgs: [paymentId]);

    await rewindPaymentSyncSequence(seqBeforeCreate);
    await pullPaymentsOnly();

    final header = await db.query(
      'supplierPayments',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    expect(header, isNotEmpty);
    expect(header.first['paymentStatus'], 'posted');
    expect(header.first['transactionVersion'], 1);
    expect(header.first['supplierId'], supplierId);

    final cash = await db.query(
      'cashTransactions',
      where: 'referenceId = ?',
      whereArgs: [paymentId],
    );
    expect(cash.length, 1);
    expect(
      cash.first['id'],
      SupplierPaymentPostIds.cashTransactionId(paymentId),
    );
    expect(cash.first['transactionType'], 'out');

    final ledger = await db.query(
      'partnerLedger',
      where: 'referenceId = ?',
      whereArgs: [paymentId],
    );
    expect(ledger.length, 1);
    expect(
      ledger.first['id'],
      SupplierPaymentPostIds.accountingEntryId(paymentId),
    );

    final cashCountBefore = cash.length;
    final ledgerCountBefore = ledger.length;

    await pushAll();
    await pullPaymentsOnly();

    final cashAfter = await db.query(
      'cashTransactions',
      where: 'referenceId = ?',
      whereArgs: [paymentId],
    );
    final ledgerAfter = await db.query(
      'partnerLedger',
      where: 'referenceId = ?',
      whereArgs: [paymentId],
    );
    expect(cashAfter.length, cashCountBefore);
    expect(ledgerAfter.length, ledgerCountBefore);
  });
}
