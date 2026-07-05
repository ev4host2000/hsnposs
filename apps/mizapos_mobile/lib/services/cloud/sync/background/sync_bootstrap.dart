import 'package:flutter/foundation.dart';
import 'package:mizapos_mobile/services/accounting_service.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_client_io.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_production.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_api_auth_coordinator.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_connectivity_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_engine.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_logger.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_scheduler.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_status_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_invoice_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_return_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_sync_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/database_service.dart';

/// تهيئة Background Sync — بدون تعديل Auth/Device Registration workers.
class BackgroundSyncBootstrap {
  BackgroundSyncBootstrap._();

  static SyncScheduler? _scheduler;
  static SyncStatusService? _statusService;
  static SyncLogger? _logger;
  static CloudSecureStorage? _storage;

  static SyncScheduler? get scheduler => _scheduler;
  static SyncStatusService? get statusService => _statusService;
  static SyncLogger? get logger => _logger;
  static CloudSecureStorage? get storage => _storage;

  static Future<void> initialize({
    required DatabaseService databaseService,
    required AccountingService accountingService,
    CloudSecureStorage? storage,
    CloudConfig? config,
  }) async {
    if (_scheduler != null) return;

    _storage = storage ?? await CloudSecureStorageProduction.create();
    ProductSyncOutboxWriter.bindStorage(_storage!);
    CatalogSyncOutboxWriter.bindStorage(_storage!);
    TransactionSyncOutboxWriter.bindStorage(_storage!);

    final cloudConfig = config ??
        (kDebugMode ? CloudConfig.development() : CloudConfig.production());

    const httpClient = CloudHttpClientIo();
    final authCoordinator = CloudApiAuthCoordinator(
      httpClient: httpClient,
      config: cloudConfig,
      storage: _storage!,
    );

    final apiClient = CloudApiClient(
      httpClient: httpClient,
      config: cloudConfig,
      storage: _storage!,
      authCoordinator: authCoordinator,
    );

    final catalogRegistry = CatalogSyncRegistry.create(
      apiClient: apiClient,
      config: cloudConfig,
      databaseService: databaseService,
    );

    final partnersRegistry = PartnersSyncRegistry.create(
      apiClient: apiClient,
      config: cloudConfig,
      databaseService: databaseService,
    );

    final transactionRegistry = TransactionRegistry.create(
      apiClient: apiClient,
      config: cloudConfig,
      databaseService: databaseService,
    );
    SalesInvoiceSyncRegistry.registerWith(registry: transactionRegistry);
    PurchaseInvoiceSyncRegistry.registerWith(registry: transactionRegistry);
    SalesReturnSyncRegistry.registerWith(registry: transactionRegistry);
    PurchaseReturnSyncRegistry.registerWith(registry: transactionRegistry);

    final syncRepository = ProductsSyncRepository(
      productsSyncApi: ProductsSyncApi(apiClient: apiClient, config: cloudConfig),
      databaseService: databaseService,
    );

    final pushWorker = ProductsPushWorker(
      repository: syncRepository,
      catalogRegistry: catalogRegistry,
      partnersRegistry: partnersRegistry,
      transactionRegistry: transactionRegistry,
    );
    final pullWorker = ProductsPullWorker(
      repository: syncRepository,
      catalogRegistry: catalogRegistry,
      partnersRegistry: partnersRegistry,
      transactionRegistry: transactionRegistry,
    );

    _logger = SyncLogger(
      databaseService: databaseService,
      contextProvider: () async {
        final deviceId = await _storage!.readDeviceId();
        return {
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
          if (apiClient.lastRequestId != null)
            'request_id': apiClient.lastRequestId,
        };
      },
    );
    _statusService = SyncStatusService(
      databaseService: databaseService,
      accountingService: accountingService,
      storage: _storage,
    );

    final connectivity = SyncConnectivityService();
    final contextResolver = SyncContextResolver(
      storage: _storage!,
      accountingService: accountingService,
      databaseService: databaseService,
    );

    final engine = SyncEngine(
      pushWorker: pushWorker,
      pullWorker: pullWorker,
      statusService: _statusService!,
      connectivityService: connectivity,
      logger: _logger!,
      contextResolver: contextResolver,
    );

    _scheduler = SyncScheduler(
      engine: engine,
      statusService: _statusService!,
      connectivityService: connectivity,
    );

    await _scheduler!.start();
  }

  static void onAppResumed() {
    _scheduler?.onAppResumed();
  }

  static Future<void> dispose() async {
    _scheduler?.dispose();
    _scheduler = null;
    _statusService = null;
    _logger = null;
  }
}
