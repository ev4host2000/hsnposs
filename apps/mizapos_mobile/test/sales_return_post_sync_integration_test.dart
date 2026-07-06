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
import 'package:mizapos_mobile/services/cloud/sync/posting/sales_return/sales_return_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_draft_payload.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_post_local_service.dart';
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

/// Sales return post sync — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const seedProductId = 'a100e840-e29b-41d4-a716-446655440020';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  late String originalInvoiceId;
  late String parentLineId;
  late String returnId;
  late String returnLineId;

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
        'name': 'Post Sync Product $returnId',
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
    transactionRegistry = TransactionRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    SalesInvoiceSyncRegistry.registerWith(registry: transactionRegistry);
    SalesReturnSyncRegistry.registerWith(registry: transactionRegistry);
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
        .where(
          (w) => w.repository.entityType == SalesReturnSyncConstants.entityType,
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

  Future<void> seedAndSyncParentInvoice() async {
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
      'id': originalInvoiceId,
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
      'id': parentLineId,
      'invoiceId': originalInvoiceId,
      'productId': seedProductId,
      'quantity': 2,
      'unitPrice': 25,
      'lineTotal': 50,
    });

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
              productId: seedProductId,
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
    await pushAll();

    final postResult = await SalesInvoicePostLocalService(
      databaseService: databaseService,
    ).postDraft(invoiceId: originalInvoiceId);
    expect(postResult.ok, isTrue);
    await pushAll();
  }

  Future<void> seedLocalReturnDraft() async {
    final db = await databaseService.database;
    await db.insert('salesReturns', {
      'id': returnId,
      'organizationId': companyId,
      'branchId': branchId,
      'customerId': customerId,
      'originalInvoiceId': originalInvoiceId,
      'returnDate': DateTime.now().toIso8601String(),
      'total': 50.0,
      'refundPaymentType': 'cash',
      'returnStatus': 'draft',
      'createdBy': userId,
      'discountAmount': 0,
      'taxPercent': 0,
      'lineSubtotal': 50.0,
      'paidAmount': 0,
      'transactionVersion': 0,
      'rowVersion': 1,
    });
    await db.insert('salesReturnItems', {
      'id': returnLineId,
      'returnId': returnId,
      'productId': seedProductId,
      'quantity': 2,
      'unitPrice': 25,
      'lineTotal': 50,
    });
  }

  Future<void> enqueueReturnDraftCreate() async {
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
          lineSubtotal: 50,
          total: 50,
          lines: [
            salesReturnLinePayload(
              lineId: returnLineId,
              productId: seedProductId,
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
  }

  Future<int> readReturnSyncSequence() async {
    final db = await databaseService.database;
    final rows = await db.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [companyId, branchId, SalesReturnSyncConstants.scopeKey],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['last_pulled_sequence'] as int?) ?? 0;
  }

  Future<void> rewindReturnSyncSequence(int sequence) async {
    final db = await databaseService.database;
    final rows = await db.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [companyId, branchId, SalesReturnSyncConstants.scopeKey],
    );
    if (rows.isEmpty) {
      await db.insert('sync_meta', {
        'organization_id': companyId,
        'branch_id': branchId,
        'scope_key': SalesReturnSyncConstants.scopeKey,
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
      whereArgs: [companyId, branchId, SalesReturnSyncConstants.scopeKey],
    );
  }

  test('device A draft → post → push → cloud → pull → device B', () async {
    await pushCustomer();
    await seedAndSyncParentInvoice();

    await seedLocalReturnDraft();
    final seqBeforeCreate = await readReturnSyncSequence();
    await enqueueReturnDraftCreate();
    await pushAll();

    final postService = SalesReturnPostLocalService(
      databaseService: databaseService,
    );
    final postResult = await postService.postDraft(returnId: returnId);
    expect(postResult.ok, isTrue);

    final db = await databaseService.database;
    final postOutbox = await db.query(
      'sync_outbox',
      where: 'entity_id = ? AND operation = ?',
      whereArgs: [returnId, 'post'],
    );
    expect(postOutbox.length, 1);

    await pushAll();

    await db.delete('stockMovements', where: 'referenceId = ?', whereArgs: [returnId]);
    await db.delete('partnerLedger', where: 'referenceId = ?', whereArgs: [returnId]);
    await db.delete('salesReturnItems');
    await db.delete('salesReturns', where: 'id = ?', whereArgs: [returnId]);
    await db.update(
      'products',
      {'stockQty': 98.0},
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
    expect(stockBeforePull, 98.0);

    await rewindReturnSyncSequence(seqBeforeCreate);
    await pullReturnsOnly();

    final header = await db.query(
      'salesReturns',
      where: 'id = ?',
      whereArgs: [returnId],
      limit: 1,
    );
    expect(header, isNotEmpty);
    expect(header.first['returnStatus'], 'posted');
    expect(header.first['transactionVersion'], 1);
    expect(header.first['originalInvoiceId'], originalInvoiceId);

    final movements = await db.query(
      'stockMovements',
      where: 'referenceId = ?',
      whereArgs: [returnId],
    );
    expect(movements.length, 1);
    expect(
      movements.first['id'],
      SalesReturnPostIds.stockMovementId(returnId, returnLineId),
    );
    expect(movements.first['movementType'], 'in');

    final ledger = await db.query(
      'partnerLedger',
      where: 'referenceId = ?',
      whereArgs: [returnId],
    );
    expect(ledger.length, greaterThanOrEqualTo(2));

    final qtyAdded = movements.fold<double>(
      0,
      (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0),
    );
    final product = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [seedProductId],
      limit: 1,
    );
    expect(product.first['stockQty'], stockBeforePull! + qtyAdded);
    expect(qtyAdded, 2.0);

    final movementCountBefore = movements.length;
    final ledgerCountBefore = ledger.length;

    await pushAll();
    await pullReturnsOnly();

    final movementsAfter = await db.query(
      'stockMovements',
      where: 'referenceId = ?',
      whereArgs: [returnId],
    );
    final ledgerAfter = await db.query(
      'partnerLedger',
      where: 'referenceId = ?',
      whereArgs: [returnId],
    );
    expect(movementsAfter.length, movementCountBefore);
    expect(ledgerAfter.length, ledgerCountBefore);
  });
}
