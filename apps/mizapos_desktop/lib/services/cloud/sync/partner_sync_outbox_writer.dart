import 'dart:convert';

import 'package:mizapos_desktop/models/entities.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/partner_update_contract.dart';
import 'package:mizapos_desktop/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/device_binding.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Dual-mode outbox writer for customer / supplier (M1 Full default, Patch optional).
class PartnerSyncOutboxWriter {
  PartnerSyncOutboxWriter._();

  static CloudSecureStorage? _storage;
  static const Uuid _uuid = Uuid();

  static void bindStorage(CloudSecureStorage storage) {
    _storage = storage;
  }

  static CloudSecureStorage? get storage => _storage;

  static bool isPartnerEntityType(String entityType) {
    return entityType == PartnersSyncConstants.entityTypeCustomer ||
        entityType == PartnersSyncConstants.entityTypeSupplier;
  }

  static String _tableFor(String entityType) {
    return entityType == PartnersSyncConstants.entityTypeSupplier
        ? 'suppliers'
        : 'customers';
  }

  static String _numberColumnFor(String entityType) {
    return entityType == PartnersSyncConstants.entityTypeSupplier
        ? 'supplierNumber'
        : 'customerNumber';
  }

  static String? _groupColumnFor(String entityType) {
    return entityType == PartnersSyncConstants.entityTypeSupplier
        ? 'supplierGroupId'
        : 'customerGroupId';
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
    if (!isPartnerEntityType(entityType)) return;
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
    MasterEntity? entity;
    Map<String, Object?>? baseSnapshot;
    int? cloudRowVersion;
    String? customerGroupId;
    String? supplierGroupId;

    if (operation == 'delete') {
      fullPayload ??= {
        'id': entityId,
        'company_id': organizationId,
        'branch_id': branchId,
        'deleted': true,
      };
    } else {
      final loaded = await _loadPartner(
        db,
        entityType: entityType,
        entityId: entityId,
        organizationId: organizationId,
        branchId: branchId,
      );
      entity = loaded.entity;
      customerGroupId = loaded.customerGroupId;
      supplierGroupId = loaded.supplierGroupId;
      if (fullPayload == null && entity == null) return;

      final meta = await _loadCloudMeta(db, _tableFor(entityType), entityId);
      cloudRowVersion = meta.cloudRowVersion;
      baseSnapshot = meta.snapshot;
    }

    final intent = PartnerUpdateContract.buildIntent(
      entityType: entityType,
      operation: operation == 'patch' ? 'update' : operation,
      entityId: entityId,
      organizationId: organizationId,
      branchId: branchId,
      operationId: outboxId,
      entity: entity,
      fullPayload: fullPayload,
      baseSnapshot: baseSnapshot,
      cloudRowVersion: cloudRowVersion,
      customerGroupId: customerGroupId,
      supplierGroupId: supplierGroupId,
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
    String table,
    String entityId,
  ) async {
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
      snapshot: PartnerUpdateContract.decodeSnapshot(
        row['cloudCatalogSnapshotJson']?.toString(),
      ),
    );
  }

  static Future<({
    MasterEntity? entity,
    String? customerGroupId,
    String? supplierGroupId,
  })> _loadPartner(
    DatabaseExecutor db, {
    required String entityType,
    required String entityId,
    required String organizationId,
    required String branchId,
  }) async {
    final table = _tableFor(entityType);
    final numberColumn = _numberColumnFor(entityType);
    final groupColumn = _groupColumnFor(entityType);
    final rows = await db.query(
      table,
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [entityId, organizationId, branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return (
        entity: null,
        customerGroupId: null,
        supplierGroupId: null,
      );
    }
    final row = rows.first;
    final entity = MasterEntity(
      id: (row['id'] ?? '').toString(),
      organizationId: (row['organizationId'] ?? '').toString(),
      branchId: (row['branchId'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      phone: row['phone']?.toString(),
      address: row['address']?.toString(),
      partnerNumber: row[numberColumn]?.toString(),
      creditLimit: (row['creditLimit'] as num?)?.toDouble() ?? 0,
      overdueAlertDays: (row['overdueAlertDays'] as num?)?.toInt(),
      notes: row['notes']?.toString(),
    );
    final groupId = groupColumn != null && row.containsKey(groupColumn)
        ? row[groupColumn]?.toString()
        : null;
    return (
      entity: entity,
      customerGroupId:
          entityType == PartnersSyncConstants.entityTypeCustomer ? groupId : null,
      supplierGroupId:
          entityType == PartnersSyncConstants.entityTypeSupplier ? groupId : null,
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
