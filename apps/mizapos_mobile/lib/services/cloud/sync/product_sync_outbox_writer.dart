import 'dart:convert';

import 'package:mizapos_mobile/models/entities.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_mobile/services/cloud/sync/models/sync_outbox_row.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/services/device_binding.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// تسجيل أحداث product في `sync_outbox` بعد commit ناجح — بدون push.
class ProductSyncOutboxWriter {
  ProductSyncOutboxWriter._();

  static CloudSecureStorage? _storage;
  static final Uuid _uuid = Uuid();

  static const String entityTypeProduct = 'product';
  static const String syncStatePending = 'pending';

  /// ربط اختياري لقراءة `cloud_device_id` بعد تسجيل الجهاز.
  static void bindStorage(CloudSecureStorage storage) {
    _storage = storage;
  }

  static CloudSecureStorage? get storage => _storage;

  /// يسجّل create / update / delete — يتخطى بصمت إذا لا يوجد device context.
  static Future<void> record({
    required String operation,
    required String productId,
    required String organizationId,
    required String branchId,
    ProductEntity? product,
    Map<String, Object?>? deletedSnapshot,
    DatabaseService? databaseService,
    CloudSecureStorage? storage,
  }) async {
    if (operation != 'create' &&
        operation != 'update' &&
        operation != 'delete') {
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

    Map<String, dynamic> payload;
    if (operation == 'delete') {
      payload = deletedSnapshot != null
          ? _payloadFromRow(deletedSnapshot, deleted: true)
          : <String, dynamic>{
              'id': productId,
              'company_id': organizationId,
              'branch_id': branchId,
              'deleted': true,
            };
    } else {
      final entity = product ??
          await _loadProductEntity(
            db,
            productId,
            organizationId,
            branchId,
          );
      if (entity == null) return;
      payload = productEntityToCloudPayload(entity);
    }

    final clientRowVersion = await _nextClientRowVersion(db, productId);
    final outboxId = _uuid.v4();
    final idempotencyKey = '$deviceId:$productId:$operation:$outboxId';
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'sync_outbox',
      {
        'id': outboxId,
        'organization_id': organizationId,
        'branch_id': branchId,
        'entity_type': entityTypeProduct,
        'entity_id': productId,
        'operation': operation,
        'sync_state': syncStatePending,
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

    final byInstall = await db.query(
      'sync_devices',
      columns: const ['cloud_device_id'],
      where: 'installation_id = ?',
      whereArgs: [installationId],
      limit: 1,
    );
    if (byInstall.isNotEmpty) {
      final id = (byInstall.first['cloud_device_id'] ?? '').toString().trim();
      if (id.isNotEmpty) return id;
    }

    return installationId;
  }

  static Future<int> _nextClientRowVersion(
    Database db,
    String productId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT MAX(client_row_version) AS m FROM sync_outbox WHERE entity_id = ?',
      [productId],
    );
    final current = (rows.first['m'] as int?) ?? 0;
    return current + 1;
  }

  static Future<ProductEntity?> _loadProductEntity(
    Database db,
    String productId,
    String organizationId,
    String branchId,
  ) async {
    final rows = await db.query(
      'products',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, organizationId, branchId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.first);
  }

  static ProductEntity _productFromRow(Map<String, Object?> row) {
    final expiryRaw = row['expiryDate']?.toString();
    DateTime? expiry;
    if (expiryRaw != null && expiryRaw.isNotEmpty) {
      expiry = DateTime.tryParse(expiryRaw);
    }
    return ProductEntity(
      id: (row['id'] ?? '').toString(),
      organizationId: (row['organizationId'] ?? '').toString(),
      branchId: (row['branchId'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      salePrice: ((row['salePrice'] as num?) ?? 0).toDouble(),
      costPrice: ((row['costPrice'] as num?) ?? 0).toDouble(),
      stockQty: ((row['stockQty'] as num?) ?? 0).toDouble(),
      barcode: row['barcode']?.toString(),
      categoryId: row['categoryId']?.toString(),
      description: row['description']?.toString(),
      unitName: row['unitName']?.toString(),
      imagePath: row['imagePath']?.toString(),
      expiryDate: expiry,
      isHidden: ((row['isHidden'] as num?) ?? 0) != 0,
      isFrozen: ((row['isFrozen'] as num?) ?? 0) != 0,
      isService: ((row['isService'] as num?) ?? 0) != 0,
    );
  }

  static Map<String, dynamic> _payloadFromRow(
    Map<String, Object?> row, {
    bool deleted = false,
  }) {
    final payload = <String, dynamic>{
      'id': (row['id'] ?? '').toString(),
      'company_id': (row['organizationId'] ?? '').toString(),
      'branch_id': (row['branchId'] ?? '').toString(),
      'name': (row['name'] ?? '').toString(),
      'sale_price': ((row['salePrice'] as num?) ?? 0).toDouble(),
      'cost_price': ((row['costPrice'] as num?) ?? 0).toDouble(),
      'stock_qty': ((row['stockQty'] as num?) ?? 0).toDouble(),
      if (row['barcode'] != null) 'barcode': row['barcode'],
      if (row['categoryId'] != null) 'category_id': row['categoryId'],
      if (row['description'] != null) 'description': row['description'],
      if (row['unitName'] != null) 'unit_name': row['unitName'],
      'is_hidden': ((row['isHidden'] as num?) ?? 0) != 0,
      'is_frozen': ((row['isFrozen'] as num?) ?? 0) != 0,
      'is_service': ((row['isService'] as num?) ?? 0) != 0,
    };
    if (deleted) payload['deleted'] = true;
    return payload;
  }
}
