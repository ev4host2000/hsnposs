import 'dart:convert';

import 'package:mizapos_desktop/models/entities.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/product_update_contract.dart';
import 'package:mizapos_desktop/services/cloud/sync/product_image_cloud_sync.dart';
import 'package:mizapos_desktop/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_outbox_row.dart';
import 'package:mizapos_desktop/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/products_pull_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/products_push_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/products_pull_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/products_push_response.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_deferred_pull_store.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_meta_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_outbox_claimer.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite `sync_outbox` + `sync_meta` + استدعاء [ProductsSyncApi].
class ProductsSyncRepository {
  ProductsSyncRepository({
    required ProductsSyncApi productsSyncApi,
    DatabaseService? databaseService,
    SyncDeferredPullStore? deferredPullStore,
    ProductImageCloudSync? imageSync,
  })  : _api = productsSyncApi,
        _db = databaseService ?? DatabaseService(),
        _deferredStore = deferredPullStore ?? SyncDeferredPullStore(),
        _imageSync = imageSync;

  final ProductsSyncApi _api;
  final DatabaseService _db;
  final SyncDeferredPullStore _deferredStore;
  final ProductImageCloudSync? _imageSync;

  DatabaseService get databaseService => _db;

  static const String entityTypeProduct = 'product';
  static const String scopeKeyProducts = 'products';
  static const String syncStatePending = 'pending';
  static const String syncStateSynced = 'synced';
  static const String syncStateFailed = 'failed';

  Future<void> enqueueProductCreate({
    required ProductEntity product,
    required String deviceId,
    required String installationId,
  }) {
    return enqueueProductOperation(
      product: product,
      operation: 'create',
      deviceId: deviceId,
      installationId: installationId,
    );
  }

  Future<void> enqueueProductOperation({
    required ProductEntity product,
    required String operation,
    required String deviceId,
    required String installationId,
    int clientRowVersion = 1,
  }) async {
    await ProductSyncOutboxWriter.record(
      operation: operation,
      productId: product.id,
      organizationId: product.organizationId,
      branchId: product.branchId,
      product: product,
      databaseService: _db,
      storage: ProductSyncOutboxWriter.storage,
    );
  }

  Future<List<SyncOutboxRow>> fetchPendingProducts({int limit = 50}) async {
    final db = await _db.database;
    final rows = await SyncOutboxClaimer.claimPending(
      db: db,
      entityType: entityTypeProduct,
      pendingState: syncStatePending,
      limit: limit,
    );
    return rows.map(_rowToOutbox).toList();
  }

  Future<int> countPendingProducts() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_outbox '
      'WHERE sync_state IN (?, ?) AND entity_type = ?',
      [
        syncStatePending,
        SyncOutboxClaimer.syncStateInFlight,
        entityTypeProduct,
      ],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// العملاء والموردون المعلّقون — يجب استنزافهم قبل المعاملات (FK).
  Future<int> countPendingPartners() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_outbox '
      'WHERE sync_state IN (?, ?) AND entity_type IN (?, ?)',
      [
        syncStatePending,
        SyncOutboxClaimer.syncStateInFlight,
        'customer',
        'supplier',
      ],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> markOutboxSynced({
    required List<String> outboxIds,
    required String batchId,
  }) async {
    if (outboxIds.isEmpty) return;
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(outboxIds.length, '?').join(',');

    // Capture product rows before marking synced (for cloud mirror update).
    final productRows = await db.query(
      'sync_outbox',
      columns: const [
        'id',
        'entity_id',
        'operation',
        'payload_json',
        'client_row_version',
      ],
      where: 'id IN ($placeholders) AND entity_type = ?',
      whereArgs: [...outboxIds, entityTypeProduct],
    );

    await db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, cloud_batch_id = ?, synced_at = ?, updated_at = ?, last_sync_error = NULL '
      'WHERE id IN ($placeholders)',
      [syncStateSynced, batchId, now, now, ...outboxIds],
    );

    for (final row in productRows) {
      await _rememberAcceptedProductCloudState(db, row);
    }
  }

  /// After successful push: store cloudRowVersion + catalog snapshot for Dual-mode Patch.
  Future<void> _rememberAcceptedProductCloudState(
    DatabaseExecutor db,
    Map<String, Object?> outboxRow,
  ) async {
    final operation = (outboxRow['operation'] ?? '').toString();
    if (operation == 'delete') return;
    final productId = (outboxRow['entity_id'] ?? '').toString();
    if (productId.isEmpty) return;

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode((outboxRow['payload_json'] ?? '{}').toString());
      payload = decoded is Map<String, dynamic>
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on Object {
      payload = <String, dynamic>{};
    }

    final base = payload['base_row_version'];
    final baseVer = base is int ? base : int.tryParse(base?.toString() ?? '');
    final clientVer = outboxRow['client_row_version'];
    final clientRowVersion = clientVer is int
        ? clientVer
        : int.tryParse(clientVer?.toString() ?? '') ?? 1;

    // Native patch bumps server to base+1; full/create uses client_row_version.
    final newCloudVersion = operation == 'patch' && baseVer != null && baseVer >= 1
        ? baseVer + 1
        : clientRowVersion;

    // Merge changed fields onto previous snapshot when patch.
    final existing = await db.query(
      'products',
      columns: const ['cloudCatalogSnapshotJson'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    var snapshot = existing.isNotEmpty
        ? ProductUpdateContract.decodeSnapshot(
            existing.first['cloudCatalogSnapshotJson']?.toString(),
          )
        : <String, Object?>{};

    if (operation == 'patch' && payload['changed_fields'] is Map) {
      final changed = Map<String, dynamic>.from(payload['changed_fields'] as Map);
      for (final e in changed.entries) {
        snapshot[e.key] = e.value;
      }
    } else {
      snapshot = ProductUpdateContract.catalogSnapshotFromPayload(payload);
    }

    await db.update(
      'products',
      {
        'cloudRowVersion': newCloudVersion,
        'cloudCatalogSnapshotJson':
            ProductUpdateContract.encodeSnapshot(snapshot),
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> markOutboxFailed(String outboxId, String error) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'sync_outbox',
      {
        'sync_state': syncStateFailed,
        'last_sync_error': error,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [outboxId],
    );
  }

  Future<void> releaseOutboxClaims(List<String> outboxIds) async {
    if (outboxIds.isEmpty) return;
    final db = await _db.database;
    await SyncOutboxClaimer.releaseToPending(
      db,
      outboxIds: outboxIds,
      pendingState: syncStatePending,
    );
  }

  Future<int> readLastPulledSequence({
    required String organizationId,
    required String branchId,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_meta',
      columns: const ['last_pulled_sequence'],
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [organizationId, branchId, scopeKeyProducts],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['last_pulled_sequence'] as int?) ?? 0;
  }

  Future<void> writeLastPulledSequence({
    required String organizationId,
    required String branchId,
    required int sequence,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await writeLastPulledSequenceTxn(
        txn,
        organizationId: organizationId,
        branchId: branchId,
        sequence: sequence,
      );
    });
  }

  Future<void> writeLastPulledSequenceTxn(
    DatabaseExecutor txn, {
    required String organizationId,
    required String branchId,
    required int sequence,
  }) {
    return SyncMetaWriter.upsertLastPulledSequence(
      txn,
      organizationId: organizationId,
      branchId: branchId,
      scopeKey: scopeKeyProducts,
      sequence: sequence,
    );
  }

  Future<CloudApiResponse<ProductsPushResponse>> pushRemote(
    ProductsPushRequest request, {
    String? idempotencyKey,
  }) {
    return _api.push(request, idempotencyKey: idempotencyKey);
  }

  Future<CloudApiResponse<ProductsPullResponse>> pullRemote(
    ProductsPullRequest request,
  ) {
    return _api.pull(request);
  }

  Future<SyncPullApplyOutcome> applyPulledEntry(
    SyncChangelogEntry entry,
    DatabaseExecutor txn, {
    required String organizationId,
    required String branchId,
  }) async {
    if (entry.entityType != entityTypeProduct) {
      return SyncPullApplyOutcome.failed;
    }
    if (entry.operation == 'delete' ||
        entry.payloadJson['deleted'] == true) {
      return _deleteLocalProduct(txn, entry.entityId);
    }

    final deferReason = await _productDependencyDeferReason(txn, entry.payloadJson);
    if (deferReason != null) {
      final org = organizationId.trim().isNotEmpty
          ? organizationId.trim()
          : (entry.payloadJson['company_id'] ?? '').toString().trim();
      final branch = branchId.trim().isNotEmpty
          ? branchId.trim()
          : (entry.payloadJson['branch_id'] ?? '').toString().trim();
      if (org.isEmpty || branch.isEmpty) {
        return SyncPullApplyOutcome.failed;
      }
      await _deferredStore.upsert(
        txn: txn,
        organizationId: org,
        branchId: branch,
        scopeKey: scopeKeyProducts,
        entry: entry,
        reason: deferReason,
      );
      return SyncPullApplyOutcome.deferred;
    }

    final outcome = await _upsertLocalProduct(
      txn,
      entry.payloadJson,
      cloudRowVersion: entry.rowVersion,
    );
    if (outcome == SyncPullApplyOutcome.applied) {
      await _deferredStore.remove(txn: txn, entityId: entry.entityId);
    }
    return outcome;
  }

  Future<void> retryDeferredProducts({
    required DatabaseExecutor txn,
    required String organizationId,
    required String branchId,
  }) async {
    final deferred = await _deferredStore.listForScope(
      txn: txn,
      organizationId: organizationId,
      branchId: branchId,
      scopeKey: scopeKeyProducts,
    );

    for (final entry in deferred) {
      final deferReason = await _productDependencyDeferReason(txn, entry.payloadJson);
      if (deferReason != null) continue;

      final outcome = await _upsertLocalProduct(
      txn,
      entry.payloadJson,
      cloudRowVersion: entry.rowVersion,
    );
      if (outcome == SyncPullApplyOutcome.applied) {
        await _deferredStore.remove(txn: txn, entityId: entry.entityId);
      }
    }
  }

  Future<String?> _productDependencyDeferReason(
    DatabaseExecutor txn,
    Map<String, dynamic> payload,
  ) async {
    final organizationId = (payload['company_id'] ?? '').toString();
    final branchId = (payload['branch_id'] ?? '').toString();
    final categoryId = _optionalString(payload['category_id']);
    if (categoryId != null) {
      final rows = await txn.query(
        'product_categories',
        columns: const ['id'],
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [categoryId, organizationId, branchId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return SyncDeferredPullStore.reasonMissingCategory;
      }
    }

    // unit_name نص حر على المنتج — لا نؤجّل السحب إن غابت صفوف product_units.
    return null;
  }

  Future<bool> upsertLocalProductFromEntity(ProductEntity product) async {
    final db = await _db.database;
    final existing = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [product.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;

    await db.insert('products', {
      'id': product.id,
      'organizationId': product.organizationId,
      'branchId': product.branchId,
      'name': product.name,
      'salePrice': product.salePrice,
      'costPrice': product.costPrice,
      'stockQty': product.stockQty,
      'barcode': product.barcode,
      'categoryId': product.categoryId,
      'description': product.description,
      'unitName': product.unitName,
      'isHidden': product.isHidden ? 1 : 0,
      'isFrozen': product.isFrozen ? 1 : 0,
      'isService': product.isService ? 1 : 0,
      'sortOrder': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return true;
  }

  Future<bool> localProductExists(String productId) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<SyncPullApplyOutcome> _upsertLocalProduct(
    DatabaseExecutor txn,
    Map<String, dynamic> payload, {
    int? cloudRowVersion,
  }) async {
    final id = (payload['id'] ?? '').toString();
    if (id.isEmpty) return SyncPullApplyOutcome.failed;

    final row = <String, Object?>{
      'id': id,
      'organizationId': (payload['company_id'] ?? '').toString(),
      'branchId': (payload['branch_id'] ?? '').toString(),
      'name': (payload['name'] ?? '').toString(),
      'salePrice': _asDouble(payload['sale_price']),
      'costPrice': _asDouble(payload['cost_price']),
      'barcode': _optionalString(payload['barcode']),
      'categoryId': _optionalString(payload['category_id']),
      'description': _optionalString(payload['description']),
      'unitName': _optionalString(payload['unit_name']),
      'isHidden': _asBool(payload['is_hidden']) ? 1 : 0,
      'isFrozen': _asBool(payload['is_frozen']) ? 1 : 0,
      'isService': _asBool(payload['is_service']) ? 1 : 0,
    };

    if (cloudRowVersion != null && cloudRowVersion >= 1) {
      row['cloudRowVersion'] = cloudRowVersion;
      row['cloudCatalogSnapshotJson'] = jsonEncode(
        ProductUpdateContract.catalogSnapshotFromPayload(payload),
      );
    }

    final existing = await txn.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (existing.isEmpty) {
      // المخزون من حركات الفواتير؛ يُطبَّق stock_qty عند الإنشاء فقط.
      await txn.insert('products', {
        ...row,
        'stockQty': _asDouble(payload['stock_qty']),
        'sortOrder': (payload['sort_order'] as num?)?.toInt() ?? 0,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } else {
      // لا تستبدل المخزون المحلي بتحديث كتالوج من جهاز آخر.
      await txn.update('products', row, where: 'id = ?', whereArgs: [id]);
    }

    if (_imageSync != null && payload.containsKey('image_url')) {
      await _imageSync.applyRemoteImage(
        productId: id,
        imageUrl: _optionalString(payload['image_url']),
        txn: txn,
      );
    }

    // أسقِط طابور رفع قديم لنفس المنتج حتى لا يعيد كتابة نسخة أقدم فوق السحابة.
    // لا تُحذف إن وُجدت صورة محلية لم تُرفع بعد (حتى لا تُفقد).
    final imageRows = await txn.query(
      'products',
      columns: const ['imagePath', 'cloudImageUrl', 'cloudImageLocalPath'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    var preserveImageOutbox = false;
    if (imageRows.isNotEmpty) {
      final imagePath =
          imageRows.first['imagePath']?.toString().trim() ?? '';
      final cloudUrl =
          imageRows.first['cloudImageUrl']?.toString().trim() ?? '';
      final syncedPath =
          imageRows.first['cloudImageLocalPath']?.toString().trim() ?? '';
      preserveImageOutbox = imagePath.isNotEmpty &&
          (cloudUrl.isEmpty || syncedPath != imagePath);
    }
    if (!preserveImageOutbox) {
      await txn.delete(
        'sync_outbox',
        where: 'entity_id = ? AND entity_type = ? AND sync_state IN (?, ?)',
        whereArgs: [
          id,
          entityTypeProduct,
          syncStatePending,
          syncStateFailed,
        ],
      );
    }

    return SyncPullApplyOutcome.applied;
  }

  Future<SyncPullApplyOutcome> _deleteLocalProduct(
    DatabaseExecutor txn,
    String productId,
  ) async {
    final count = await txn.delete(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    );
    if (count > 0) return SyncPullApplyOutcome.applied;
    final existing = await txn.query(
      'products',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    return existing.isEmpty
        ? SyncPullApplyOutcome.applied
        : SyncPullApplyOutcome.failed;
  }

  SyncOutboxRow _rowToOutbox(Map<String, Object?> row) {
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
      entityType: entityTypeProduct,
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

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    return value == true || value == 1 || value == '1' || value == 't';
  }

  String? _optionalString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
