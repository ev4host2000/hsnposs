import 'dart:convert';

import 'package:mizapos_desktop/models/entities.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/product_update_contract.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_outbox_row.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/device_binding.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// ØªØ³Ø¬ÙŠÙ„ Ø£Ø­Ø¯Ø§Ø« product ÙÙŠ `sync_outbox` Ø¨Ø¹Ø¯ commit Ù†Ø§Ø¬Ø­ â€” Ø¨Ø¯ÙˆÙ† push.
///
/// M1 Dual-mode: Ø§ÙØªØ±Ø§Ø¶ÙŠ Full EntityØ› Patch Ø¹Ù†Ø¯ ØªÙØ¹ÙŠÙ„ Ø§Ù„Ø¹Ù„Ù… ÙˆØªÙˆÙØ± base Ø³Ø­Ø§Ø¨ÙŠ.
class ProductSyncOutboxWriter {
  ProductSyncOutboxWriter._();

  static CloudSecureStorage? _storage;
  static const Uuid _uuid = Uuid();

  static const String entityTypeProduct = 'product';
  static const String syncStatePending = 'pending';

  /// Ø±Ø¨Ø· Ø§Ø®ØªÙŠØ§Ø±ÙŠ Ù„Ù‚Ø±Ø§Ø¡Ø© `cloud_device_id` Ø¨Ø¹Ø¯ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¬Ù‡Ø§Ø².
  static void bindStorage(CloudSecureStorage storage) {
    _storage = storage;
  }

  static CloudSecureStorage? get storage => _storage;

  /// ÙŠØ³Ø¬Ù‘Ù„ create / update / delete â€” ÙŠØªØ®Ø·Ù‰ Ø¨ØµÙ…Øª Ø¥Ø°Ø§ Ù„Ø§ ÙŠÙˆØ¬Ø¯ device context.
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

    final outboxId = _uuid.v4();

    Map<String, dynamic>? fullPayload;
    ProductEntity? entity = product;
    String? imageUrl;
    var sortOrder = 0;
    Map<String, Object?>? baseSnapshot;
    int? cloudRowVersion;

    if (operation == 'delete') {
      fullPayload = deletedSnapshot != null
          ? _payloadFromRow(deletedSnapshot, deleted: true)
          : <String, dynamic>{
              'id': productId,
              'company_id': organizationId,
              'branch_id': branchId,
              'deleted': true,
            };
    } else {
      entity ??= await _loadProductEntity(
        db,
        productId,
        organizationId,
        branchId,
      );
      if (entity == null) return;
      fullPayload = productEntityToCloudPayload(entity);

      final meta = await _loadCloudMeta(db, productId);
      cloudRowVersion = meta.cloudRowVersion;
      baseSnapshot = meta.snapshot;
      imageUrl = meta.imageUrl;
      sortOrder = meta.sortOrder;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        fullPayload['image_url'] = imageUrl;
      }
      if (sortOrder != 0) {
        fullPayload['sort_order'] = sortOrder;
      }
    }

    final intent = ProductUpdateContract.buildIntent(
      operation: operation,
      productId: productId,
      organizationId: organizationId,
      branchId: branchId,
      operationId: outboxId,
      product: entity,
      fullPayload: fullPayload,
      baseSnapshot: baseSnapshot,
      cloudRowVersion: cloudRowVersion,
      imageUrl: imageUrl,
      sortOrder: sortOrder,
    );

    if (intent.skipEnqueue) {
      return;
    }

    final clientRowVersion = intent.clientRowVersionHint ??
        await _nextClientRowVersion(db, productId);
    final idempotencyKey =
        '$deviceId:$productId:${intent.operation}:$outboxId';
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'sync_outbox',
      {
        'id': outboxId,
        'organization_id': organizationId,
        'branch_id': branchId,
        'entity_type': entityTypeProduct,
        'entity_id': productId,
        'operation': intent.operation,
        'sync_state': syncStatePending,
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

  /// Rebuilds a failed patch/update outbox after version_conflict (post-pull).
  static Future<bool> rebuildAfterVersionConflict({
    required String outboxId,
    DatabaseService? databaseService,
  }) async {
    final dbService = databaseService ?? DatabaseService();
    final db = await dbService.database;
    final rows = await db.query(
      'sync_outbox',
      where: 'id = ? AND entity_type = ?',
      whereArgs: [outboxId, entityTypeProduct],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    final productId = (row['entity_id'] ?? '').toString();
    final organizationId = (row['organization_id'] ?? '').toString();
    final branchId = (row['branch_id'] ?? '').toString();
    final prevOp = (row['operation'] ?? '').toString();
    if (productId.isEmpty) return false;

    if (prevOp == 'delete') {
      await db.update(
        'sync_outbox',
        {
          'sync_state': syncStatePending,
          'last_sync_error': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [outboxId],
      );
      return true;
    }

    final entity = await _loadProductEntity(
      db,
      productId,
      organizationId,
      branchId,
    );
    if (entity == null) {
      await db.delete('sync_outbox', where: 'id = ?', whereArgs: [outboxId]);
      return false;
    }

    final meta = await _loadCloudMeta(db, productId);
    final fullPayload = productEntityToCloudPayload(entity);
    if (meta.imageUrl != null && meta.imageUrl!.isNotEmpty) {
      fullPayload['image_url'] = meta.imageUrl;
    }

    final intent = ProductUpdateContract.buildIntent(
      operation: 'update',
      productId: productId,
      organizationId: organizationId,
      branchId: branchId,
      operationId: outboxId,
      product: entity,
      fullPayload: fullPayload,
      baseSnapshot: meta.snapshot,
      cloudRowVersion: meta.cloudRowVersion,
      imageUrl: meta.imageUrl,
      sortOrder: meta.sortOrder,
    );

    if (intent.skipEnqueue) {
      await db.delete('sync_outbox', where: 'id = ?', whereArgs: [outboxId]);
      return true;
    }

    final clientRowVersion = intent.clientRowVersionHint ??
        await _nextClientRowVersion(db, productId);

    await db.update(
      'sync_outbox',
      {
        'operation': intent.operation,
        'payload_json': jsonEncode(intent.payload),
        'client_row_version': clientRowVersion,
        'sync_state': syncStatePending,
        'last_sync_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [outboxId],
    );
    return true;
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

  static Future<({
    int? cloudRowVersion,
    Map<String, Object?> snapshot,
    String? imageUrl,
    int sortOrder,
  })> _loadCloudMeta(Database db, String productId) async {
    final rows = await db.query(
      'products',
      columns: const [
        'cloudRowVersion',
        'cloudCatalogSnapshotJson',
        'cloudImageUrl',
        'sortOrder',
      ],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return (
        cloudRowVersion: null,
        snapshot: <String, Object?>{},
        imageUrl: null,
        sortOrder: 0,
      );
    }
    final row = rows.first;
    final ver = row['cloudRowVersion'];
    final cloudRowVersion = ver is int
        ? ver
        : int.tryParse(ver?.toString() ?? '');
    final snapshot = ProductUpdateContract.decodeSnapshot(
      row['cloudCatalogSnapshotJson']?.toString(),
    );
    final imageUrl = row['cloudImageUrl']?.toString();
    final sortOrder = (row['sortOrder'] as num?)?.toInt() ?? 0;
    return (
      cloudRowVersion: cloudRowVersion,
      snapshot: snapshot,
      imageUrl: (imageUrl != null && imageUrl.isNotEmpty) ? imageUrl : null,
      sortOrder: sortOrder,
    );
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
