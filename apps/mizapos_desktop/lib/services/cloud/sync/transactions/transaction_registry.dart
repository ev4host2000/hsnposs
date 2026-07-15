import 'package:mizapos_desktop/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_config.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_pull_worker.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_push_worker.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_api.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_repository.dart';
import 'package:mizapos_desktop/services/database_service.dart';

/// Central registry for transaction document types — ADR-TX-015.
///
/// Foundation sprint: starts empty; no business documents registered.
class TransactionRegistry {
  TransactionRegistry._({
    required CloudApiClient apiClient,
    CloudConfig? config,
    required DatabaseService databaseService,
  })  : _apiClient = apiClient,
        _config = config,
        _databaseService = databaseService;

  final CloudApiClient _apiClient;
  final CloudConfig? _config;
  final DatabaseService _databaseService;

  final Map<String, TransactionTypeDefinition> _types = {};
  final Map<String, TransactionSyncRepository> _repositories = {};
  final Map<String, TransactionPushWorker> _pushWorkers = {};
  final Map<String, TransactionPullWorker> _pullWorkers = {};

  List<String> get registeredEntityTypes =>
      _types.keys.toList(growable: false);

  List<String> get registeredScopeKeys => _types.values
      .map((t) => t.scopeKey)
      .toList(growable: false);

  bool get isEmpty => _types.isEmpty;

  int get count => _types.length;

  bool isRegistered(String entityType) => _types.containsKey(entityType);

  TransactionTypeDefinition? definition(String entityType) => _types[entityType];

  TransactionSyncRepository? repository(String entityType) =>
      _repositories[entityType];

  List<TransactionPushWorker> get pushWorkers =>
      _pushWorkers.values.toList(growable: false);

  List<TransactionPullWorker> get pullWorkers =>
      _pullWorkers.values.toList(growable: false);

  static TransactionRegistry create({
    required CloudApiClient apiClient,
    CloudConfig? config,
    DatabaseService? databaseService,
  }) {
    return TransactionRegistry._(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService ?? DatabaseService(),
    );
  }

  /// Registers a future document type and builds repo/workers for it.
  void register(TransactionTypeDefinition definition) {
    if (_types.containsKey(definition.entityType)) {
      throw StateError(
        'Transaction type already registered: ${definition.entityType}',
      );
    }

    final repo = TransactionSyncRepository(
      typeDefinition: definition,
      syncApi: TransactionSyncApi(
        apiClient: _apiClient,
        pushPath: definition.pushPath,
        pullPath: definition.pullPath,
        config: _config,
      ),
      databaseService: _databaseService,
    );

    _types[definition.entityType] = definition;
    _repositories[definition.entityType] = repo;
    _pushWorkers[definition.entityType] = TransactionPushWorker(
      repository: repo,
    );
    _pullWorkers[definition.entityType] = TransactionPullWorker(
      repository: repo,
    );
  }

  void unregister(String entityType) {
    _types.remove(entityType);
    _repositories.remove(entityType);
    _pushWorkers.remove(entityType);
    _pullWorkers.remove(entityType);
  }
}
