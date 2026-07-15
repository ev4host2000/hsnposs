import 'package:mizapos_desktop/services/cloud/sync/contract/field_spec.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/product_sync_contract_config.dart';

/// Embedded Product Field Dictionary v1.0.0 (client mirror of cloud contract).
abstract final class ProductFieldDictionary {
  static String get version => ProductSyncContractConfig.dictionaryVersion;

  static const String entityType = 'product';

  static const String pathProductCatalogPatch = 'product_catalog_patch';

  static final Map<String, FieldSpec> fields = {
    for (final f in _fields) f.name: f,
  };

  static List<FieldSpec> get patchableFields => fields.values
      .where((f) => f.patchable && !f.deprecated)
      .toList(growable: false);

  static FieldSpec? field(String name) => fields[name];

  static bool isPatchable(String name) {
    final f = fields[name];
    return f != null && f.patchable && !f.deprecated;
  }

  static const List<FieldSpec> _fields = [
    FieldSpec(
      name: 'name',
      type: 'string',
      nullable: false,
      comparisonRule: 'string_default',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'sale_price',
      type: 'decimal',
      nullable: false,
      decimalScale: 4,
      comparisonRule: 'decimal_scale',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'cost_price',
      type: 'decimal',
      nullable: false,
      decimalScale: 4,
      comparisonRule: 'decimal_scale',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'barcode',
      type: 'string',
      nullable: true,
      comparisonRule: 'string_default',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'category_id',
      type: 'uuid',
      nullable: true,
      comparisonRule: 'uuid_canonical',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'unit_name',
      type: 'string',
      nullable: true,
      comparisonRule: 'string_default',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'description',
      type: 'string',
      nullable: true,
      comparisonRule: 'string_default',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'image_url',
      type: 'image_url',
      nullable: true,
      comparisonRule: 'image_url_special',
      patchable: true,
      syncable: true,
      emptyAsNull: true,
    ),
    FieldSpec(
      name: 'is_hidden',
      type: 'boolean',
      nullable: false,
      defaultValue: false,
      comparisonRule: 'boolean_default',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'is_frozen',
      type: 'boolean',
      nullable: false,
      defaultValue: false,
      comparisonRule: 'boolean_default',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'is_service',
      type: 'boolean',
      nullable: false,
      defaultValue: false,
      comparisonRule: 'boolean_default',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'sort_order',
      type: 'integer',
      nullable: false,
      defaultValue: 0,
      comparisonRule: 'integer_default',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'stock_qty',
      type: 'decimal',
      nullable: false,
      decimalScale: 4,
      defaultValue: 0,
      comparisonRule: 'decimal_scale',
      patchable: false,
      syncable: false,
      forbiddenOnEntityPaths: [pathProductCatalogPatch],
    ),
  ];
}
