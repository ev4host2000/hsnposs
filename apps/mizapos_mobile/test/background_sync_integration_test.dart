import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mizapos_mobile/models/entities.dart';
import 'package:mizapos_mobile/security/password_crypto.dart';
import 'package:mizapos_mobile/services/accounting_service.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_client.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_client_io.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_request.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_response.dart';
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
import 'package:mizapos_mobile/services/cloud/sync/background/models/sync_status_snapshot.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_connectivity_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_engine.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_logger.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_status_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/utils/app_data_paths.dart';

import 'package:mizapos_mobile/services/database_runtime_profile.dart';

import 'isolated_test_database.dart';
import 'sync_integration_test_helpers.dart';
import 'package:uuid/uuid.dart';

/// Background Sync scenarios A/B/C — requires backend on 127.0.0.1:8787.
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  const ownerPassword = 'MizaTest123!';

  late DatabaseService databaseService;
  late AccountingService accountingService;
  late CloudSecureStoragePlaceholder storage;

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
    accountingService = AccountingService(databaseService);
    storage = CloudSecureStoragePlaceholder();
    ProductSyncOutboxWriter.bindStorage(storage);

    final db = await databaseService.database;
    await db.delete(
      'sync_outbox',
      where: 'organization_id = ?',
      whereArgs: [companyId],
    );
    await db.delete(
      'products',
      where: 'organizationId = ?',
      whereArgs: [companyId],
    );

    await _seedLocalTenant(databaseService, companyId, branchId, ownerPassword);
    await _cloudLoginAndRegister(
      storage: storage,
      companyId: companyId,
      branchId: branchId,
      deviceId: seedDeviceId,
      installationId: installationId,
    );
    final loggedIn = await accountingService.login(
      'owner@store.com',
      ownerPassword,
    );
    expect(loggedIn, isNotNull);
  });

  test('A) offline add 10 products then online auto sync clears pending', () async {
    var online = false;
    final stack = await _buildSyncStack(
      databaseService: databaseService,
      accountingService: accountingService,
      storage: storage,
      onlineOverride: () async => online,
    );

    await _seedPendingOutboxRows(
      databaseService: databaseService,
      companyId: companyId,
      branchId: branchId,
      count: 10,
      installationId: installationId,
    );

    expect(await stack.status.countPending(), 10);

    online = true;
    final result = await stack.engine.run(trigger: SyncTrigger.connectivityRestored);
    expect(result.status, SyncRunStatus.success);
    expect(await stack.status.countPending(), 0);
  });

  test('B) push fails once then retries after network returns', () async {
    final recorder = _FlakyPushHttpClient(
      inner: const CloudHttpClientIo(),
      failPushAttempts: 1,
    );
    final stack = await _buildSyncStack(
      databaseService: databaseService,
      accountingService: accountingService,
      storage: storage,
      httpClient: recorder,
      onlineOverride: () async => true,
    );

    await _seedPendingOutboxRows(
      databaseService: databaseService,
      companyId: companyId,
      branchId: branchId,
      count: 1,
      installationId: installationId,
    );

    final result = await stack.engine.run(trigger: SyncTrigger.manual);
    expect(result.status, SyncRunStatus.success);
    expect(recorder.pushAttempts, greaterThan(1));
    expect(await stack.status.countPending(), 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('C) 120 pending outbox rows push in 3 batches', () async {
    final recorder = _RecordingPushHttpClient(inner: const CloudHttpClientIo());
    final stack = await _buildSyncStack(
      databaseService: databaseService,
      accountingService: accountingService,
      storage: storage,
      httpClient: recorder,
      onlineOverride: () async => true,
    );

    await _seedPendingOutboxRows(
      databaseService: databaseService,
      companyId: companyId,
      branchId: branchId,
      count: 120,
      installationId: installationId,
    );

    expect(await stack.status.countPending(), 120);

    final result = await stack.engine.run(trigger: SyncTrigger.manual);
    expect(result.status, SyncRunStatus.success);
    expect(recorder.pushCalls, 3);
    expect(recorder.pushEventCounts.every((c) => c <= 50), isTrue);
    expect(recorder.pushEventCounts.fold<int>(0, (a, b) => a + b), 120);
    expect(await stack.status.countPending(), 0);
  });

  test('D) pull fails once then retries successfully', () async {
    final recorder = _FlakyPullHttpClient(
      inner: const CloudHttpClientIo(),
      failPullAttempts: 1,
    );
    final stack = await _buildSyncStack(
      databaseService: databaseService,
      accountingService: accountingService,
      storage: storage,
      httpClient: recorder,
      onlineOverride: () async => true,
    );

    await _seedPendingOutboxRows(
      databaseService: databaseService,
      companyId: companyId,
      branchId: branchId,
      count: 1,
      installationId: installationId,
    );

    final result = await stack.engine.run(trigger: SyncTrigger.manual);
    expect(result.status, SyncRunStatus.success);
    expect(recorder.pullAttempts, greaterThan(1));
    expect(await stack.status.countPending(), 0);
  });

  test('E) pending outbox survives simulated app restart', () async {
    await _seedPendingOutboxRows(
      databaseService: databaseService,
      companyId: companyId,
      branchId: branchId,
      count: 5,
      installationId: installationId,
    );

    final stackAfterRestart = await _buildSyncStack(
      databaseService: databaseService,
      accountingService: accountingService,
      storage: storage,
      onlineOverride: () async => true,
    );

    expect(await stackAfterRestart.status.countPending(), 5);
    final result =
        await stackAfterRestart.engine.run(trigger: SyncTrigger.appStart);
    expect(result.status, SyncRunStatus.success);
    expect(await stackAfterRestart.status.countPending(), 0);
  });

  test('F) concurrent engine runs are serialized', () async {
    final stack = await _buildSyncStack(
      databaseService: databaseService,
      accountingService: accountingService,
      storage: storage,
      onlineOverride: () async => true,
    );

    await _seedPendingOutboxRows(
      databaseService: databaseService,
      companyId: companyId,
      branchId: branchId,
      count: 3,
      installationId: installationId,
    );

    final results = await Future.wait([
      stack.engine.run(trigger: SyncTrigger.manual),
      stack.engine.run(trigger: SyncTrigger.manual),
    ]);

    expect(
      results.where((r) => r.status == SyncRunStatus.skippedAlreadyRunning),
      hasLength(1),
    );
    expect(await stack.status.countPending(), 0);
  });
}

class _SyncTestStack {
  _SyncTestStack({
    required this.engine,
    required this.status,
  });

  final SyncEngine engine;
  final SyncStatusService status;
}

Future<_SyncTestStack> _buildSyncStack({
  required DatabaseService databaseService,
  required AccountingService accountingService,
  required CloudSecureStoragePlaceholder storage,
  required Future<bool> Function() onlineOverride,
  CloudHttpClient? httpClient,
}) async {
  final config = CloudConfig.development();
  final apiClient = CloudApiClient(
    httpClient: httpClient ?? const CloudHttpClientIo(),
    config: config,
    storage: storage,
  );
  final repository = ProductsSyncRepository(
    productsSyncApi: ProductsSyncApi(apiClient: apiClient, config: config),
    databaseService: databaseService,
  );
  final status = SyncStatusService(
    databaseService: databaseService,
    accountingService: accountingService,
    storage: storage,
  );
  final connectivity = SyncConnectivityService(onlineOverride: onlineOverride);
  final engine = SyncEngine(
    pushWorker: ProductsPushWorker(repository: repository),
    pullWorker: ProductsPullWorker(repository: repository),
    statusService: status,
    connectivityService: connectivity,
    logger: SyncLogger(databaseService: databaseService),
    contextResolver: SyncContextResolver(
      storage: storage,
      accountingService: accountingService,
      databaseService: databaseService,
    ),
  );
  return _SyncTestStack(engine: engine, status: status);
}

class _RecordingPushHttpClient implements CloudHttpClient {
  _RecordingPushHttpClient({required this.inner});

  final CloudHttpClient inner;
  int pushCalls = 0;
  final List<int> pushEventCounts = [];

  @override
  Future<CloudHttpResponse> delete(CloudHttpRequest request) =>
      inner.delete(request);

  @override
  Future<CloudHttpResponse> download(CloudHttpRequest request) =>
      inner.download(request);

  @override
  Future<CloudHttpResponse> get(CloudHttpRequest request) => inner.get(request);

  @override
  Future<CloudHttpResponse> patch(CloudHttpRequest request) =>
      inner.patch(request);

  @override
  Future<CloudHttpResponse> post(CloudHttpRequest request) async {
    if (request.path.contains('/sync/push/products')) {
      pushCalls++;
      final body = request.body;
      if (body is Map) {
        final events = body['events'];
        if (events is List) {
          pushEventCounts.add(events.length);
        }
      } else if (body is String) {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['events'] is List) {
          pushEventCounts.add((decoded['events'] as List).length);
        }
      }
    }
    return inner.post(request);
  }

  @override
  Future<CloudHttpResponse> put(CloudHttpRequest request) => inner.put(request);

  @override
  Future<CloudHttpResponse> upload(CloudHttpRequest request) =>
      inner.upload(request);
}

class _FlakyPullHttpClient implements CloudHttpClient {
  _FlakyPullHttpClient({
    required this.inner,
    required this.failPullAttempts,
  });

  final CloudHttpClient inner;
  final int failPullAttempts;
  int pullAttempts = 0;

  @override
  Future<CloudHttpResponse> delete(CloudHttpRequest request) =>
      inner.delete(request);

  @override
  Future<CloudHttpResponse> download(CloudHttpRequest request) =>
      inner.download(request);

  @override
  Future<CloudHttpResponse> get(CloudHttpRequest request) async {
    if (request.path.contains('/sync/pull/products')) {
      pullAttempts++;
      if (pullAttempts <= failPullAttempts) {
        throw const SocketException('simulated offline during pull');
      }
    }
    return inner.get(request);
  }

  @override
  Future<CloudHttpResponse> patch(CloudHttpRequest request) =>
      inner.patch(request);

  @override
  Future<CloudHttpResponse> post(CloudHttpRequest request) =>
      inner.post(request);

  @override
  Future<CloudHttpResponse> put(CloudHttpRequest request) => inner.put(request);

  @override
  Future<CloudHttpResponse> upload(CloudHttpRequest request) =>
      inner.upload(request);
}

class _FlakyPushHttpClient implements CloudHttpClient {
  _FlakyPushHttpClient({
    required this.inner,
    required this.failPushAttempts,
  });

  final CloudHttpClient inner;
  final int failPushAttempts;
  int pushAttempts = 0;

  @override
  Future<CloudHttpResponse> delete(CloudHttpRequest request) =>
      inner.delete(request);

  @override
  Future<CloudHttpResponse> download(CloudHttpRequest request) =>
      inner.download(request);

  @override
  Future<CloudHttpResponse> get(CloudHttpRequest request) => inner.get(request);

  @override
  Future<CloudHttpResponse> patch(CloudHttpRequest request) =>
      inner.patch(request);

  @override
  Future<CloudHttpResponse> post(CloudHttpRequest request) async {
    if (request.path.contains('/sync/push/products')) {
      pushAttempts++;
      if (pushAttempts <= failPushAttempts) {
        throw const SocketException('simulated offline during push');
      }
    }
    return inner.post(request);
  }

  @override
  Future<CloudHttpResponse> put(CloudHttpRequest request) => inner.put(request);

  @override
  Future<CloudHttpResponse> upload(CloudHttpRequest request) =>
      inner.upload(request);
}

Future<void> _seedPendingOutboxRows({
  required DatabaseService databaseService,
  required String companyId,
  required String branchId,
  required int count,
  required String installationId,
}) async {
  final db = await databaseService.database;
  final now = DateTime.now().toIso8601String();
  const uuid = Uuid();
  for (var i = 0; i < count; i++) {
    final productId = uuid.v4();
    final outboxId = uuid.v4();
    await db.insert('sync_outbox', {
      'id': outboxId,
      'organization_id': companyId,
      'branch_id': branchId,
      'entity_type': 'product',
      'entity_id': productId,
      'operation': 'create',
      'sync_state': 'pending',
      'payload_json': jsonEncode({
        'id': productId,
        'company_id': companyId,
        'branch_id': branchId,
        'name': 'Batch seed $i',
        'sale_price': 1.0,
        'cost_price': 0.5,
        'stock_qty': 1.0,
      }),
      'client_row_version': i + 1,
      'idempotency_key': '$installationId:$productId:create:$outboxId',
      'installation_id': installationId,
      'created_at': now,
      'updated_at': now,
    });
  }
}

Future<void> _cloudLoginAndRegister({
  required CloudSecureStoragePlaceholder storage,
  required String companyId,
  required String branchId,
  required String deviceId,
  required String installationId,
}) async {
  final config = CloudConfig.development();
  final apiClient = CloudApiClient(
    httpClient: const CloudHttpClientIo(),
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
    LoginRequest(
      username: 'owner@store.com',
      password: 'MizaTest123!',
      companyId: companyId,
      branchId: branchId,
      deviceId: deviceId,
      installationId: installationId,
    ),
  );
  await DeviceManager(
    deviceService: DeviceService(
      repository: DeviceRepository(
        deviceApi: DeviceApi(apiClient: apiClient, config: config),
        storage: storage,
      ),
      storage: storage,
    ),
  ).register(companyId: companyId, branchId: branchId);
}

Future<void> _seedLocalTenant(
  DatabaseService dbService,
  String organizationId,
  String branchId,
  String ownerPassword,
) async {
  final db = await dbService.database;
  final ownerId = '990e8400-e29b-41d4-a716-446655440004';

  await db.insert(
    'organizations',
    {
      'id': organizationId,
      'name': 'Demo Store',
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  await db.insert(
    'branches',
    {
      'id': branchId,
      'organizationId': organizationId,
      'name': 'Main Branch',
      'code': 'MAIN',
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  await db.insert(
    'users',
    {
      'id': ownerId,
      'organizationId': organizationId,
      'branchId': branchId,
      'fullName': 'Store Owner',
      'username': 'owner@store.com',
      'email': 'owner@store.com',
      'password': PasswordCrypto.hash(ownerPassword),
      'role': 'owner',
      'accountStatus': 'active',
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
