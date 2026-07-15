import 'package:mizapos_desktop/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_config.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_entity_pull_worker.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_entity_push_worker.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_entity_sync_api.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_entity_sync_repository.dart';
import 'package:mizapos_desktop/services/cloud/sync/expense_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Push/pull registry for expenses master rows.
class ExpenseSyncRegistry {
  ExpenseSyncRegistry._({
    required CloudApiClient apiClient,
    CloudConfig? config,
    required DatabaseService databaseService,
  }) : _db = databaseService {
    repository = CatalogEntitySyncRepository(
      entityType: ExpenseSyncConstants.entityType,
      scopeKey: ExpenseSyncConstants.scopeKey,
      syncApi: CatalogEntitySyncApi(
        apiClient: apiClient,
        pushPath: ExpenseSyncConstants.pushPath,
        pullPath: ExpenseSyncConstants.pullPath,
        config: config,
      ),
      applyEntry: _applyExpense,
      databaseService: _db,
    );
    pushWorker = CatalogEntityPushWorker(repository: repository);
    pullWorker = CatalogEntityPullWorker(repository: repository);
  }

  final DatabaseService _db;

  late final CatalogEntitySyncRepository repository;
  late final CatalogEntityPushWorker pushWorker;
  late final CatalogEntityPullWorker pullWorker;

  List<CatalogEntityPushWorker> get pushWorkers => [pushWorker];
  List<CatalogEntityPullWorker> get pullWorkers => [pullWorker];

  static ExpenseSyncRegistry create({
    required CloudApiClient apiClient,
    CloudConfig? config,
    DatabaseService? databaseService,
  }) {
    return ExpenseSyncRegistry._(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService ?? DatabaseService(),
    );
  }

  Future<SyncPullApplyOutcome> _applyExpense(
    SyncChangelogEntry entry,
    DatabaseExecutor txn,
  ) async {
    if (entry.entityType != ExpenseSyncConstants.entityType) {
      return SyncPullApplyOutcome.failed;
    }
    if (entry.operation == 'delete' || entry.payloadJson['deleted'] == true) {
      final count = await txn.delete(
        'expenses',
        where: 'id = ?',
        whereArgs: [entry.entityId],
      );
      return count > 0 ||
              (await txn.query(
                'expenses',
                columns: const ['id'],
                where: 'id = ?',
                whereArgs: [entry.entityId],
                limit: 1,
              ))
                  .isEmpty
          ? SyncPullApplyOutcome.applied
          : SyncPullApplyOutcome.failed;
    }

    final payload = entry.payloadJson;
    final id = (payload['id'] ?? entry.entityId).toString();
    if (id.isEmpty) return SyncPullApplyOutcome.failed;

    final title = (payload['title'] ?? '').toString().trim();
    if (title.isEmpty) return SyncPullApplyOutcome.failed;
    final amount = CatalogEntitySyncRepository.asDouble(payload['amount']);
    if (amount <= 0) return SyncPullApplyOutcome.failed;
    final createdBy =
        (payload['created_by_user_id'] ?? '').toString().trim();
    if (createdBy.isEmpty) return SyncPullApplyOutcome.failed;

    final row = <String, Object?>{
      'id': id,
      'organizationId': (payload['company_id'] ?? '').toString(),
      'branchId': (payload['branch_id'] ?? '').toString(),
      'title': title,
      'amount': amount,
      'expenseDate':
          (payload['expense_date'] ?? DateTime.now().toIso8601String())
              .toString(),
      'notes': CatalogEntitySyncRepository.optionalString(payload['notes']),
      'createdBy': createdBy,
    };

    final existing = await txn.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isEmpty) {
      await txn.insert('expenses', row);
    } else {
      await txn.update('expenses', row, where: 'id = ?', whereArgs: [id]);
    }
    return SyncPullApplyOutcome.applied;
  }
}
