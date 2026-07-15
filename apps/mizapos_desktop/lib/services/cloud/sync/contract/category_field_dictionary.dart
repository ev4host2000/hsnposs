import 'package:mizapos_desktop/services/cloud/sync/contract/category_sync_contract_config.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/field_spec.dart';

/// Embedded Product Category Field Dictionary v1.0.0 (client mirror of cloud).
abstract final class CategoryFieldDictionary {
  static String get version => CategorySyncContractConfig.dictionaryVersion;

  static const String entityType = 'product_category';

  static const String pathCatalogPatch = 'product_category_catalog_patch';

  static List<FieldSpec> patchableFields() {
    return fields.values
        .where((f) => f.patchable && !f.deprecated)
        .toList(growable: false);
  }

  static final Map<String, FieldSpec> fields = {
    for (final f in _fieldList) f.name: f,
  };

  static FieldSpec? field(String name) => fields[name];

  static bool isPatchable(String name) {
    final f = field(name);
    return f != null && f.patchable && !f.deprecated;
  }

  static const List<FieldSpec> _fieldList = [
    FieldSpec(
      name: 'name',
      type: 'string',
      nullable: false,
      comparisonRule: 'string_default',
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
  ];
}
