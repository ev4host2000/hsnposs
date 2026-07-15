import 'package:mizapos_desktop/services/cloud/sync/contract/field_spec.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/partner_sync_contract_config.dart';

/// Embedded Partner Field Dictionary v1.0.0 (client mirror of cloud customer/supplier).
abstract final class PartnerFieldDictionary {
  static String get version => PartnerSyncContractConfig.dictionaryVersion;

  static const String entityTypeCustomer = 'customer';
  static const String entityTypeSupplier = 'supplier';

  static const String pathCustomerCatalogPatch = 'customer_catalog_patch';
  static const String pathSupplierCatalogPatch = 'supplier_catalog_patch';

  static List<FieldSpec> patchableFieldsFor(String entityType) {
    final map = fieldsFor(entityType);
    return map.values
        .where((f) => f.patchable && !f.deprecated)
        .toList(growable: false);
  }

  static Map<String, FieldSpec> fieldsFor(String entityType) {
    if (entityType == entityTypeSupplier) {
      return _supplierFields;
    }
    return _customerFields;
  }

  static FieldSpec? field(String entityType, String name) =>
      fieldsFor(entityType)[name];

  static bool isPatchable(String entityType, String name) {
    final f = field(entityType, name);
    return f != null && f.patchable && !f.deprecated;
  }

  static final Map<String, FieldSpec> _customerFields = {
    for (final f in _customerFieldList) f.name: f,
  };

  static final Map<String, FieldSpec> _supplierFields = {
    for (final f in _supplierFieldList) f.name: f,
  };

  static const List<FieldSpec> _sharedFields = [
    FieldSpec(
      name: 'name',
      type: 'string',
      nullable: false,
      comparisonRule: 'string_default',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'phone',
      type: 'string',
      nullable: true,
      comparisonRule: 'string_default',
      patchable: true,
      syncable: true,
      emptyAsNull: true,
    ),
    FieldSpec(
      name: 'address',
      type: 'string',
      nullable: true,
      comparisonRule: 'string_default',
      patchable: true,
      syncable: true,
      emptyAsNull: true,
    ),
    FieldSpec(
      name: 'notes',
      type: 'string',
      nullable: true,
      comparisonRule: 'string_default',
      patchable: true,
      syncable: true,
      emptyAsNull: true,
    ),
    FieldSpec(
      name: 'partner_number',
      type: 'string',
      nullable: true,
      comparisonRule: 'string_default',
      patchable: true,
      syncable: true,
      emptyAsNull: true,
    ),
    FieldSpec(
      name: 'credit_limit',
      type: 'decimal',
      nullable: false,
      decimalScale: 4,
      defaultValue: 0,
      comparisonRule: 'decimal_scale',
      patchable: true,
      syncable: true,
    ),
    FieldSpec(
      name: 'overdue_alert_days',
      type: 'integer',
      nullable: true,
      comparisonRule: 'integer_default',
      patchable: true,
      syncable: true,
    ),
  ];

  static const List<FieldSpec> _customerFieldList = [
    ..._sharedFields,
    FieldSpec(
      name: 'customer_group_id',
      type: 'uuid',
      nullable: true,
      comparisonRule: 'uuid_canonical',
      patchable: true,
      syncable: true,
    ),
  ];

  static const List<FieldSpec> _supplierFieldList = [
    ..._sharedFields,
    FieldSpec(
      name: 'supplier_group_id',
      type: 'uuid',
      nullable: true,
      comparisonRule: 'uuid_canonical',
      patchable: true,
      syncable: true,
    ),
  ];
}
