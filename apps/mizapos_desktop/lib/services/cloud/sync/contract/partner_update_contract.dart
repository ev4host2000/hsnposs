import 'dart:convert';

import 'package:mizapos_desktop/models/entities.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/change_detection_engine.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/partner_field_dictionary.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/partner_sync_contract_config.dart';

/// Result of building a partner outbox intent under Update Contract v2 dual-mode.
class PartnerOutboxIntent {
  const PartnerOutboxIntent({
    required this.operation,
    required this.payload,
    required this.clientRowVersionHint,
    this.skipEnqueue = false,
  });

  /// create | update | patch | delete
  final String operation;
  final Map<String, dynamic> payload;

  /// Still used for BC client_row_version column / create path.
  final int? clientRowVersionHint;

  /// True when patch mode detected no changes (local no-op; do not enqueue).
  final bool skipEnqueue;
}

/// Builds Full or Patch partner outbox payloads (M1 Dual-mode).
abstract final class PartnerUpdateContract {
  /// Snapshot of patchable catalog fields from a cloud/full payload map.
  static Map<String, Object?> catalogSnapshotFromPayload(
    String entityType,
    Map<String, dynamic> payload,
  ) {
    final out = <String, Object?>{};
    for (final field in PartnerFieldDictionary.patchableFieldsFor(entityType)) {
      if (payload.containsKey(field.name)) {
        out[field.name] = payload[field.name];
      }
    }
    return out;
  }

  /// Snapshot from local master entity (+ optional group id).
  static Map<String, Object?> catalogSnapshotFromEntity(
    String entityType,
    MasterEntity entity, {
    String? customerGroupId,
    String? supplierGroupId,
  }) {
    final snap = <String, Object?>{
      'name': entity.name,
      'phone': entity.phone,
      'address': entity.address,
      'notes': entity.notes ??
          (entity.extra.trim().isEmpty ? null : entity.extra),
      'partner_number': entity.partnerNumber,
      'credit_limit': entity.creditLimit,
      'overdue_alert_days': entity.overdueAlertDays,
    };
    if (entityType == PartnerFieldDictionary.entityTypeCustomer) {
      snap['customer_group_id'] = customerGroupId;
    } else if (entityType == PartnerFieldDictionary.entityTypeSupplier) {
      snap['supplier_group_id'] = supplierGroupId;
    }
    return snap;
  }

  static String encodeSnapshot(Map<String, Object?> snapshot) {
    return jsonEncode(snapshot);
  }

  static Map<String, Object?> decodeSnapshot(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } on Object {
      /* ignore corrupt */
    }
    return {};
  }

  /// Decide Full vs Patch for an update (or create/delete pass-through).
  static PartnerOutboxIntent buildIntent({
    required String entityType,
    required String operation,
    required String entityId,
    required String organizationId,
    required String branchId,
    required String operationId,
    MasterEntity? entity,
    Map<String, dynamic>? fullPayload,
    Map<String, Object?>? baseSnapshot,
    int? cloudRowVersion,
    String? customerGroupId,
    String? supplierGroupId,
  }) {
    if (operation == 'delete') {
      return PartnerOutboxIntent(
        operation: 'delete',
        payload: fullPayload ??
            {
              'id': entityId,
              'company_id': organizationId,
              'branch_id': branchId,
              'deleted': true,
            },
        clientRowVersionHint: null,
      );
    }

    if (operation == 'create') {
      final payload = fullPayload ??
          (entity != null
              ? partnerEntityCloudPayload(
                  id: entity.id,
                  organizationId: entity.organizationId,
                  branchId: entity.branchId,
                  name: entity.name,
                  partnerNumber: entity.partnerNumber,
                  phone: entity.phone,
                  address: entity.address,
                  notes: entity.notes ??
                      (entity.extra.trim().isEmpty ? null : entity.extra),
                  creditLimit: entity.creditLimit,
                  overdueAlertDays: entity.overdueAlertDays,
                  customerGroupId: customerGroupId,
                  supplierGroupId: supplierGroupId,
                )
              : <String, dynamic>{});
      return PartnerOutboxIntent(
        operation: 'create',
        payload: payload,
        clientRowVersionHint: null,
      );
    }

    // update
    final nextPayload = fullPayload ??
        (entity != null
            ? partnerEntityCloudPayload(
                id: entity.id,
                organizationId: entity.organizationId,
                branchId: entity.branchId,
                name: entity.name,
                partnerNumber: entity.partnerNumber,
                phone: entity.phone,
                address: entity.address,
                notes: entity.notes ??
                    (entity.extra.trim().isEmpty ? null : entity.extra),
                creditLimit: entity.creditLimit,
                overdueAlertDays: entity.overdueAlertDays,
                customerGroupId: customerGroupId,
                supplierGroupId: supplierGroupId,
              )
            : <String, dynamic>{});

    final usePatch = PartnerSyncContractConfig.partnersPatchEnabled &&
        cloudRowVersion != null &&
        cloudRowVersion >= 1 &&
        baseSnapshot != null &&
        baseSnapshot.isNotEmpty;

    if (!usePatch) {
      return PartnerOutboxIntent(
        operation: 'update',
        payload: nextPayload,
        clientRowVersionHint: null,
      );
    }

    final fields = PartnerFieldDictionary.patchableFieldsFor(entityType);
    final nextSnap = entity != null
        ? catalogSnapshotFromEntity(
            entityType,
            entity,
            customerGroupId: customerGroupId ??
                nextPayload['customer_group_id']?.toString(),
            supplierGroupId: supplierGroupId ??
                nextPayload['supplier_group_id']?.toString(),
          )
        : catalogSnapshotFromPayload(entityType, nextPayload);

    final changed = ChangeDetectionEngine.detect(
      baseSnapshot: baseSnapshot,
      nextSnapshot: nextSnap,
      fields: fields,
    );

    if (changed.isEmpty) {
      return const PartnerOutboxIntent(
        operation: 'patch',
        payload: {},
        clientRowVersionHint: null,
        skipEnqueue: true,
      );
    }

    changed.removeWhere(
      (key, _) => !PartnerFieldDictionary.isPatchable(entityType, key),
    );
    if (changed.isEmpty) {
      return const PartnerOutboxIntent(
        operation: 'patch',
        payload: {},
        clientRowVersionHint: null,
        skipEnqueue: true,
      );
    }

    final payload = <String, dynamic>{
      'id': entityId,
      'company_id': organizationId,
      'branch_id': branchId,
      'contract_version': PartnerSyncContractConfig.contractVersion,
      'dictionary_version': PartnerFieldDictionary.version,
      'base_row_version': cloudRowVersion,
      'operation_id': operationId,
      'changed_fields': changed,
      ...changed,
    };

    return PartnerOutboxIntent(
      operation: 'patch',
      payload: payload,
      clientRowVersionHint: cloudRowVersion + 1,
    );
  }

  /// True when outbox payload/event is a native Update Contract v2 patch.
  static bool isNativePatchPayload(Map<String, dynamic> payload) {
    if (payload['changed_fields'] is Map) return true;
    final cv = payload['contract_version'];
    return cv == 2 || cv == '2' || cv == 'v2';
  }
}
