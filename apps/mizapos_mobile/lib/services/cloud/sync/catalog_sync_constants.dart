/// Catalog sync identifiers — mirrors cloud sync_changelog entity_type / entity_scope.
class CatalogSyncConstants {
  CatalogSyncConstants._();

  static const entityTypeProduct = 'product';
  static const entityTypeProductCategory = 'product_category';
  static const entityTypeProductUnit = 'product_unit';
  static const entityTypeTax = 'tax';
  static const entityTypePriceList = 'price_list';

  static const scopeKeyProducts = 'products';
  static const scopeKeyProductCategories = 'product_categories';
  static const scopeKeyProductUnits = 'product_units';
  static const scopeKeyTaxes = 'taxes';
  static const scopeKeyPriceLists = 'price_lists';

  static const syncStatePending = 'pending';
  static const syncStateSynced = 'synced';
  static const syncStateFailed = 'failed';

  /// Push order: masters before products.
  static const catalogPushEntityTypes = [
    entityTypeProductCategory,
    entityTypeProductUnit,
    entityTypeTax,
    entityTypePriceList,
    entityTypeProduct,
  ];

  /// Pull order: same as push.
  static const catalogPullScopes = [
    scopeKeyProductCategories,
    scopeKeyProductUnits,
    scopeKeyTaxes,
    scopeKeyPriceLists,
    scopeKeyProducts,
  ];

  static const allCatalogEntityTypes = catalogPushEntityTypes;
}
