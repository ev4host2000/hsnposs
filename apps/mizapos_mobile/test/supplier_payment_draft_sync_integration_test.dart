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
import 'package:mizapos_mobile/services/cloud/sync/supplier_payment_draft_payload.dart';
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

/// Supplier payment draft sync — requires backend on 127.0.0.1:8787.
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
    final db = await databaseService.database;
    for (final table in [
      'supplierPayments',
      'sync_outbox',
      'suppliers',
    ]) {
      await db.delete(table);
    }

    await db.insert('suppliers', {
      'id': supplierId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Draft Sync Supplier',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });

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
      transactionRegistry: transactionRegistry,
    );
  });

  Future<void> pullPaymentsOnly() {
    final workers = transactionRegistry.pullWorkers
        .where((w) => w.repository.entityType == SupplierPaymentSyncConstants.entityType)
        .toList();
    return TransactionOrchestrator.runPullWorkers(
      workers: workers,
      companyId: companyId,
      branchId: branchId,
    );
  }

  Future<void> pushPayments() {
    return TransactionOrchestrator.runPushWorkers(
      workers: transactionRegistry.pushWorkers,
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
        name: 'Draft Sync Supplier',
      ),
      databaseService: databaseService,
      storage: storage,
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
    double amount = 50,
    String? notes,
  }) {
    return supplierPaymentDraftAggregate(
      id: paymentId,
      organizationId: companyId,
      branchId: branchId,
      createdBy: userId,
      supplierId: supplierId,
      transactionVersion: transactionVersion,
      rowVersion: rowVersion,
      amount: amount,
      notes: notes,
      originDeviceId: seedDeviceId,
    );
  }

  Future<void> enqueueDraft({
    required String operation,
    required Map<String, dynamic> aggregate,
  }) async {
    final envelope = supplierPaymentDraftPushEnvelope(
      aggregateJson: aggregate,
      operation: operation,
      clientRowVersion: aggregate['header']['row_version'] as int? ?? 1,
    );
    await TransactionSyncOutboxWriter.record(
      entityType: SupplierPaymentSyncConstants.entityType,
      operation: operation,
      entityId: paymentId,
      organizationId: companyId,
      branchId: branchId,
      payload: envelope,
      databaseService: databaseService,
      storage: storage,
    );
  }

  Future<Map<String, Object?>?> readPaymentHeader() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'supplierPayments',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
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

  test('device A create draft → push → device B pull → update → delete', () async {
    await pushSupplier();
    final db = await databaseService.database;
    await db.delete('supplierPayments');

    final seqBeforeCreate = await readPaymentSyncSequence();
    await enqueueDraft(
      operation: 'create',
      aggregate: draftAggregate(notes: 'Draft v1'),
    );
    await pushPayments();

    await db.delete('supplierPayments', where: 'id = ?', whereArgs: [paymentId]);

    await rewindPaymentSyncSequence(seqBeforeCreate);
    await pullPaymentsOnly();

    final pulled = await readPaymentHeader();
    expect(pulled, isNotNull);
    expect(pulled!['paymentStatus'], 'draft');
    expect(pulled['notes'], 'Draft v1');
    expect(pulled['supplierId'], supplierId);
    expect(pulled['amount'], 50.0);

    await enqueueDraft(
      operation: 'update',
      aggregate: draftAggregate(
        transactionVersion: 1,
        rowVersion: 2,
        amount: 80,
        notes: 'Draft v2',
      ),
    );
    final seqBeforeUpdate = await readPaymentSyncSequence();
    await pushPayments();
    await db.delete('supplierPayments', where: 'id = ?', whereArgs: [paymentId]);
    await rewindPaymentSyncSequence(seqBeforeUpdate);
    await pullPaymentsOnly();

    final updated = await readPaymentHeader();
    expect(updated?['notes'], 'Draft v2');
    expect(updated?['amount'], 80.0);

    final cancelEnvelope = supplierPaymentDraftPushEnvelope(
      aggregateJson: supplierPaymentDraftAggregate(
        id: paymentId,
        organizationId: companyId,
        branchId: branchId,
        createdBy: userId,
        supplierId: supplierId,
        amount: 80,
        transactionVersion: 1,
        rowVersion: 3,
        status: 'cancelled',
      ),
      operation: 'cancel',
      clientRowVersion: 3,
    );
    await TransactionSyncOutboxWriter.record(
      entityType: SupplierPaymentSyncConstants.entityType,
      operation: 'cancel',
      entityId: paymentId,
      organizationId: companyId,
      branchId: branchId,
      payload: cancelEnvelope,
      databaseService: databaseService,
      storage: storage,
    );
    final seqBeforeCancel = await readPaymentSyncSequence();
    await pushPayments();

    await db.delete('supplierPayments', where: 'id = ?', whereArgs: [paymentId]);
    await db.insert('supplierPayments', {
      'id': paymentId,
      'organizationId': companyId,
      'branchId': branchId,
      'supplierId': supplierId,
      'amount': 80.0,
      'paymentDate': DateTime.now().toIso8601String(),
      'paymentMethod': 'cash',
      'paymentStatus': 'draft',
      'createdBy': userId,
    });
    await rewindPaymentSyncSequence(seqBeforeCancel);
    await pullPaymentsOnly();
    expect(await readPaymentHeader(), isNull);
  });
}
