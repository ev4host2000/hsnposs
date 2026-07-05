import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_return_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/sales_return_draft_apply_handler.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_mobile/services/database_service.dart';

/// Registers sales return draft/post with the transaction framework.
class SalesReturnSyncRegistry {
  SalesReturnSyncRegistry._();

  static void registerWith({
    required TransactionRegistry registry,
  }) {
    if (registry.isRegistered(SalesReturnSyncConstants.entityType)) {
      return;
    }

    registry.register(
      TransactionTypeDefinition(
        entityType: SalesReturnSyncConstants.entityType,
        scopeKey: SalesReturnSyncConstants.scopeKey,
        pushPath: SalesReturnSyncConstants.pushPath,
        pullPath: SalesReturnSyncConstants.pullPath,
        applyHandler: SalesReturnDraftApplyHandler(),
      ),
    );
  }

  static TransactionRegistry createRegistered({
    required CloudApiClient apiClient,
    CloudConfig? config,
    DatabaseService? databaseService,
  }) {
    final registry = TransactionRegistry.create(
      apiClient: apiClient,
      config: config,
      databaseService: databaseService,
    );
    registerWith(registry: registry);
    return registry;
  }
}
