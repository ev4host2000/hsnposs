import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_push_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_sync_api.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Repositories + workers for customers and suppliers.
class PartnersSyncRegistry {
  PartnersSyncRegistry._({
    required CloudApiClient apiClient,
    CloudConfig? config,
    required DatabaseService databaseService,
  }) : _db = databaseService {
    customers = _buildRepo(
      apiClient: apiClient,
      config: config,
      entityType: PartnersSyncConstants.entityTypeCustomer,
      scopeKey: PartnersSyncConstants.scopeKeyCustomers,
      pushPath: '/sync/push/customers',
      pullPath: '/sync/pull/customers',
      applyEntry: _applyCustomer,
    );
    suppliers = _buildRepo(
      apiClient: apiClient,
      config: config,
      entityType: PartnersSyncConstants.entityTypeSupplier,
      scopeKey: PartnersSyncConstants.scopeKeySuppliers,
      pushPath: '/sync/push/suppliers',
      pullPath: '/sync/pull/suppliers',
      applyEntry: _applySupplier,
    );

    customersPush = CatalogEntityPushWorker(repository: customers);
    suppliersPush = CatalogEntityPushWorker(repository: suppliers);
    customersPull = CatalogEntityPullWorker(repository: customers);
    suppliersPull = CatalogEntityPullWorker(repository: suppliers);
  }

  final DatabaseService _db;

  late final CatalogEntitySyncRepository customers;
  late final CatalogEntitySyncRepository suppliers;

  late final CatalogEntityPushWorker customersPush;
  late final CatalogEntityPushWorker suppliersPush;
  late final CatalogEntityPullWorker customersPull;
  late final CatalogEntityPullWorker suppliersPull;

  List<CatalogEntityPushWorker> get pushWorkers => [
        customersPush,
        suppliersPush,
      ];

  List<CatalogEntityPullWorker> get pullWorkers => [
        customersPull,
        suppliersPull,
      ];

  static PartnersSyncRegistry create({
    required CloudApiClient apiClient,
    CloudConfig? config,
    DatabaseService? databaseService,
  }) {
    return PartnersSyncRegistry._(
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

  Future<SyncPullApplyOutcome> _applyCustomer(
    SyncChangelogEntry entry,
    DatabaseExecutor txn,
  ) async {
    if (entry.entityType != PartnersSyncConstants.entityTypeCustomer) {
      return SyncPullApplyOutcome.failed;
    }
    return _applyPartner(
      txn,
      table: 'customers',
      numberColumn: 'customerNumber',
      groupColumn: 'customerGroupId',
      entry: entry,
    );
  }

  Future<SyncPullApplyOutcome> _applySupplier(
    SyncChangelogEntry entry,
    DatabaseExecutor txn,
  ) async {
    if (entry.entityType != PartnersSyncConstants.entityTypeSupplier) {
      return SyncPullApplyOutcome.failed;
    }
    return _applyPartner(
      txn,
      table: 'suppliers',
      numberColumn: 'supplierNumber',
      groupColumn: 'supplierGroupId',
      entry: entry,
    );
  }

  Future<SyncPullApplyOutcome> _applyPartner(
    DatabaseExecutor txn, {
    required String table,
    required String numberColumn,
    required String groupColumn,
    required SyncChangelogEntry entry,
  }) async {
    if (entry.operation == 'delete' || entry.payloadJson['deleted'] == true) {
      return _deleteById(txn, table: table, id: entry.entityId);
    }

    final payload = entry.payloadJson;
    final id = (payload['id'] ?? entry.entityId).toString();
    if (id.isEmpty) return SyncPullApplyOutcome.failed;

    final row = <String, Object?>{
      'id': id,
      'organizationId': (payload['company_id'] ?? '').toString(),
      'branchId': (payload['branch_id'] ?? '').toString(),
      'name': (payload['name'] ?? '').toString(),
      'phone': CatalogEntitySyncRepository.optionalString(payload['phone']),
      'address': CatalogEntitySyncRepository.optionalString(payload['address']),
      'notes': CatalogEntitySyncRepository.optionalString(payload['notes']),
      numberColumn: CatalogEntitySyncRepository.optionalString(
        payload['partner_number'] ?? payload[numberColumn == 'customerNumber' ? 'customer_number' : 'supplier_number'],
      ),
      'creditLimit': CatalogEntitySyncRepository.asDouble(payload['credit_limit']),
      'overdueAlertDays': payload['overdue_alert_days'] == null
          ? null
          : (payload['overdue_alert_days'] as num?)?.toInt(),
    };

    final groupId = CatalogEntitySyncRepository.optionalString(
      payload['customer_group_id'] ?? payload['supplier_group_id'],
    );
    if (groupId != null && await _tableHasColumn(txn, table, groupColumn)) {
      row[groupColumn] = groupId;
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

  Future<bool> _tableHasColumn(
    DatabaseExecutor txn,
    String table,
    String column,
  ) async {
    final rows = await txn.rawQuery('PRAGMA table_info($table)');
    for (final row in rows) {
      if ((row['name'] ?? '').toString() == column) return true;
    }
    return false;
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
}
