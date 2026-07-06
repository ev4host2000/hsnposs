import 'dart:io';

import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage_placeholder.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/requests/catalog_pull_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_page.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

import 'isolated_test_database.dart';

/// Shared tenant identifiers for live sync integration/benchmark tests.
abstract final class SyncIntegrationTestTenant {
  static const companyId = '550e8400-e29b-41d4-a716-446655440000';
  static const branchId = '660e8400-e29b-41d4-a716-446655440001';
  static const seedDeviceId = '770e8400-e29b-41d4-a716-446655440002';
  static const installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  static const userId = '990e8400-e29b-41d4-a716-446655440004';
  static const seedProductId = 'a100e840-e29b-41d4-a716-446655440020';
  static const seedCustomerId = 'c100e840-e29b-41d4-a716-446655440040';
  static const seedSupplierId = 'd100e840-e29b-41d4-a716-446655440050';
}

/// Clears cloud `sync_changelog` / queue / volatile rows for the test tenant.
Future<void> resetCloudSyncTestTenant({
  String databaseName = 'mizacloud',
  String postgresUser = 'postgres',
}) async {
  final psql = _findPsqlExecutable();
  if (psql == null) {
    throw StateError(
      'psql not found — required to reset cloud sync_changelog for integration tests.',
    );
  }

  final sqlPath = _cloudTestResetSqlPath();
  if (!File(sqlPath).existsSync()) {
    throw StateError('Missing cloud test reset SQL at $sqlPath');
  }

  final result = await Process.run(
    psql,
    [
      '-U',
      postgresUser,
      '-d',
      databaseName,
      '-v',
      'ON_ERROR_STOP=1',
      '-f',
      sqlPath,
    ],
    environment: Platform.environment,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'resetCloudSyncTestTenant failed (${result.exitCode}): ${result.stderr}',
    );
  }
}

/// Serializes cloud tenant mutations across parallel Flutter test isolates.
Future<T> withCloudIntegrationTestLock<T>(Future<T> Function() action) async {
  final lockPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}miza_cloud_integration.lock';
  final lockFile = File(lockPath);

  for (var attempt = 0; attempt < 600; attempt++) {
    RandomAccessFile? handle;
    try {
      handle = await lockFile.open(mode: FileMode.write);
      await handle.lock(FileLock.exclusive);
      try {
        return await action();
      } finally {
        await handle.unlock();
        await handle.close();
      }
    } on FileSystemException {
      await handle?.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  throw StateError('Timed out waiting for cloud integration test lock');
}

/// Deletes the isolated SQLite file and reopens an empty schema.
Future<void> resetLocalSyncTestDatabase(DatabaseService databaseService) async {
  await resetIsolatedTestDatabaseFile();
  await databaseService.database;
}

/// Writes `sync_meta.last_pulled_sequence` for one scope.
Future<void> setSyncMetaLastPulledSequence(
  Database db, {
  required String organizationId,
  required String branchId,
  required String scopeKey,
  required int sequence,
}) async {
  final now = DateTime.now().toIso8601String();
  final existing = await db.query(
    'sync_meta',
    where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
    whereArgs: [organizationId, branchId, scopeKey],
    limit: 1,
  );
  if (existing.isEmpty) {
    await db.insert('sync_meta', {
      'organization_id': organizationId,
      'branch_id': branchId,
      'scope_key': scopeKey,
      'last_pulled_sequence': sequence,
      'last_pushed_sequence': 0,
      'cloud_version_catalog': 0,
      'cloud_version_invoices': 0,
      'cloud_version_users': 0,
      'last_pulled_at': now,
      'updated_at': now,
    });
    return;
  }
  await db.update(
    'sync_meta',
    {
      'last_pulled_sequence': sequence,
      'updated_at': now,
    },
    where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
    whereArgs: [organizationId, branchId, scopeKey],
  );
}

/// Skips historical cloud changelog by advancing local pull cursor to tail.
Future<int> advanceSyncMetaToCloudTail({
  required CloudApiClient apiClient,
  required Database db,
  required String organizationId,
  required String branchId,
  required String scopeKey,
  required String pullPath,
}) async {
  final syncApi = CatalogEntitySyncApi(
    apiClient: apiClient,
    pullPath: pullPath,
    pushPath: pullPath.replaceFirst('/pull/', '/push/'),
  );
  final response = await syncApi.pull(
    CatalogPullRequest(
      companyId: organizationId,
      branchId: branchId,
      sinceSequence: 999999999,
      limit: 1,
    ),
  );
  if (!response.ok) {
    throw StateError(
      'advanceSyncMetaToCloudTail pull failed: ${response.error?.code}',
    );
  }
  final tail = readLastSequence(0, response.meta);
  await setSyncMetaLastPulledSequence(
    db,
    organizationId: organizationId,
    branchId: branchId,
    scopeKey: scopeKey,
    sequence: tail,
  );
  return tail;
}

Future<void> prepareSyncIntegrationTest({
  required DatabaseService databaseService,
  bool resetCloud = true,
}) async {
  await withCloudIntegrationTestLock(() async {
    if (resetCloud) {
      await resetCloudSyncTestTenant();
    }
    await resetLocalSyncTestDatabase(databaseService);
  });
}

/// Seeds a bench product locally and pushes it to cloud (required after tenant reset).
Future<void> ensureTestProductOnCloud({
  required DatabaseService databaseService,
  required CloudSecureStoragePlaceholder storage,
  required ProductsPushWorker pushWorker,
  required String companyId,
  required String branchId,
  required String deviceId,
  required String productId,
  double stockQty = 1000000,
  String name = 'Sync Bench Product',
}) async {
  ProductSyncOutboxWriter.bindStorage(storage);
  final db = await databaseService.database;
  await db.insert(
    'products',
    {
      'id': productId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': name,
      'salePrice': 10.0,
      'costPrice': 5.0,
      'stockQty': stockQty,
      'isHidden': 0,
      'isFrozen': 0,
      'isService': 0,
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  await ProductSyncOutboxWriter.record(
    operation: 'create',
    productId: productId,
    organizationId: companyId,
    branchId: branchId,
    databaseService: databaseService,
    storage: storage,
  );
  await withCloudIntegrationTestLock(() async {
    await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: deviceId,
    );
  });
}

/// Seeds a bench customer locally and pushes it to cloud (required after tenant reset).
Future<void> ensureTestCustomerOnCloud({
  required DatabaseService databaseService,
  required CloudSecureStoragePlaceholder storage,
  required ProductsPushWorker pushWorker,
  required String companyId,
  required String branchId,
  required String deviceId,
  required String customerId,
  String name = 'Sync Bench Customer',
}) async {
  CatalogSyncOutboxWriter.bindStorage(storage);
  final db = await databaseService.database;
  await db.insert(
    'customers',
    {
      'id': customerId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': name,
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
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
      name: name,
    ),
    databaseService: databaseService,
    storage: storage,
  );
  await withCloudIntegrationTestLock(() async {
    await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: deviceId,
    );
  });
}

/// Seeds a bench supplier locally and pushes it to cloud (required after tenant reset).
Future<void> ensureTestSupplierOnCloud({
  required DatabaseService databaseService,
  required CloudSecureStoragePlaceholder storage,
  required ProductsPushWorker pushWorker,
  required String companyId,
  required String branchId,
  required String deviceId,
  required String supplierId,
  String name = 'Sync Bench Supplier',
}) async {
  CatalogSyncOutboxWriter.bindStorage(storage);
  final db = await databaseService.database;
  await db.insert(
    'suppliers',
    {
      'id': supplierId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': name,
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
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
      name: name,
    ),
    databaseService: databaseService,
    storage: storage,
  );
  await withCloudIntegrationTestLock(() async {
    await pushWorker.run(
      companyId: companyId,
      branchId: branchId,
      deviceId: deviceId,
    );
  });
}

String? _findPsqlExecutable() {
  const candidates = [
    'psql',
    r'D:\MizaPos\cloud\api\tools\pgsql\pgsql\bin\psql.exe',
    r'C:\Program Files\PostgreSQL\17\bin\psql.exe',
    r'C:\Program Files\PostgreSQL\16\bin\psql.exe',
    r'C:\Program Files\PostgreSQL\15\bin\psql.exe',
  ];
  for (final candidate in candidates) {
    if (candidate == 'psql') {
      try {
        final result = Process.runSync('where', ['psql']);
        if (result.exitCode == 0) return 'psql';
      } on Object {
        continue;
      }
    } else if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

String _cloudTestResetSqlPath() {
  final fromEnv = Platform.environment['MIZA_CLOUD_TEST_RESET_SQL']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return fromEnv;
  }
  final cwd = Directory.current.path;
  final candidates = [
    r'd:\MizaPos\cloud\api\database\test_reset_sync_tenant.sql',
    '$cwd${Platform.pathSeparator}cloud${Platform.pathSeparator}api${Platform.pathSeparator}database${Platform.pathSeparator}test_reset_sync_tenant.sql',
    '$cwd${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}cloud${Platform.pathSeparator}api${Platform.pathSeparator}database${Platform.pathSeparator}test_reset_sync_tenant.sql',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw StateError('Could not locate test_reset_sync_tenant.sql');
}
