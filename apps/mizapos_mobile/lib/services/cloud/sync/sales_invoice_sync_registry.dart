import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/sales_invoice_draft_apply_handler.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_registry.dart';
import 'package:mizapos_mobile/services/database_service.dart';

/// Registers sales invoice draft with the transaction framework.
class SalesInvoiceSyncRegistry {
  SalesInvoiceSyncRegistry._();

  static void registerWith({
    required TransactionRegistry registry,
  }) {
    if (registry.isRegistered(SalesInvoiceSyncConstants.entityType)) {
      return;
    }

    registry.register(
      TransactionTypeDefinition(
        entityType: SalesInvoiceSyncConstants.entityType,
        scopeKey: SalesInvoiceSyncConstants.scopeKey,
        pushPath: SalesInvoiceSyncConstants.pushPath,
        pullPath: SalesInvoiceSyncConstants.pullPath,
        applyHandler: SalesInvoiceDraftApplyHandler(),
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
