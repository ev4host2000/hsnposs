import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_outbox_row.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/device_binding.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Generic outbox writer for catalog master entities.
class CatalogSyncOutboxWriter {
  CatalogSyncOutboxWriter._();

  static CloudSecureStorage? _storage;
  static final Uuid _uuid = Uuid();

  static void bindStorage(CloudSecureStorage storage) {
    _storage = storage;
  }

  static CloudSecureStorage? get storage => _storage;

  static Future<void> record({
    required String entityType,
    required String operation,
    required String entityId,
    required String organizationId,
    required String branchId,
    required Map<String, dynamic> payload,
    DatabaseService? databaseService,
    CloudSecureStorage? storage,
    DatabaseExecutor? executor,
  }) async {
    if (operation != 'create' &&
        operation != 'update' &&
        operation != 'delete') {
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

    final clientRowVersion = await _nextClientRowVersion(db, entityId);
    final outboxId = _uuid.v4();
    final idempotencyKey = '$deviceId:$entityId:$operation:$outboxId';
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'sync_outbox',
      {
        'id': outboxId,
        'organization_id': organizationId,
        'branch_id': branchId,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation,
        'sync_state': CatalogSyncConstants.syncStatePending,
        'payload_json': jsonEncode(payload),
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
}

Map<String, dynamic> namedEntityCloudPayload({
  required String id,
  required String organizationId,
  required String branchId,
  required String name,
  int? sortOrder,
  bool deleted = false,
}) {
  return {
    'id': id,
    'company_id': organizationId,
    'branch_id': branchId,
    'name': name,
    if (sortOrder != null) 'sort_order': sortOrder,
    if (deleted) 'deleted': true,
  };
}

Map<String, dynamic> taxEntityCloudPayload({
  required String id,
  required String organizationId,
  required String branchId,
  required String name,
  required double percent,
  bool isDefault = false,
  int sortOrder = 0,
  bool deleted = false,
}) {
  return {
    'id': id,
    'company_id': organizationId,
    'branch_id': branchId,
    'name': name,
    'percent': percent,
    'is_default': isDefault,
    'sort_order': sortOrder,
    if (deleted) 'deleted': true,
  };
}

Map<String, dynamic> priceListEntityCloudPayload({
  required String id,
  required String organizationId,
  required String branchId,
  required String name,
  bool isDefault = false,
  int sortOrder = 0,
  List<Map<String, dynamic>> items = const [],
  bool deleted = false,
}) {
  return {
    'id': id,
    'company_id': organizationId,
    'branch_id': branchId,
    'name': name,
    'is_default': isDefault,
    'sort_order': sortOrder,
    'items': items,
    if (deleted) 'deleted': true,
  };
}

Map<String, dynamic> partnerEntityCloudPayload({
  required String id,
  required String organizationId,
  required String branchId,
  required String name,
  String? partnerNumber,
  String? phone,
  String? address,
  String? notes,
  double creditLimit = 0,
  int? overdueAlertDays,
  String? customerGroupId,
  String? supplierGroupId,
  bool deleted = false,
}) {
  return {
    'id': id,
    'company_id': organizationId,
    'branch_id': branchId,
    'name': name,
    if (partnerNumber != null) 'partner_number': partnerNumber,
    if (phone != null) 'phone': phone,
    if (address != null) 'address': address,
    if (notes != null) 'notes': notes,
    'credit_limit': creditLimit,
    if (overdueAlertDays != null) 'overdue_alert_days': overdueAlertDays,
    if (customerGroupId != null) 'customer_group_id': customerGroupId,
    if (supplierGroupId != null) 'supplier_group_id': supplierGroupId,
    if (deleted) 'deleted': true,
  };
}

Map<String, dynamic> cashEntityCloudPayload({
  required String id,
  required String organizationId,
  required String branchId,
  required String transactionType,
  required double amount,
  required String description,
  required String referenceType,
  required String referenceId,
  required String transactionDate,
  required String createdByUserId,
}) {
  return {
    'id': id,
    'company_id': organizationId,
    'branch_id': branchId,
    'transaction_type': transactionType,
    'amount': amount,
    'description': description,
    'reference_type': referenceType,
    'reference_id': referenceId,
    'transaction_date': transactionDate,
    'created_by_user_id': createdByUserId,
  };
}

Map<String, dynamic> expenseEntityCloudPayload({
  required String id,
  required String organizationId,
  required String branchId,
  required String title,
  required double amount,
  required String expenseDate,
  required String createdByUserId,
  String? notes,
  bool deleted = false,
}) {
  return {
    'id': id,
    'company_id': organizationId,
    'branch_id': branchId,
    'title': title,
    'amount': amount,
    'expense_date': expenseDate,
    if (notes != null && notes.isNotEmpty) 'notes': notes,
    'created_by_user_id': createdByUserId,
    if (deleted) 'deleted': true,
  };
}

SyncOutboxRow rowToOutbox(Map<String, Object?> row, String entityType) {
  final rawPayload = row['payload_json'];
  Map<String, dynamic> payload = const {};
  if (rawPayload is String && rawPayload.isNotEmpty) {
    final decoded = jsonDecode(rawPayload);
    if (decoded is Map) {
      payload = Map<String, dynamic>.from(decoded);
    }
  }

  return SyncOutboxRow(
    id: (row['id'] ?? '').toString(),
    entityType: entityType,
    organizationId: (row['organization_id'] ?? '').toString(),
    branchId: (row['branch_id'] ?? '').toString(),
    entityId: (row['entity_id'] ?? '').toString(),
    operation: (row['operation'] ?? '').toString(),
    payloadJson: payload,
    clientRowVersion: (row['client_row_version'] as int?) ?? 1,
    idempotencyKey: (row['idempotency_key'] ?? '').toString(),
    installationId: (row['installation_id'] ?? '').toString(),
  );
}
