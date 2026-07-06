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
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_sync_constants.dart';
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

/// Sales return draft sync — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  const seedProductId = 'a100e840-e29b-41d4-a716-446655440020';
  late String originalInvoiceId;
  late String parentLineId;
  late String returnId;
  late String returnLineId;
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
    originalInvoiceId = const Uuid().v4();
    parentLineId = const Uuid().v4();
    returnId = const Uuid().v4();
    returnLineId = const Uuid().v4();
    databaseService = DatabaseService();
    await prepareSyncIntegrationTest(databaseService: databaseService);
    final db = await databaseService.database;
    for (final table in [
      'salesReturns',
      'salesReturnItems',
      'salesInvoices',
      'salesInvoiceItems',
      'sync_outbox',
      'customers',
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
        'name': 'Draft Sync Product $returnId',
        'salePrice': 25.0,
        'costPrice': 10.0,
        'stockQty': 98.0,
        'isHidden': 0,
        'isFrozen': 0,
        'isService': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    productId = seedProductId;

    await db.insert('customers', {
      'id': customerId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Draft Sync Customer',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await ReturnTestSeed.seedPostedParentSalesInvoice(
      db,
      originalInvoiceId: originalInvoiceId,
      parentLineId: parentLineId,
      companyId: companyId,
      branchId: branchId,
      customerId: customerId,
      productId: productId,
      userId: userId,
    );

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
    SalesReturnSyncRegistry.registerWith(registry: transactionRegistry);
    SalesInvoiceSyncRegistry.registerWith(registry: transactionRegistry);
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

  Future<void> pullReturnsOnly() {
    final workers = transactionRegistry.pullWorkers
        .where((w) => w.repository.entityType == SalesReturnSyncConstants.entityType)
        .toList();
    return TransactionOrchestrator.runPullWorkers(
      workers: workers,
      companyId: companyId,
      branchId: branchId,
    );
  }

  Future<void> pullReturns() => pullReturnsOnly();

  Future<void> pushReturns() {
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
    return salesReturnDraftAggregate(
      id: returnId,
      organizationId: companyId,
      branchId: branchId,
      createdBy: userId,
      originalInvoiceId: originalInvoiceId,
      customerId: customerId,
      transactionVersion: transactionVersion,
      rowVersion: rowVersion,
      lineSubtotal: total,
      total: total,
      notes: notes,
      lines: [
        salesReturnLinePayload(
          lineId: returnLineId,
          productId: productId,
          quantity: 2,
          unitPrice: total / 2,
        ),
      ],
      originDeviceId: seedDeviceId,
    );
  }

  Future<void> enqueueDraft({
    required String operation,
    required Map<String, dynamic> aggregate,
  }) async {
    final envelope = salesReturnDraftPushEnvelope(
      aggregateJson: aggregate,
      operation: operation,
      clientRowVersion: aggregate['header']['row_version'] as int? ?? 1,
    );
    await TransactionSyncOutboxWriter.record(
      entityType: SalesReturnSyncConstants.entityType,
      operation: operation,
      entityId: returnId,
      organizationId: companyId,
      branchId: branchId,
      payload: envelope,
      databaseService: databaseService,
      storage: storage,
    );
  }

  Future<Map<String, Object?>?> readReturnHeader() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'salesReturns',
      where: 'id = ?',
      whereArgs: [returnId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> readReturnLines() async {
    final db = await databaseService.database;
    return db.query(
      'salesReturnItems',
      where: 'returnId = ?',
      whereArgs: [returnId],
    );
  }

  Future<void> pushOriginalInvoiceToCloud() async {
    await ensureTestCustomerOnCloud(
      databaseService: databaseService,
      storage: storage,
      pushWorker: pushWorker,
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
      customerId: customerId,
      name: 'Draft Sync Customer',
    );
    await ensureTestProductOnCloud(
      databaseService: databaseService,
      storage: storage,
      pushWorker: pushWorker,
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
      productId: productId,
      name: 'Draft Sync Product $returnId',
    );
    await TransactionSyncOutboxWriter.record(
      entityType: SalesInvoiceSyncConstants.entityType,
      operation: 'create',
      entityId: originalInvoiceId,
      organizationId: companyId,
      branchId: branchId,
      payload: salesInvoiceDraftPushEnvelope(
        aggregateJson: salesInvoiceDraftAggregate(
          id: originalInvoiceId,
          organizationId: companyId,
          branchId: branchId,
          createdBy: userId,
          customerId: customerId,
          lineSubtotal: 50,
          total: 50,
          lines: [
            salesInvoiceLinePayload(
              lineId: parentLineId,
              productId: productId,
              quantity: 2,
              unitPrice: 25,
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
    await pushReturns();
    final postResult = await SalesInvoicePostLocalService(
      databaseService: databaseService,
    ).postDraft(invoiceId: originalInvoiceId);
    expect(postResult.ok, isTrue);
    await pushReturns();
  }

  test('device A create draft → push → device B pull → update → delete', () async {
    await pushOriginalInvoiceToCloud();
    await pullReturns();
    final db = await databaseService.database;
    await db.delete('salesReturns');
    await db.delete('salesReturnItems');

    await enqueueDraft(
      operation: 'create',
      aggregate: draftAggregate(notes: 'Draft v1'),
    );
    await pushReturns();

    await db.delete('salesReturns', where: 'id = ?', whereArgs: [returnId]);
    await db.delete('salesReturnItems', where: 'returnId = ?', whereArgs: [returnId]);

    await pullReturns();

    final pulled = await readReturnHeader();
    expect(pulled, isNotNull);
    expect(pulled!['returnStatus'], 'draft');
    expect(pulled['notes'], 'Draft v1');
    expect(pulled['originalInvoiceId'], originalInvoiceId);
    expect((await readReturnLines()).length, 1);

    await enqueueDraft(
      operation: 'update',
      aggregate: draftAggregate(
        transactionVersion: 1,
        rowVersion: 2,
        total: 80,
        notes: 'Draft v2',
      ),
    );
    await pushReturns();
    await db.delete('salesReturns', where: 'id = ?', whereArgs: [returnId]);
    await db.delete('salesReturnItems', where: 'returnId = ?', whereArgs: [returnId]);
    await pullReturns();

    final updated = await readReturnHeader();
    expect(updated?['notes'], 'Draft v2');
    expect(updated?['total'], 80.0);

    final cancelEnvelope = salesReturnDraftPushEnvelope(
      aggregateJson: salesReturnDraftAggregate(
        id: returnId,
        organizationId: companyId,
        branchId: branchId,
        createdBy: userId,
        originalInvoiceId: originalInvoiceId,
        customerId: customerId,
        transactionVersion: 1,
        rowVersion: 3,
        status: 'cancelled',
      ),
      operation: 'cancel',
      clientRowVersion: 3,
    );
    await TransactionSyncOutboxWriter.record(
      entityType: SalesReturnSyncConstants.entityType,
      operation: 'cancel',
      entityId: returnId,
      organizationId: companyId,
      branchId: branchId,
      payload: cancelEnvelope,
      databaseService: databaseService,
      storage: storage,
    );
    await pushReturns();

    await db.delete('salesReturns', where: 'id = ?', whereArgs: [returnId]);
    await db.delete('salesReturnItems', where: 'returnId = ?', whereArgs: [returnId]);
    await db.insert('salesReturns', {
      'id': returnId,
      'organizationId': companyId,
      'branchId': branchId,
      'originalInvoiceId': originalInvoiceId,
      'customerId': customerId,
      'returnDate': DateTime.now().toIso8601String(),
      'total': 80.0,
      'refundPaymentType': 'cash',
      'returnStatus': 'draft',
      'createdBy': userId,
    });
    await pullReturns();
    expect(await readReturnHeader(), isNull);
  });
}
