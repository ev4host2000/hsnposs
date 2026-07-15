import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_client.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_request.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_response.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_config.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/partners_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_desktop/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_desktop/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_sync_registry.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_invoice_sync_service.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/transaction_walk_in_partners.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_desktop/services/database_runtime_profile.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Windows regression for the production `partner_not_found` Walk-in failure.
///
/// Uses the real Windows SQLite schema, outbox, partner/transaction registries
/// and push orchestrator. The deterministic HTTP boundary rejects an invoice
/// received before its Walk-in customer.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const deviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const userId = '990e8400-e29b-41d4-a716-446655440004';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';

  late Directory originalDirectory;
  late Directory isolatedDirectory;
  late DatabaseService databaseService;
  late CloudSecureStoragePlaceholder storage;
  late _WalkInOrderingCloud cloud;
  late ProductsSyncRepository productsRepository;
  late ProductsPushWorker pushWorker;
  late String invoiceId;
  late String lineId;
  late String walkInCustomerId;

  setUpAll(() async {
    originalDirectory = Directory.current;
    isolatedDirectory =
        await Directory.systemTemp.createTemp('mizapos_desktop_test_sqlite_');
    Directory.current = isolatedDirectory.path;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseRuntimeConfig.configureForTesting(
      profile: DatabaseRuntimeProfile.integrationTest,
      directory: isolatedDirectory.path,
    );
  });

  tearDownAll(() async {
    await DatabaseService().closeDatabase();
    DatabaseRuntimeConfig.resetForTesting();
    Directory.current = originalDirectory.path;
    try {
      await isolatedDirectory.delete(recursive: true);
    } on Object {
      // Best-effort test cleanup.
    }
  });

  setUp(() async {
    databaseService = DatabaseService();
    final db = await databaseService.database;
    for (final table in [
      'customers',
      'salesInvoices',
      'salesInvoiceItems',
      'sync_outbox',
      'stockMovements',
      'partnerLedger',
    ]) {
      await db.delete(table);
    }

    invoiceId = const Uuid().v4();
    lineId = const Uuid().v4();
    walkInCustomerId = TransactionWalkInPartners.walkInCustomerId(companyId);

    await db.delete('products', where: 'id = ?', whereArgs: [productId]);
    await db.insert(
      'products',
      {
        'id': productId,
        'organizationId': companyId,
        'branchId': branchId,
        'name': 'Windows Walk-in regression product',
        'salePrice': 20.0,
        'costPrice': 8.0,
        'stockQty': 100.0,
        'isHidden': 0,
        'isFrozen': 0,
        'isService': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await File(
      '${isolatedDirectory.path}${Platform.pathSeparator}.mizapos_device_id',
    ).writeAsString(installationId);

    storage = CloudSecureStoragePlaceholder();
    await storage.writeAccessToken('test-access-token');
    await storage.writeDeviceId(deviceId);
    await storage.writeInstallationId(installationId);
    await storage.writeCompanyId(companyId);
    await storage.writeBranchId(branchId);
    await storage.writeUserId(userId);

    TransactionSyncOutboxWriter.bindStorage(storage);
    CatalogSyncOutboxWriter.bindStorage(storage);

    cloud = _WalkInOrderingCloud(walkInCustomerId: walkInCustomerId);
    final config = CloudConfig.development(baseUrl: 'http://fake.local');
    final apiClient = CloudApiClient(
      httpClient: cloud,
      config: config,
      storage: storage,
    );
    final partnersRegistry = PartnersSyncRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    final TransactionRegistry transactionRegistry =
        SalesInvoiceSyncRegistry.createRegistered(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    productsRepository = ProductsSyncRepository(
      productsSyncApi: ProductsSyncApi(
        apiClient: apiClient,
        config: config,
      ),
      databaseService: databaseService,
    );
    pushWorker = ProductsPushWorker(
      repository: productsRepository,
      partnersRegistry: partnersRegistry,
      transactionRegistry: transactionRegistry,
    );
  });

  test(
    'Windows pushes Walk-in customer before invoice without partner_not_found',
    () async {
      final result = await TransactionInvoiceSyncService(
        databaseService: databaseService,
      ).createSalesDraftAndPost(
        invoiceId: invoiceId,
        organizationId: companyId,
        branchId: branchId,
        userId: userId,
        customerId: null,
        invoiceDate: DateTime.utc(2026, 7, 14),
        paymentType: 'cash',
        lineSubtotal: 40,
        discountAmount: 0,
        taxPercent: 0,
        total: 40,
        paidAmount: 40,
        notes: null,
        invoiceNumber: 1,
        lines: [
          (
            lineId: lineId,
            productId: productId,
            quantity: 2.0,
            unitPrice: 20.0,
          ),
        ],
      );
      expect(
        result.ok,
        isTrue,
        reason: '${result.failureCode}: ${result.failureMessage}',
      );

      final db = await databaseService.database;
      final customerOutboxBefore = await db.query(
        'sync_outbox',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [
          PartnersSyncConstants.entityTypeCustomer,
          walkInCustomerId,
        ],
      );
      expect(customerOutboxBefore, hasLength(1));
      expect(customerOutboxBefore.single['operation'], 'create');
      expect(customerOutboxBefore.single['sync_state'], 'pending');

      final invoiceOutboxBefore = await db.query(
        'sync_outbox',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [SalesInvoiceSyncConstants.entityType, invoiceId],
      );
      expect(invoiceOutboxBefore, isNotEmpty);
      expect(await productsRepository.countPendingPartners(), 1);

      await pushWorker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: deviceId,
      );

      expect(cloud.partnerNotFoundCount, 0);
      expect(cloud.pushOrder, isNotEmpty);
      expect(cloud.pushOrder.first, 'customer');
      expect(cloud.pushOrder.where((e) => e == 'sales_invoice'), isNotEmpty);
      expect(
        cloud.pushOrder.indexOf('customer'),
        lessThan(cloud.pushOrder.indexOf('sales_invoice')),
      );

      final customerOutboxAfter = await db.query(
        'sync_outbox',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [
          PartnersSyncConstants.entityTypeCustomer,
          walkInCustomerId,
        ],
      );
      expect(customerOutboxAfter.single['sync_state'], 'synced');
      expect(customerOutboxAfter.single['last_sync_error'], isNull);

      final invoiceOutboxAfter = await db.query(
        'sync_outbox',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [SalesInvoiceSyncConstants.entityType, invoiceId],
      );
      expect(invoiceOutboxAfter, isNotEmpty);
      for (final row in invoiceOutboxAfter) {
        expect(row['sync_state'], 'synced');
        expect(row['last_sync_error'], isNull);
      }
    },
  );
}

class _WalkInOrderingCloud implements CloudHttpClient {
  _WalkInOrderingCloud({required this.walkInCustomerId});

  final String walkInCustomerId;
  final List<String> pushOrder = [];
  bool _customerExists = false;
  int partnerNotFoundCount = 0;

  @override
  Future<CloudHttpResponse> post(CloudHttpRequest request) async {
    final body = _bodyMap(request.body);
    final events = (body['events'] as List?) ?? const [];
    final batchId = (body['batch_id'] ?? 'test-batch').toString();

    if (request.path.contains('/sync/push/customers')) {
      pushOrder.add('customer');
      final containsWalkIn = events.any((event) {
        if (event is! Map) return false;
        final payload = event['payload_json'];
        return payload is Map && payload['id'] == walkInCustomerId;
      });
      _customerExists = containsWalkIn;
      return _accepted(batchId, events.length);
    }

    if (request.path.contains('/sync/push/sales-invoices')) {
      pushOrder.add('sales_invoice');
      if (!_customerExists) {
        partnerNotFoundCount++;
        return _partnerNotFound(batchId, events);
      }
      return _accepted(batchId, events.length);
    }

    return _accepted(batchId, events.length);
  }

  CloudHttpResponse _accepted(String batchId, int accepted) {
    return CloudHttpResponse(
      statusCode: 202,
      isSuccess: true,
      body: jsonEncode({
        'ok': true,
        'data': {
          'batch_id': batchId,
          'status': 'accepted',
          'accepted': accepted,
          'duplicates': 0,
          'rejected': 0,
          'rejected_events': const [],
        },
      }),
    );
  }

  CloudHttpResponse _partnerNotFound(String batchId, List<Object?> events) {
    final rejectedEvents = events.map((event) {
      final map = event is Map ? event : const {};
      return {
        'outbox_id': (map['outbox_id'] ?? '').toString(),
        'error_code': 'partner_not_found',
        'message': 'Walk-in customer is not on cloud',
      };
    }).toList();
    return CloudHttpResponse(
      statusCode: 422,
      isSuccess: false,
      body: jsonEncode({
        'ok': false,
        'data': {
          'batch_id': batchId,
          'status': 'partial',
          'accepted': 0,
          'duplicates': 0,
          'rejected': rejectedEvents.length,
          'rejected_events': rejectedEvents,
        },
        'error': {
          'code': 'partial_reject',
          'message': 'Some events rejected',
          'status_code': 422,
        },
      }),
    );
  }

  Map<String, dynamic> _bodyMap(Object? body) {
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    if (body is String) {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  Never _unexpected(String method, CloudHttpRequest request) {
    throw StateError('Unexpected $method request: ${request.path}');
  }

  @override
  Future<CloudHttpResponse> delete(CloudHttpRequest request) async =>
      _unexpected('DELETE', request);

  @override
  Future<CloudHttpResponse> download(CloudHttpRequest request) async =>
      _unexpected('DOWNLOAD', request);

  @override
  Future<CloudHttpResponse> get(CloudHttpRequest request) async =>
      _unexpected('GET', request);

  @override
  Future<CloudHttpResponse> patch(CloudHttpRequest request) async =>
      _unexpected('PATCH', request);

  @override
  Future<CloudHttpResponse> put(CloudHttpRequest request) async =>
      _unexpected('PUT', request);

  @override
  Future<CloudHttpResponse> upload(CloudHttpRequest request) async =>
      _unexpected('UPLOAD', request);
}
