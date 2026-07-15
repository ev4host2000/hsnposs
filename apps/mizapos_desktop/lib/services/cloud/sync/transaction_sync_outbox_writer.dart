import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_constants.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/device_binding.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Outbox writer for transaction document types (envelope payload).
class TransactionSyncOutboxWriter {
  TransactionSyncOutboxWriter._();

  static CloudSecureStorage? _storage;
  static final Uuid _uuid = Uuid();

  static void bindStorage(CloudSecureStorage storage) {
    _storage = storage;
  }

  static Future<void> record({
    required String entityType,
    required String operation,
    required String entityId,
    required String organizationId,
    required String branchId,
    required Map<String, dynamic> payload,
    DatabaseService? databaseService,
    CloudSecureStorage? storage,
  }) async {
    if (!TransactionSyncConstants.supportedOperations.contains(operation)) {
      return;
    }

    final dbService = databaseService ?? DatabaseService();
    final db = await dbService.database;
    final installationId = await DeviceBinding.readInstallationId();
    final deviceId = await _resolveDeviceId(
      db,
      storage ?? _storage,
      installationId,
    );
    if (deviceId.isEmpty) return;

    final clientRowVersion = await _nextClientRowVersion(db, entityId);
    final outboxId = _uuid.v4();
    final idempotencyKey = _idempotencyKey(
      deviceId: deviceId,
      entityId: entityId,
      operation: operation,
      outboxId: outboxId,
    );
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
        'sync_state': TransactionSyncConstants.syncStatePending,
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

  /// يحاول تسجيل الحدث في outbox دون إفشال مسار الترحيل المحلي.
  static Future<void> recordBestEffort({
    required String entityType,
    required String operation,
    required String entityId,
    required String organizationId,
    required String branchId,
    required Map<String, dynamic> payload,
    DatabaseService? databaseService,
    CloudSecureStorage? storage,
  }) async {
    try {
      await record(
        entityType: entityType,
        operation: operation,
        entityId: entityId,
        organizationId: organizationId,
        branchId: branchId,
        payload: payload,
        databaseService: databaseService,
        storage: storage,
      );
    } on Object {
      // لا يُلغى ترحيل المخزون المحلي عند تعذّر طابور المزامنة.
    }
  }

  static Future<String> _resolveDeviceId(
    Database db,
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

  /// Create/post/void use stable keys so replay push does not create duplicate changelog entries.
  static String _idempotencyKey({
    required String deviceId,
    required String entityId,
    required String operation,
    required String outboxId,
  }) {
    if (operation == 'create' ||
        operation == 'post' ||
        operation == 'void') {
      return '$deviceId:$entityId:$operation';
    }
    return '$deviceId:$entityId:$operation:$outboxId';
  }

  static Future<int> _nextClientRowVersion(Database db, String entityId) async {
    final rows = await db.rawQuery(
      'SELECT MAX(client_row_version) AS m FROM sync_outbox WHERE entity_id = ?',
      [entityId],
    );
    final current = (rows.first['m'] as int?) ?? 0;
    return current + 1;
  }
}
