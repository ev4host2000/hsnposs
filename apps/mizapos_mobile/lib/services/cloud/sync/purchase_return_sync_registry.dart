import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/sync/purchase_return_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/purchase_return_draft_apply_handler.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_mobile/services/database_service.dart';

/// Registers purchase return draft/post with the transaction framework.
class PurchaseReturnSyncRegistry {
  PurchaseReturnSyncRegistry._();

  static void registerWith({
    required TransactionRegistry registry,
  }) {
    if (registry.isRegistered(PurchaseReturnSyncConstants.entityType)) {
      return;
    }

    registry.register(
      TransactionTypeDefinition(
        entityType: PurchaseReturnSyncConstants.entityType,
        scopeKey: PurchaseReturnSyncConstants.scopeKey,
        pushPath: PurchaseReturnSyncConstants.pushPath,
        pullPath: PurchaseReturnSyncConstants.pullPath,
        applyHandler: PurchaseReturnDraftApplyHandler(),
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
