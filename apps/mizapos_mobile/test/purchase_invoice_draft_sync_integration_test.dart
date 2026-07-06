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
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_draft_payload.dart';
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

/// Purchase invoice draft sync — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const seedProductId = 'a100e840-e29b-41d4-a716-446655440020';
  late String invoiceId;
  late String lineId;
  late String productId;

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
    invoiceId = const Uuid().v4();
    lineId = const Uuid().v4();
    databaseService = DatabaseService();
    await prepareSyncIntegrationTest(databaseService: databaseService);
    final db = await databaseService.database;
    for (final table in [
      'purchaseInvoices',
      'purchaseInvoiceItems',
      'sync_outbox',
    ]) {
      await db.delete(table);
    }

    await db.delete('products', where: 'id = ?', whereArgs: [seedProductId]);
    await db.insert(
      'products',
      {
        'id': seedProductId,
        'organizationId': companyId,
        'branchId': branchId,
        'name': 'Draft Sync Product $invoiceId',
        'salePrice': 25.0,
        'costPrice': 10.0,
        'stockQty': 100.0,
        'isHidden': 0,
        'isFrozen': 0,
        'isService': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    productId = seedProductId;

    storage = CloudSecureStoragePlaceholder();
    TransactionSyncOutboxWriter.bindStorage(storage);
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

    transactionRegistry = PurchaseInvoiceSyncRegistry.createRegistered(
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
      transactionRegistry: transactionRegistry,
    );
  });

  Future<void> pullInvoices() {
    return TransactionOrchestrator.runPullWorkers(
      workers: transactionRegistry.pullWorkers,
      companyId: companyId,
      branchId: branchId,
    );
  }

  Future<void> pushInvoices() {
    return TransactionOrchestrator.runPushWorkers(
      workers: transactionRegistry.pushWorkers,
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
  }

  Map<String, dynamic> draftAggregate({
    int transactionVersion = 0,
    int rowVersion = 1,
    double total = 50,
    String? notes,
  }) {
    return purchaseInvoiceDraftAggregate(
      id: invoiceId,
      organizationId: companyId,
      branchId: branchId,
      createdBy: userId,
      transactionVersion: transactionVersion,
      rowVersion: rowVersion,
      lineSubtotal: total,
      total: total,
      notes: notes,
      lines: [
        purchaseInvoiceLinePayload(
          lineId: lineId,
          productId: productId,
          quantity: 2,
          unitCost: total / 2,
        ),
      ],
      originDeviceId: seedDeviceId,
    );
  }

  Future<void> enqueueDraft({
    required String operation,
    required Map<String, dynamic> aggregate,
  }) async {
    final envelope = purchaseInvoiceDraftPushEnvelope(
      aggregateJson: aggregate,
      operation: operation,
      clientRowVersion: aggregate['header']['row_version'] as int? ?? 1,
    );
    await TransactionSyncOutboxWriter.record(
      entityType: PurchaseInvoiceSyncConstants.entityType,
      operation: operation,
      entityId: invoiceId,
      organizationId: companyId,
      branchId: branchId,
      payload: envelope,
      databaseService: databaseService,
      storage: storage,
    );
  }

  Future<Map<String, Object?>?> readInvoiceHeader() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'purchaseInvoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> readInvoiceLines() async {
    final db = await databaseService.database;
    return db.query(
      'purchaseInvoiceItems',
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );
  }

  test('device A create draft → push → device B pull → update → delete', () async {
    await pullInvoices();
    final db = await databaseService.database;
    await db.delete('purchaseInvoices');
    await db.delete('purchaseInvoiceItems');

    await enqueueDraft(
      operation: 'create',
      aggregate: draftAggregate(notes: 'Draft v1'),
    );
    await pushInvoices();

    await db.delete('purchaseInvoices', where: 'id = ?', whereArgs: [invoiceId]);
    await db.delete('purchaseInvoiceItems', where: 'invoiceId = ?', whereArgs: [invoiceId]);

    await pullInvoices();

    final pulled = await readInvoiceHeader();
    expect(pulled, isNotNull);
    expect(pulled!['invoiceStatus'], 'draft');
    expect(pulled['notes'], 'Draft v1');
    expect((await readInvoiceLines()).length, 1);

    await enqueueDraft(
      operation: 'update',
      aggregate: draftAggregate(
        transactionVersion: 1,
        rowVersion: 2,
        total: 80,
        notes: 'Draft v2',
      ),
    );
    await pushInvoices();
    await db.delete('purchaseInvoices', where: 'id = ?', whereArgs: [invoiceId]);
    await db.delete('purchaseInvoiceItems', where: 'invoiceId = ?', whereArgs: [invoiceId]);
    await pullInvoices();

    final updated = await readInvoiceHeader();
    expect(updated?['notes'], 'Draft v2');
    expect(updated?['total'], 80.0);

    final cancelEnvelope = purchaseInvoiceDraftPushEnvelope(
      aggregateJson: purchaseInvoiceDraftAggregate(
        id: invoiceId,
        organizationId: companyId,
        branchId: branchId,
        createdBy: userId,
        transactionVersion: 1,
        rowVersion: 3,
        status: 'cancelled',
      ),
      operation: 'cancel',
      clientRowVersion: 3,
    );
    await TransactionSyncOutboxWriter.record(
      entityType: PurchaseInvoiceSyncConstants.entityType,
      operation: 'cancel',
      entityId: invoiceId,
      organizationId: companyId,
      branchId: branchId,
      payload: cancelEnvelope,
      databaseService: databaseService,
      storage: storage,
    );
    await pushInvoices();

    await db.delete('purchaseInvoices', where: 'id = ?', whereArgs: [invoiceId]);
    await db.delete('purchaseInvoiceItems', where: 'invoiceId = ?', whereArgs: [invoiceId]);
    await db.insert('purchaseInvoices', {
      'id': invoiceId,
      'organizationId': companyId,
      'branchId': branchId,
      'invoiceDate': DateTime.now().toIso8601String(),
      'total': 80.0,
      'paymentType': 'cash',
      'invoiceStatus': 'draft',
      'createdBy': userId,
    });
    await pullInvoices();
    expect(await readInvoiceHeader(), isNull);
  });
}
