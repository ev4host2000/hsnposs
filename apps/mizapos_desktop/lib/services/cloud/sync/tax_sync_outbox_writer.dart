import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/tax_update_contract.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/device_binding.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Dual-mode outbox writer for tax (M1 Full default, Patch optional).
class TaxSyncOutboxWriter {
  TaxSyncOutboxWriter._();

  static CloudSecureStorage? _storage;
  static const Uuid _uuid = Uuid();

  static void bindStorage(CloudSecureStorage storage) {
    _storage = storage;
  }

  static CloudSecureStorage? get storage => _storage;

  static bool isTaxEntityType(String entityType) {
    return entityType == CatalogSyncConstants.entityTypeTax;
  }

  /// Records create / update / patch / delete — skips silently without device context.
  static Future<void> record({
    required String entityType,
    required String operation,
    required String entityId,
    required String organizationId,
    required String branchId,
    Map<String, dynamic>? payload,
    DatabaseService? databaseService,
    CloudSecureStorage? storage,
    DatabaseExecutor? executor,
  }) async {
    if (!isTaxEntityType(entityType)) return;
    if (operation != 'create' &&
        operation != 'update' &&
        operation != 'delete' &&
        operation != 'patch') {
      return;
    }

    final db = executor ??
        await (databaseService ?? DatabaseService()).database;
    final installationId = await DeviceBinding.readInstallationId();
    final deviceId = await _resolveDeviceId(
      db,
      storage ?? _storage,
      installationId,
    );
    if (deviceId.isEmpty) return;

    final outboxId = _uuid.v4();
    Map<String, dynamic>? fullPayload = payload;
    String? name;
    double? percent;
    bool? isDefault;
    int? sortOrder;
    Map<String, Object?>? baseSnapshot;
    int? cloudRowVersion;

    if (operation == 'delete') {
      fullPayload ??= taxEntityCloudPayload(
        id: entityId,
        organizationId: organizationId,
        branchId: branchId,
        name: '',
        percent: 0,
        deleted: true,
      );
    } else {
      final loaded = await _loadTax(
        db,
        entityId: entityId,
        organizationId: organizationId,
        branchId: branchId,
      );
      name = loaded.name;
      percent = loaded.percent;
      isDefault = loaded.isDefault;
      sortOrder = loaded.sortOrder;
      if (fullPayload == null && name == null) return;

      final meta = await _loadCloudMeta(db, entityId);
      cloudRowVersion = meta.cloudRowVersion;
      baseSnapshot = meta.snapshot;
    }

    final intent = TaxUpdateContract.buildIntent(
      operation: operation == 'patch' ? 'update' : operation,
      entityId: entityId,
      organizationId: organizationId,
      branchId: branchId,
      operationId: outboxId,
      name: name,
      percent: percent,
      isDefault: isDefault,
      sortOrder: sortOrder,
      fullPayload: fullPayload,
      baseSnapshot: baseSnapshot,
      cloudRowVersion: cloudRowVersion,
    );

    if (intent.skipEnqueue) {
      return;
    }

    final clientRowVersion = intent.clientRowVersionHint ??
        await _nextClientRowVersion(db, entityId);
    final idempotencyKey =
        '$deviceId:$entityId:${intent.operation}:$outboxId';
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'sync_outbox',
      {
        'id': outboxId,
        'organization_id': organizationId,
        'branch_id': branchId,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': intent.operation,
        'sync_state': CatalogSyncConstants.syncStatePending,
        'payload_json': jsonEncode(intent.payload),
        'client_row_version': clientRowVersion,
        'idempotency_key': idempotencyKey,
        'installation_id': installationId,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<String> _resolveDeviceId(
    DatabaseExecutor db,
    CloudSecureStorage? storage,
    String installationId,
  ) async {
    final fromStorage = await storage?.readDeviceId();
    if (fromStorage != null && fromStorage.trim().isNotEmpty) {
      return fromStorage.trim();
    }

    final selfRows = await db.query(
      'sync_devices',
      columns: const ['cloud_device_id'],
      where: 'is_self = 1 AND cloud_device_id IS NOT NULL AND cloud_device_id != ?',
      whereArgs: [''],
      limit: 1,
    );
    if (selfRows.isNotEmpty) {
      final id = (selfRows.first['cloud_device_id'] ?? '').toString().trim();
      if (id.isNotEmpty) return id;
    }

    return installationId;
  }

  static Future<int> _nextClientRowVersion(
    DatabaseExecutor db,
    String entityId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT MAX(client_row_version) AS m FROM sync_outbox WHERE entity_id = ?',
      [entityId],
    );
    final current = (rows.first['m'] as int?) ?? 0;
    return current + 1;
  }

  static Future<({
    int? cloudRowVersion,
    Map<String, Object?> snapshot,
  })> _loadCloudMeta(
    DatabaseExecutor db,
    String entityId,
  ) async {
    const table = 'taxes';
    final hasVersion = await _hasColumn(db, table, 'cloudRowVersion');
    if (!hasVersion) {
      return (cloudRowVersion: null, snapshot: <String, Object?>{});
    }
    final rows = await db.query(
      table,
      columns: const ['cloudRowVersion', 'cloudCatalogSnapshotJson'],
      where: 'id = ?',
      whereArgs: [entityId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return (cloudRowVersion: null, snapshot: <String, Object?>{});
    }
    final row = rows.first;
    final ver = row['cloudRowVersion'];
    final cloudRowVersion = ver is int
        ? ver
        : int.tryParse(ver?.toString() ?? '');
    return (
      cloudRowVersion: cloudRowVersion,
      snapshot: TaxUpdateContract.decodeSnapshot(
        row['cloudCatalogSnapshotJson']?.toString(),
      ),
    );
  }

  static Future<({
    String? name,
    double? percent,
    bool? isDefault,
    int? sortOrder,
  })> _loadTax(
    DatabaseExecutor db, {
    required String entityId,
    required String organizationId,
    required String branchId,
  }) async {
    final rows = await db.query(
      'taxes',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [entityId, organizationId, branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return (
        name: null,
        percent: null,
        isDefault: null,
        sortOrder: null,
      );
    }
    final row = rows.first;
    final percentRaw = row['percent'];
    final percent = percentRaw is num
        ? percentRaw.toDouble()
        : double.tryParse(percentRaw?.toString() ?? '') ?? 0.0;
    final isDefaultRaw = row['isDefault'];
    final isDefault = isDefaultRaw is bool
        ? isDefaultRaw
        : (isDefaultRaw is num
            ? isDefaultRaw != 0
            : (isDefaultRaw?.toString() == '1' ||
                isDefaultRaw?.toString().toLowerCase() == 'true'));
    final sort = row.containsKey('sortOrder')
        ? (row['sortOrder'] as num?)?.toInt() ?? 0
        : 0;
    return (
      name: (row['name'] ?? '').toString(),
      percent: percent,
      isDefault: isDefault,
      sortOrder: sort,
    );
  }

  static Future<bool> _hasColumn(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    for (final row in rows) {
      if ((row['name'] ?? '').toString() == column) return true;
    }
    return false;
  }
}
