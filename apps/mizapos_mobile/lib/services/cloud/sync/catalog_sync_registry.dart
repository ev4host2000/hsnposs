import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Repositories + workers for catalog master entities (excluding products).
class CatalogSyncRegistry {
  CatalogSyncRegistry._({
    required CloudApiClient apiClient,
    CloudConfig? config,
    required DatabaseService databaseService,
  }) : _db = databaseService {
    productCategories = _buildRepo(
      apiClient: apiClient,
      config: config,
      entityType: CatalogSyncConstants.entityTypeProductCategory,
      scopeKey: CatalogSyncConstants.scopeKeyProductCategories,
      pushPath: '/sync/push/product-categories',
      pullPath: '/sync/pull/product-categories',
      applyEntry: _applyProductCategory,
    );
    productUnits = _buildRepo(
      apiClient: apiClient,
      config: config,
      entityType: CatalogSyncConstants.entityTypeProductUnit,
      scopeKey: CatalogSyncConstants.scopeKeyProductUnits,
      pushPath: '/sync/push/product-units',
      pullPath: '/sync/pull/product-units',
      applyEntry: _applyProductUnit,
    );
    taxes = _buildRepo(
      apiClient: apiClient,
      config: config,
      entityType: CatalogSyncConstants.entityTypeTax,
      scopeKey: CatalogSyncConstants.scopeKeyTaxes,
      pushPath: '/sync/push/taxes',
      pullPath: '/sync/pull/taxes',
      applyEntry: _applyTax,
    );
    priceLists = _buildRepo(
      apiClient: apiClient,
      config: config,
      entityType: CatalogSyncConstants.entityTypePriceList,
      scopeKey: CatalogSyncConstants.scopeKeyPriceLists,
      pushPath: '/sync/push/price-lists',
      pullPath: '/sync/pull/price-lists',
      applyEntry: _applyPriceList,
    );

    productCategoriesPush = CatalogEntityPushWorker(repository: productCategories);
    productUnitsPush = CatalogEntityPushWorker(repository: productUnits);
    taxesPush = CatalogEntityPushWorker(repository: taxes);
    priceListsPush = CatalogEntityPushWorker(repository: priceLists);

    productCategoriesPull = CatalogEntityPullWorker(repository: productCategories);
    productUnitsPull = CatalogEntityPullWorker(repository: productUnits);
    taxesPull = CatalogEntityPullWorker(repository: taxes);
    priceListsPull = CatalogEntityPullWorker(repository: priceLists);
  }

  final DatabaseService _db;

  late final CatalogEntitySyncRepository productCategories;
  late final CatalogEntitySyncRepository productUnits;
  late final CatalogEntitySyncRepository taxes;
  late final CatalogEntitySyncRepository priceLists;

  late final CatalogEntityPushWorker productCategoriesPush;
  late final CatalogEntityPushWorker productUnitsPush;
  late final CatalogEntityPushWorker taxesPush;
  late final CatalogEntityPushWorker priceListsPush;

  late final CatalogEntityPullWorker productCategoriesPull;
  late final CatalogEntityPullWorker productUnitsPull;
  late final CatalogEntityPullWorker taxesPull;
  late final CatalogEntityPullWorker priceListsPull;

  static CatalogSyncRegistry create({
    required CloudApiClient apiClient,
    CloudConfig? config,
    DatabaseService? databaseService,
  }) {
    return CatalogSyncRegistry._(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService ?? DatabaseService(),
    );
  }

  CatalogEntitySyncRepository _buildRepo({
    required CloudApiClient apiClient,
    CloudConfig? config,
    required String entityType,
    required String scopeKey,
    required String pushPath,
    required String pullPath,
    required CatalogApplyEntry applyEntry,
  }) {
    return CatalogEntitySyncRepository(
      entityType: entityType,
      scopeKey: scopeKey,
      syncApi: CatalogEntitySyncApi(
        apiClient: apiClient,
        pushPath: pushPath,
        pullPath: pullPath,
        config: config,
      ),
      applyEntry: applyEntry,
      databaseService: _db,
    );
  }

  Future<SyncPullApplyOutcome> _applyProductCategory(
    SyncChangelogEntry entry,
    DatabaseExecutor txn,
  ) async {
    if (entry.entityType != CatalogSyncConstants.entityTypeProductCategory) {
      return SyncPullApplyOutcome.failed;
    }
    if (entry.operation == 'delete' || entry.payloadJson['deleted'] == true) {
      return _deleteById(
        txn,
        table: 'product_categories',
        id: entry.entityId,
      );
    }
    return _upsertNamedRow(
      txn,
      table: 'product_categories',
      payload: entry.payloadJson,
      sortColumn: 'sortOrder',
    );
  }

  Future<SyncPullApplyOutcome> _applyProductUnit(
    SyncChangelogEntry entry,
    DatabaseExecutor txn,
  ) async {
    if (entry.entityType != CatalogSyncConstants.entityTypeProductUnit) {
      return SyncPullApplyOutcome.failed;
    }
    if (entry.operation == 'delete' || entry.payloadJson['deleted'] == true) {
      return _deleteById(
        txn,
        table: 'product_units',
        id: entry.entityId,
      );
    }
    return _upsertNamedRow(
      txn,
      table: 'product_units',
      payload: entry.payloadJson,
    );
  }

  Future<SyncPullApplyOutcome> _applyTax(
    SyncChangelogEntry entry,
    DatabaseExecutor txn,
  ) async {
    if (entry.entityType != CatalogSyncConstants.entityTypeTax) {
      return SyncPullApplyOutcome.failed;
    }
    if (entry.operation == 'delete' || entry.payloadJson['deleted'] == true) {
      return _deleteById(txn, table: 'taxes', id: entry.entityId);
    }

    final id = (entry.payloadJson['id'] ?? entry.entityId).toString();
    if (id.isEmpty) return SyncPullApplyOutcome.failed;

    final row = {
      'id': id,
      'organizationId': (entry.payloadJson['company_id'] ?? '').toString(),
      'branchId': (entry.payloadJson['branch_id'] ?? '').toString(),
      'name': (entry.payloadJson['name'] ?? '').toString(),
      'percent': CatalogEntitySyncRepository.asDouble(entry.payloadJson['percent']),
      'isDefault': CatalogEntitySyncRepository.asBool(entry.payloadJson['is_default']) ? 1 : 0,
      'sortOrder': (entry.payloadJson['sort_order'] as num?)?.toInt() ?? 0,
    };

    final existing = await txn.query('taxes', where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isEmpty) {
      await txn.insert('taxes', {
        ...row,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } else {
      await txn.update('taxes', row, where: 'id = ?', whereArgs: [id]);
    }
    return SyncPullApplyOutcome.applied;
  }

  Future<SyncPullApplyOutcome> _applyPriceList(
    SyncChangelogEntry entry,
    DatabaseExecutor txn,
  ) async {
    if (entry.entityType != CatalogSyncConstants.entityTypePriceList) {
      return SyncPullApplyOutcome.failed;
    }
    if (entry.operation == 'delete' || entry.payloadJson['deleted'] == true) {
      await txn.delete(
        'price_list_items',
        where: 'priceListId = ?',
        whereArgs: [entry.entityId],
      );
      return _deleteById(txn, table: 'price_lists', id: entry.entityId);
    }

    final id = (entry.payloadJson['id'] ?? entry.entityId).toString();
    if (id.isEmpty) return SyncPullApplyOutcome.failed;

    final row = {
      'id': id,
      'organizationId': (entry.payloadJson['company_id'] ?? '').toString(),
      'branchId': (entry.payloadJson['branch_id'] ?? '').toString(),
      'name': (entry.payloadJson['name'] ?? '').toString(),
      'isDefault': CatalogEntitySyncRepository.asBool(entry.payloadJson['is_default']) ? 1 : 0,
      'sortOrder': (entry.payloadJson['sort_order'] as num?)?.toInt() ?? 0,
    };

    final existing = await txn.query('price_lists', where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isEmpty) {
      await txn.insert('price_lists', {
        ...row,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } else {
      await txn.update('price_lists', row, where: 'id = ?', whereArgs: [id]);
    }

    await txn.delete('price_list_items', where: 'priceListId = ?', whereArgs: [id]);
    for (final item in CatalogEntitySyncRepository.decodeItems(entry.payloadJson['items'])) {
      final productId = (item['product_id'] ?? '').toString();
      if (productId.isEmpty) continue;
      await txn.insert('price_list_items', {
        'id': (item['id'] ?? '${id}_$productId').toString(),
        'organizationId': row['organizationId'],
        'branchId': row['branchId'],
        'priceListId': id,
        'productId': productId,
        'salePrice': CatalogEntitySyncRepository.asDouble(item['sale_price']),
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
    return SyncPullApplyOutcome.applied;
  }

  Future<SyncPullApplyOutcome> _deleteById(
    DatabaseExecutor txn, {
    required String table,
    required String id,
  }) async {
    final count = await txn.delete(table, where: 'id = ?', whereArgs: [id]);
    if (count > 0) return SyncPullApplyOutcome.applied;
    final existing = await txn.query(
      table,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return existing.isEmpty
        ? SyncPullApplyOutcome.applied
        : SyncPullApplyOutcome.failed;
  }

  Future<SyncPullApplyOutcome> _upsertNamedRow(
    DatabaseExecutor txn, {
    required String table,
    required Map<String, dynamic> payload,
    String? sortColumn,
  }) async {
    final id = (payload['id'] ?? '').toString();
    if (id.isEmpty) return SyncPullApplyOutcome.failed;

    final row = <String, Object?>{
      'id': id,
      'organizationId': (payload['company_id'] ?? '').toString(),
      'branchId': (payload['branch_id'] ?? '').toString(),
      'name': (payload['name'] ?? '').toString(),
    };
    if (sortColumn != null) {
      row[sortColumn] = (payload['sort_order'] as num?)?.toInt() ?? 0;
    }

    final existing = await txn.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isEmpty) {
      await txn.insert(table, {
        ...row,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } else {
      await txn.update(table, row, where: 'id = ?', whereArgs: [id]);
    }
    return SyncPullApplyOutcome.applied;
  }
}
