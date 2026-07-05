import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_constants.dart';

/// Customers & suppliers sync identifiers — mirrors cloud entity_type / entity_scope.
class PartnersSyncConstants {
  PartnersSyncConstants._();

  static const entityTypeCustomer = 'customer';
  static const entityTypeSupplier = 'supplier';

  static const scopeKeyCustomers = 'customers';
  static const scopeKeySuppliers = 'suppliers';

  static const catalogEntityTypes = CatalogSyncConstants.catalogPushEntityTypes;

  static const partnerEntityTypes = [
    entityTypeCustomer,
    entityTypeSupplier,
  ];

  static const partnerPushEntityTypes = partnerEntityTypes;

  static const partnerPullScopes = [
    scopeKeyCustomers,
    scopeKeySuppliers,
  ];
}
