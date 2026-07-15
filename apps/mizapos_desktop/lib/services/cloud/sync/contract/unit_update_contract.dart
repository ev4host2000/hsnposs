import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/change_detection_engine.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/unit_field_dictionary.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/unit_sync_contract_config.dart';

/// Result of building a unit outbox intent under Update Contract v2 dual-mode.
class UnitOutboxIntent {
  const UnitOutboxIntent({
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

/// Builds Full or Patch unit outbox payloads (M1 Dual-mode, name-only).
abstract final class UnitUpdateContract {
  /// Snapshot of patchable catalog fields from a cloud/full payload map.
  static Map<String, Object?> catalogSnapshotFromPayload(
    Map<String, dynamic> payload,
  ) {
    final out = <String, Object?>{};
    for (final field in UnitFieldDictionary.patchableFields()) {
      if (payload.containsKey(field.name)) {
        out[field.name] = payload[field.name];
      }
    }
    return out;
  }

  /// Snapshot from local name.
  static Map<String, Object?> catalogSnapshotFromValues({
    required String name,
  }) {
    return {
      'name': name,
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
  static UnitOutboxIntent buildIntent({
    required String operation,
    required String entityId,
    required String organizationId,
    required String branchId,
    required String operationId,
    String? name,
    Map<String, dynamic>? fullPayload,
    Map<String, Object?>? baseSnapshot,
    int? cloudRowVersion,
  }) {
    if (operation == 'delete') {
      return UnitOutboxIntent(
        operation: 'delete',
        payload: fullPayload ??
            namedEntityCloudPayload(
              id: entityId,
              organizationId: organizationId,
              branchId: branchId,
              name: name ?? '',
              deleted: true,
            ),
        clientRowVersionHint: null,
      );
    }

    if (operation == 'create') {
      final payload = fullPayload ??
          namedEntityCloudPayload(
            id: entityId,
            organizationId: organizationId,
            branchId: branchId,
            name: name ?? '',
          );
      return UnitOutboxIntent(
        operation: 'create',
        payload: payload,
        clientRowVersionHint: null,
      );
    }

    // update
    final resolvedName = name ?? fullPayload?['name']?.toString() ?? '';
    final nextPayload = fullPayload ??
        namedEntityCloudPayload(
          id: entityId,
          organizationId: organizationId,
          branchId: branchId,
          name: resolvedName,
        );

    final usePatch = UnitSyncContractConfig.unitsPatchEnabled &&
        cloudRowVersion != null &&
        cloudRowVersion >= 1 &&
        baseSnapshot != null &&
        baseSnapshot.isNotEmpty;

    if (!usePatch) {
      return UnitOutboxIntent(
        operation: 'update',
        payload: nextPayload,
        clientRowVersionHint: null,
      );
    }

    final fields = UnitFieldDictionary.patchableFields();
    final nextSnap = name != null
        ? catalogSnapshotFromValues(name: resolvedName)
        : catalogSnapshotFromPayload(nextPayload);

    final changed = ChangeDetectionEngine.detect(
      baseSnapshot: baseSnapshot,
      nextSnapshot: nextSnap,
      fields: fields,
    );

    if (changed.isEmpty) {
      return const UnitOutboxIntent(
        operation: 'patch',
        payload: {},
        clientRowVersionHint: null,
        skipEnqueue: true,
      );
    }

    changed.removeWhere(
      (key, _) => !UnitFieldDictionary.isPatchable(key),
    );
    if (changed.isEmpty) {
      return const UnitOutboxIntent(
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
      'contract_version': UnitSyncContractConfig.contractVersion,
      'dictionary_version': UnitFieldDictionary.version,
      'base_row_version': cloudRowVersion,
      'operation_id': operationId,
      'changed_fields': changed,
      ...changed,
    };

    return UnitOutboxIntent(
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
