import 'package:mizapos_desktop/services/cloud/sync/contract/field_spec.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/tax_sync_contract_config.dart';

/// Embedded Tax Field Dictionary v1.0.0 (client mirror of cloud).
abstract final class TaxFieldDictionary {
  static String get version => TaxSyncContractConfig.dictionaryVersion;

  static const String entityType = 'tax';

  static const String pathCatalogPatch = 'tax_catalog_patch';

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
      name: 'percent',
      type: 'decimal',
      nullable: false,
      decimalScale: 4,
      defaultValue: 0,
      comparisonRule: 'decimal_scale',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'is_default',
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
  ];
}
