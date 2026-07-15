import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/change_detection_engine.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/tax_field_dictionary.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/tax_sync_contract_config.dart';

/// Result of building a tax outbox intent under Update Contract v2 dual-mode.
class TaxOutboxIntent {
  const TaxOutboxIntent({
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

/// Builds Full or Patch tax outbox payloads (M1 Dual-mode).
abstract final class TaxUpdateContract {
  /// Snapshot of patchable catalog fields from a cloud/full payload map.
  static Map<String, Object?> catalogSnapshotFromPayload(
    Map<String, dynamic> payload,
  ) {
    final out = <String, Object?>{};
    for (final field in TaxFieldDictionary.patchableFields()) {
      if (payload.containsKey(field.name)) {
        out[field.name] = payload[field.name];
      }
    }
    return out;
  }

  /// Snapshot from local tax values.
  static Map<String, Object?> catalogSnapshotFromValues({
    required String name,
    required double percent,
    bool isDefault = false,
    int sortOrder = 0,
  }) {
    return {
      'name': name,
      'percent': percent,
      'is_default': isDefault,
      'sort_order': sortOrder,
    };
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
  static TaxOutboxIntent buildIntent({
    required String operation,
    required String entityId,
    required String organizationId,
    required String branchId,
    required String operationId,
    String? name,
    double? percent,
    bool? isDefault,
    int? sortOrder,
    Map<String, dynamic>? fullPayload,
    Map<String, Object?>? baseSnapshot,
    int? cloudRowVersion,
  }) {
    if (operation == 'delete') {
      return TaxOutboxIntent(
        operation: 'delete',
        payload: fullPayload ??
            taxEntityCloudPayload(
              id: entityId,
              organizationId: organizationId,
              branchId: branchId,
              name: name ?? '',
              percent: percent ?? 0,
              isDefault: isDefault ?? false,
              sortOrder: sortOrder ?? 0,
              deleted: true,
            ),
        clientRowVersionHint: null,
      );
    }

    if (operation == 'create') {
      final payload = fullPayload ??
          taxEntityCloudPayload(
            id: entityId,
            organizationId: organizationId,
            branchId: branchId,
            name: name ?? '',
            percent: percent ?? 0,
            isDefault: isDefault ?? false,
            sortOrder: sortOrder ?? 0,
          );
      return TaxOutboxIntent(
        operation: 'create',
        payload: payload,
        clientRowVersionHint: null,
      );
    }

    // update
    final resolvedName = name ?? fullPayload?['name']?.toString() ?? '';
    final resolvedPercent = percent ??
        (fullPayload?['percent'] as num?)?.toDouble() ??
        0.0;
    final resolvedDefault = isDefault ??
        _asBool(fullPayload?['is_default']) ??
        false;
    final resolvedSort = sortOrder ??
        (fullPayload?['sort_order'] as num?)?.toInt() ??
        0;
    final nextPayload = fullPayload ??
        taxEntityCloudPayload(
          id: entityId,
          organizationId: organizationId,
          branchId: branchId,
          name: resolvedName,
          percent: resolvedPercent,
          isDefault: resolvedDefault,
          sortOrder: resolvedSort,
        );

    final usePatch = TaxSyncContractConfig.taxesPatchEnabled &&
        cloudRowVersion != null &&
        cloudRowVersion >= 1 &&
        baseSnapshot != null &&
        baseSnapshot.isNotEmpty;

    if (!usePatch) {
      return TaxOutboxIntent(
        operation: 'update',
        payload: nextPayload,
        clientRowVersionHint: null,
      );
    }

    final fields = TaxFieldDictionary.patchableFields();
    final nextSnap = name != null
        ? catalogSnapshotFromValues(
            name: resolvedName,
            percent: resolvedPercent,
            isDefault: resolvedDefault,
            sortOrder: resolvedSort,
          )
        : catalogSnapshotFromPayload(nextPayload);

    final changed = ChangeDetectionEngine.detect(
      baseSnapshot: baseSnapshot,
      nextSnapshot: nextSnap,
      fields: fields,
    );

    if (changed.isEmpty) {
      return const TaxOutboxIntent(
        operation: 'patch',
        payload: {},
        clientRowVersionHint: null,
        skipEnqueue: true,
      );
    }

    changed.removeWhere(
      (key, _) => !TaxFieldDictionary.isPatchable(key),
    );
    if (changed.isEmpty) {
      return const TaxOutboxIntent(
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
      'contract_version': TaxSyncContractConfig.contractVersion,
      'dictionary_version': TaxFieldDictionary.version,
      'base_row_version': cloudRowVersion,
      'operation_id': operationId,
      'changed_fields': changed,
      ...changed,
    };

    return TaxOutboxIntent(
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

  static bool? _asBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final v = value.toString().trim().toLowerCase();
    if (v == '1' || v == 'true' || v == 'yes') return true;
    if (v == '0' || v == 'false' || v == 'no') return false;
    return null;
  }
}
