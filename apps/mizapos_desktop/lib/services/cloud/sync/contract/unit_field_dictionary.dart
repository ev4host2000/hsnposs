import 'package:mizapos_desktop/services/cloud/sync/contract/field_spec.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/unit_sync_contract_config.dart';

/// Embedded Product Unit Field Dictionary v1.0.0 (client mirror of cloud).
abstract final class UnitFieldDictionary {
  static String get version => UnitSyncContractConfig.dictionaryVersion;

  static const String entityType = 'product_unit';

  static const String pathCatalogPatch = 'product_unit_catalog_patch';

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
  ];
}
