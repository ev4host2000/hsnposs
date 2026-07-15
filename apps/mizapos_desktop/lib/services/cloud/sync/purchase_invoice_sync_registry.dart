import 'package:mizapos_desktop/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_config.dart';
import 'package:mizapos_desktop/services/cloud/sync/purchase_invoice_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/purchase_invoice_draft_apply_handler.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_desktop/services/database_service.dart';

/// Registers purchase invoice draft/post with the transaction framework.
class PurchaseInvoiceSyncRegistry {
  PurchaseInvoiceSyncRegistry._();

  static void registerWith({
    required TransactionRegistry registry,
  }) {
    if (registry.isRegistered(PurchaseInvoiceSyncConstants.entityType)) {
      return;
    }

    registry.register(
      TransactionTypeDefinition(
        entityType: PurchaseInvoiceSyncConstants.entityType,
        scopeKey: PurchaseInvoiceSyncConstants.scopeKey,
        pushPath: PurchaseInvoiceSyncConstants.pushPath,
        pullPath: PurchaseInvoiceSyncConstants.pullPath,
        applyHandler: PurchaseInvoiceDraftApplyHandler(),
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
