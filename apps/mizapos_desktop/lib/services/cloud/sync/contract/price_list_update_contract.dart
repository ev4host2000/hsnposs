import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/change_detection_engine.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/price_list_field_dictionary.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/price_list_sync_contract_config.dart';

/// Result of building a price-list outbox intent under Update Contract v2 dual-mode.
class PriceListOutboxIntent {
  const PriceListOutboxIntent({
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

/// Builds Full or Patch price-list outbox payloads (M1 Dual-mode).
///
/// Nested `items` are price-list nature (not Field Dictionary). M1 Full Entity
/// always includes items. Native patch is header-only; item mutations fall back
/// to Full update.
abstract final class PriceListUpdateContract {
  /// Snapshot of header fields + canonical items for change detection.
  static Map<String, Object?> catalogSnapshotFromPayload(
    Map<String, dynamic> payload,
  ) {
    final out = <String, Object?>{};
    for (final field in PriceListFieldDictionary.patchableFields()) {
      if (payload.containsKey(field.name)) {
        out[field.name] = payload[field.name];
      }
    }
    out['items'] = canonicalizeItems(payload['items']);
    return out;
  }

  /// Snapshot from local price-list values (header + items).
  static Map<String, Object?> catalogSnapshotFromValues({
    required String name,
    bool isDefault = false,
    int sortOrder = 0,
    List<Map<String, dynamic>> items = const [],
  }) {
    return {
      'name': name,
      'is_default': isDefault,
      'sort_order': sortOrder,
      'items': canonicalizeItems(items),
    };
  }

  /// Canonical items fingerprint: sorted by product_id, sale_price to 4dp.
  static List<Map<String, Object?>> canonicalizeItems(Object? raw) {
    if (raw is! List) return const [];
    final out = <Map<String, Object?>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final productId = (item['product_id'] ?? '').toString().trim();
      if (productId.isEmpty) continue;
      final priceRaw = item['sale_price'];
      final salePrice = priceRaw is num
          ? priceRaw.toDouble()
          : double.tryParse(priceRaw?.toString() ?? '') ?? 0.0;
      out.add({
        'product_id': productId,
        'sale_price': double.parse(salePrice.toStringAsFixed(4)),
      });
    }
    out.sort(
      (a, b) =>
          (a['product_id'] as String).compareTo(b['product_id'] as String),
    );
    return out;
  }

  static bool itemsEqual(Object? a, Object? b) {
    final ca = canonicalizeItems(a);
    final cb = canonicalizeItems(b);
    if (ca.length != cb.length) return false;
    for (var i = 0; i < ca.length; i++) {
      if (ca[i]['product_id'] != cb[i]['product_id']) return false;
      if (ca[i]['sale_price'] != cb[i]['sale_price']) return false;
    }
    return true;
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
  static PriceListOutboxIntent buildIntent({
    required String operation,
    required String entityId,
    required String organizationId,
    required String branchId,
    required String operationId,
    String? name,
    bool? isDefault,
    int? sortOrder,
    List<Map<String, dynamic>>? items,
    Map<String, dynamic>? fullPayload,
    Map<String, Object?>? baseSnapshot,
    int? cloudRowVersion,
  }) {
    if (operation == 'delete') {
      return PriceListOutboxIntent(
        operation: 'delete',
        payload: fullPayload ??
            priceListEntityCloudPayload(
              id: entityId,
              organizationId: organizationId,
              branchId: branchId,
              name: name ?? '',
              deleted: true,
            ),
        clientRowVersionHint: null,
      );
    }

    final resolvedName = name ?? fullPayload?['name']?.toString() ?? '';
    final resolvedDefault =
        isDefault ?? _asBool(fullPayload?['is_default']) ?? false;
    final resolvedSort =
        sortOrder ?? (fullPayload?['sort_order'] as num?)?.toInt() ?? 0;
    final resolvedItems = items ??
        _itemsFromPayload(fullPayload?['items']) ??
        const <Map<String, dynamic>>[];

    if (operation == 'create') {
      final payload = fullPayload ??
          priceListEntityCloudPayload(
            id: entityId,
            organizationId: organizationId,
            branchId: branchId,
            name: resolvedName,
            isDefault: resolvedDefault,
            sortOrder: resolvedSort,
            items: resolvedItems,
          );
      return PriceListOutboxIntent(
        operation: 'create',
        payload: payload,
        clientRowVersionHint: null,
      );
    }

    // update — M1 Full Entity always carries items.
    final nextPayload = fullPayload ??
        priceListEntityCloudPayload(
          id: entityId,
          organizationId: organizationId,
          branchId: branchId,
          name: resolvedName,
          isDefault: resolvedDefault,
          sortOrder: resolvedSort,
          items: resolvedItems,
        );

    final usePatch = PriceListSyncContractConfig.priceListsPatchEnabled &&
        cloudRowVersion != null &&
        cloudRowVersion >= 1 &&
        baseSnapshot != null &&
        baseSnapshot.isNotEmpty;

    if (!usePatch) {
      return PriceListOutboxIntent(
        operation: 'update',
        payload: nextPayload,
        clientRowVersionHint: null,
      );
    }

    final nextItems = canonicalizeItems(
      items ?? nextPayload['items'] ?? resolvedItems,
    );

    // Price-list nature: no items patch semantics — fall back to Full.
    if (!itemsEqual(baseSnapshot['items'], nextItems)) {
      return PriceListOutboxIntent(
        operation: 'update',
        payload: nextPayload,
        clientRowVersionHint: null,
      );
    }

    final fields = PriceListFieldDictionary.patchableFields();
    final nextSnap = catalogSnapshotFromValues(
      name: resolvedName,
      isDefault: resolvedDefault,
      sortOrder: resolvedSort,
      items: resolvedItems,
    );

    final changed = ChangeDetectionEngine.detect(
      baseSnapshot: baseSnapshot,
      nextSnapshot: nextSnap,
      fields: fields,
    );

    if (changed.isEmpty) {
      return const PriceListOutboxIntent(
        operation: 'patch',
        payload: {},
        clientRowVersionHint: null,
        skipEnqueue: true,
      );
    }

    changed.removeWhere(
      (key, _) => !PriceListFieldDictionary.isPatchable(key),
    );
    if (changed.isEmpty) {
      return const PriceListOutboxIntent(
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
      'contract_version': PriceListSyncContractConfig.contractVersion,
      'dictionary_version': PriceListFieldDictionary.version,
      'base_row_version': cloudRowVersion,
      'operation_id': operationId,
      'changed_fields': changed,
      ...changed,
    };

    return PriceListOutboxIntent(
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

  static List<Map<String, dynamic>>? _itemsFromPayload(Object? raw) {
    if (raw is! List) return null;
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        out.add(item);
      } else if (item is Map) {
        out.add(item.map((k, v) => MapEntry(k.toString(), v)));
      }
    }
    return out;
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
