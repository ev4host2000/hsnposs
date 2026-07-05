import 'dart:convert';

import 'package:mizapos_mobile/models/entities.dart';
import 'package:mizapos_mobile/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_mobile/services/cloud/sync/models/sync_outbox_row.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/requests/products_pull_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/requests/products_push_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/responses/products_pull_response.dart';
import 'package:mizapos_mobile/services/cloud/sync/responses/products_push_response.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_deferred_pull_store.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite `sync_outbox` + `sync_meta` + استدعاء [ProductsSyncApi].
class ProductsSyncRepository {
  ProductsSyncRepository({
    required ProductsSyncApi productsSyncApi,
    DatabaseService? databaseService,
    SyncDeferredPullStore? deferredPullStore,
  })  : _api = productsSyncApi,
        _db = databaseService ?? DatabaseService(),
        _deferredStore = deferredPullStore ?? SyncDeferredPullStore();

  final ProductsSyncApi _api;
  final DatabaseService _db;
  final SyncDeferredPullStore _deferredStore;

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
    final rows = await db.query(
      'sync_outbox',
      where: 'sync_state = ? AND entity_type = ?',
      whereArgs: [syncStatePending, entityTypeProduct],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return rows.map(_rowToOutbox).toList();
  }

  Future<void> markOutboxSynced({
    required List<String> outboxIds,
    required String batchId,
  }) async {
    if (outboxIds.isEmpty) return;
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(outboxIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, cloud_batch_id = ?, synced_at = ?, updated_at = ?, last_sync_error = NULL '
      'WHERE id IN ($placeholders)',
      [syncStateSynced, batchId, now, now, ...outboxIds],
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
  }) async {
    final now = DateTime.now().toIso8601String();
    final existing = await txn.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [organizationId, branchId, scopeKeyProducts],
      limit: 1,
    );

    if (existing.isEmpty) {
      await txn.insert('sync_meta', {
        'organization_id': organizationId,
        'branch_id': branchId,
        'scope_key': scopeKeyProducts,
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

    await txn.update(
      'sync_meta',
      {
        'last_pulled_sequence': sequence,
        'last_pulled_at': now,
        'updated_at': now,
      },
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [organizationId, branchId, scopeKeyProducts],
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
    DatabaseExecutor txn,
  ) async {
    if (entry.entityType != entityTypeProduct) {
      return SyncPullApplyOutcome.failed;
    }
    if (entry.operation == 'delete' ||
        entry.payloadJson['deleted'] == true) {
      return _deleteLocalProduct(txn, entry.entityId);
    }

    final deferReason = await _productDependencyDeferReason(txn, entry.payloadJson);
    if (deferReason != null) {
      await _deferredStore.upsert(
        txn: txn,
        organizationId: (entry.payloadJson['company_id'] ?? '').toString(),
        branchId: (entry.payloadJson['branch_id'] ?? '').toString(),
        scopeKey: scopeKeyProducts,
        entry: entry,
        reason: deferReason,
      );
      return SyncPullApplyOutcome.deferred;
    }

    return _upsertLocalProduct(txn, entry.payloadJson);
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

      final outcome = await _upsertLocalProduct(txn, entry.payloadJson);
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

    final unitName = _optionalString(payload['unit_name']);
    if (unitName != null) {
      final rows = await txn.rawQuery(
        'SELECT id FROM product_units '
        'WHERE organizationId = ? AND branchId = ? AND name = ? COLLATE NOCASE '
        'LIMIT 1',
        [organizationId, branchId, unitName],
      );
      if (rows.isEmpty) {
        return SyncDeferredPullStore.reasonMissingUnit;
      }
    }

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
    Map<String, dynamic> payload,
  ) async {
    final id = (payload['id'] ?? '').toString();
    if (id.isEmpty) return SyncPullApplyOutcome.failed;

    final row = {
      'id': id,
      'organizationId': (payload['company_id'] ?? '').toString(),
      'branchId': (payload['branch_id'] ?? '').toString(),
      'name': (payload['name'] ?? '').toString(),
      'salePrice': _asDouble(payload['sale_price']),
      'costPrice': _asDouble(payload['cost_price']),
      'stockQty': _asDouble(payload['stock_qty']),
      'barcode': _optionalString(payload['barcode']),
      'categoryId': _optionalString(payload['category_id']),
      'description': _optionalString(payload['description']),
      'unitName': _optionalString(payload['unit_name']),
      'isHidden': _asBool(payload['is_hidden']) ? 1 : 0,
      'isFrozen': _asBool(payload['is_frozen']) ? 1 : 0,
      'isService': _asBool(payload['is_service']) ? 1 : 0,
    };

    final existing = await txn.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (existing.isEmpty) {
      await txn.insert('products', {
        ...row,
        'sortOrder': (payload['sort_order'] as num?)?.toInt() ?? 0,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } else {
      await txn.update('products', row, where: 'id = ?', whereArgs: [id]);
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
