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
import 'package:mizapos_mobile/services/cloud/sync/posting/sales_invoice/sales_invoice_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_registry.dart';
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

/// Sales invoice post sync — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const seedProductId = 'a100e840-e29b-41d4-a716-446655440020';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  late String invoiceId;
  late String lineId;

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
    invoiceId = const Uuid().v4();
    lineId = const Uuid().v4();
    databaseService = DatabaseService();
    await prepareSyncIntegrationTest(databaseService: databaseService);
    final db = await databaseService.database;
    for (final table in [
      'salesInvoices',
      'salesInvoiceItems',
      'stockMovements',
      'partnerLedger',
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
        'name': 'Post Sync Product $invoiceId',
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
    transactionRegistry = SalesInvoiceSyncRegistry.createRegistered(
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

  Future<void> pushAll() {
    return pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
    );
  }

  Future<void> pushCustomer() async {
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
        name: 'Post Sync Customer',
      ),
      databaseService: databaseService,
      storage: storage,
    );
    await pushAll();
  }

  Map<String, dynamic> draftAggregate({
    int transactionVersion = 0,
    int rowVersion = 1,
    double total = 50,
  }) {
    return salesInvoiceDraftAggregate(
      id: invoiceId,
      organizationId: companyId,
      branchId: branchId,
      createdBy: userId,
      customerId: customerId,
      transactionVersion: transactionVersion,
      rowVersion: rowVersion,
      lineSubtotal: total,
      total: total,
      lines: [
        salesInvoiceLinePayload(
          lineId: lineId,
          productId: seedProductId,
          quantity: 2,
          unitPrice: total / 2,
        ),
      ],
      originDeviceId: seedDeviceId,
    );
  }

  Future<void> seedLocalDraft() async {
    final db = await databaseService.database;
    await db.insert('customers', {
      'id': customerId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Post Sync Customer',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('salesInvoices', {
      'id': invoiceId,
      'organizationId': companyId,
      'branchId': branchId,
      'customerId': customerId,
      'invoiceDate': DateTime.now().toIso8601String(),
      'total': 50.0,
      'paymentType': 'cash',
      'invoiceStatus': 'draft',
      'createdBy': userId,
      'discountAmount': 0,
      'taxPercent': 0,
      'lineSubtotal': 50.0,
      'paidAmount': 0,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
    await db.insert('salesInvoiceItems', {
      'id': lineId,
      'invoiceId': invoiceId,
      'productId': seedProductId,
      'quantity': 2,
      'unitPrice': 25,
      'lineTotal': 50,
    });
  }

  Future<void> enqueueDraftCreate() async {
    await TransactionSyncOutboxWriter.record(
      entityType: SalesInvoiceSyncConstants.entityType,
      operation: 'create',
      entityId: invoiceId,
      organizationId: companyId,
      branchId: branchId,
      payload: salesInvoiceDraftPushEnvelope(
        aggregateJson: draftAggregate(),
        operation: 'create',
        clientRowVersion: 1,
      ),
      databaseService: databaseService,
      storage: storage,
    );
  }

  Future<int> readInvoiceSyncSequence() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [companyId, branchId, SalesInvoiceSyncConstants.scopeKey],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['last_pulled_sequence'] as int?) ?? 0;
  }

  Future<void> rewindInvoiceSyncSequence(int sequence) async {
    final db = await databaseService.database;
    final rows = await db.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [companyId, branchId, SalesInvoiceSyncConstants.scopeKey],
    );
    if (rows.isEmpty) {
      await db.insert('sync_meta', {
        'organization_id': companyId,
        'branch_id': branchId,
        'scope_key': SalesInvoiceSyncConstants.scopeKey,
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
      whereArgs: [companyId, branchId, SalesInvoiceSyncConstants.scopeKey],
    );
  }

  test('device A draft → post → push → cloud → pull → device B', () async {
    await pushCustomer();
    await pullInvoices();

    await seedLocalDraft();
    final seqBeforeCreate = await readInvoiceSyncSequence();
    await enqueueDraftCreate();
    await pushAll();

    final postService = SalesInvoicePostLocalService(
      databaseService: databaseService,
    );
    final postResult = await postService.postDraft(invoiceId: invoiceId);
    expect(postResult.ok, isTrue);

    final db = await databaseService.database;
    final postOutbox = await db.query(
      'sync_outbox',
      where: 'entity_id = ? AND operation = ?',
      whereArgs: [invoiceId, 'post'],
    );
    expect(postOutbox.length, 1);

    await pushAll();

    await db.delete('stockMovements');
    await db.delete('partnerLedger');
    await db.delete('salesInvoiceItems');
    await db.delete('salesInvoices', where: 'id = ?', whereArgs: [invoiceId]);
    await db.update(
      'products',
      {'stockQty': 100.0},
      where: 'id = ?',
      whereArgs: [seedProductId],
    );

    final stockBeforePull = ((await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [seedProductId],
      limit: 1,
    )).first['stockQty'] as num?)
        ?.toDouble();
    expect(stockBeforePull, 100.0);

    await rewindInvoiceSyncSequence(seqBeforeCreate);
    await pullInvoices();

    final header = await db.query(
      'salesInvoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    expect(header, isNotEmpty);
    expect(header.first['invoiceStatus'], 'posted');
    expect(header.first['transactionVersion'], 1);

    final movements = await db.query(
      'stockMovements',
      where: 'referenceId = ?',
      whereArgs: [invoiceId],
    );
    expect(movements.length, 1);
    expect(
      movements.first['id'],
      SalesInvoicePostIds.stockMovementId(invoiceId, lineId),
    );

    final ledger = await db.query(
      'partnerLedger',
      where: 'referenceId = ?',
      whereArgs: [invoiceId],
    );
    expect(ledger.length, greaterThanOrEqualTo(2));

    final qtyDeducted = movements.fold<double>(
      0,
      (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0),
    );
    final product = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [seedProductId],
      limit: 1,
    );
    expect(product.first['stockQty'], stockBeforePull! - qtyDeducted);
    expect(qtyDeducted, 2.0);

    final movementCountBefore = movements.length;
    final ledgerCountBefore = ledger.length;

    await pushAll();
    await pullInvoices();

    final movementsAfter = await db.query(
      'stockMovements',
      where: 'referenceId = ?',
      whereArgs: [invoiceId],
    );
    final ledgerAfter = await db.query(
      'partnerLedger',
      where: 'referenceId = ?',
      whereArgs: [invoiceId],
    );
    expect(movementsAfter.length, movementCountBefore);
    expect(ledgerAfter.length, ledgerCountBefore);
  });
}
