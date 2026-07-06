import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/sync/inventory_adjustment_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/inventory_adjustment_draft_apply_handler.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_mobile/services/database_service.dart';

/// Registers inventory adjustment draft/post with the transaction framework.
class InventoryAdjustmentSyncRegistry {
  InventoryAdjustmentSyncRegistry._();

  static void registerWith({
    required TransactionRegistry registry,
  }) {
    if (registry.isRegistered(InventoryAdjustmentSyncConstants.entityType)) {
      return;
    }

    registry.register(
      TransactionTypeDefinition(
        entityType: InventoryAdjustmentSyncConstants.entityType,
        scopeKey: InventoryAdjustmentSyncConstants.scopeKey,
        pushPath: InventoryAdjustmentSyncConstants.pushPath,
        pullPath: InventoryAdjustmentSyncConstants.pullPath,
        applyHandler: InventoryAdjustmentDraftApplyHandler(),
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
