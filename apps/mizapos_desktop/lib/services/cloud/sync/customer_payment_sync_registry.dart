import 'package:mizapos_desktop/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_config.dart';
import 'package:mizapos_desktop/services/cloud/sync/customer_payment_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/customer_payment_draft_apply_handler.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_desktop/services/database_service.dart';

/// Registers customer payment draft/post with the transaction framework.
class CustomerPaymentSyncRegistry {
  CustomerPaymentSyncRegistry._();

  static void registerWith({
    required TransactionRegistry registry,
  }) {
    if (registry.isRegistered(CustomerPaymentSyncConstants.entityType)) {
      return;
    }

    registry.register(
      TransactionTypeDefinition(
        entityType: CustomerPaymentSyncConstants.entityType,
        scopeKey: CustomerPaymentSyncConstants.scopeKey,
        pushPath: CustomerPaymentSyncConstants.pushPath,
        pullPath: CustomerPaymentSyncConstants.pullPath,
        applyHandler: CustomerPaymentDraftApplyHandler(),
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
