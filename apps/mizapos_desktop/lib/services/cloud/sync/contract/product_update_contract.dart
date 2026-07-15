import 'dart:convert';

import 'package:mizapos_desktop/models/entities.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/change_detection_engine.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/product_field_dictionary.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/product_sync_contract_config.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_outbox_row.dart';

/// Result of building a product outbox intent under Update Contract v2 dual-mode.
class ProductOutboxIntent {
  const ProductOutboxIntent({
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

/// Builds Full or Patch product outbox payloads (M1 Dual-mode).
abstract final class ProductUpdateContract {
  /// Snapshot of patchable catalog fields from a cloud/full payload map.
  static Map<String, Object?> catalogSnapshotFromPayload(
    Map<String, dynamic> payload,
  ) {
    final out = <String, Object?>{};
    for (final field in ProductFieldDictionary.patchableFields) {
      if (payload.containsKey(field.name)) {
        out[field.name] = payload[field.name];
      }
    }
    return out;
  }

  /// Snapshot from local entity (+ optional image URL).
  static Map<String, Object?> catalogSnapshotFromEntity(
    ProductEntity product, {
    String? imageUrl,
    int sortOrder = 0,
  }) {
    return {
      'name': product.name,
      'sale_price': product.salePrice,
      'cost_price': product.costPrice,
      'barcode': product.barcode,
      'category_id': product.categoryId,
      'unit_name': product.unitName,
      'description': product.description,
      'image_url': imageUrl,
      'is_hidden': product.isHidden,
      'is_frozen': product.isFrozen,
      'is_service': product.isService,
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
  static ProductOutboxIntent buildIntent({
    required String operation,
    required String productId,
    required String organizationId,
    required String branchId,
    required String operationId,
    ProductEntity? product,
    Map<String, dynamic>? fullPayload,
    Map<String, Object?>? baseSnapshot,
    int? cloudRowVersion,
    String? imageUrl,
    int sortOrder = 0,
  }) {
    if (operation == 'delete') {
      return ProductOutboxIntent(
        operation: 'delete',
        payload: fullPayload ??
            {
              'id': productId,
              'company_id': organizationId,
              'branch_id': branchId,
              'deleted': true,
            },
        clientRowVersionHint: null,
      );
    }

    if (operation == 'create') {
      final payload = fullPayload ??
          (product != null
              ? productEntityToCloudPayload(product)
              : <String, dynamic>{});
      return ProductOutboxIntent(
        operation: 'create',
        payload: payload,
        clientRowVersionHint: null,
      );
    }

    // update
    final nextPayload = fullPayload ??
        (product != null
            ? productEntityToCloudPayload(product)
            : <String, dynamic>{});
    if (imageUrl != null && imageUrl.isNotEmpty) {
      nextPayload['image_url'] = imageUrl;
    }

    final usePatch = ProductSyncContractConfig.productsPatchEnabled &&
        cloudRowVersion != null &&
        cloudRowVersion >= 1 &&
        baseSnapshot != null &&
        baseSnapshot.isNotEmpty;

    if (!usePatch) {
      // M1 default / fallback: Full Entity (server Adapter).
      return ProductOutboxIntent(
        operation: 'update',
        payload: nextPayload,
        clientRowVersionHint: null,
      );
    }

    final nextSnap = product != null
        ? catalogSnapshotFromEntity(
            product,
            imageUrl: imageUrl ?? nextPayload['image_url']?.toString(),
            sortOrder: sortOrder,
          )
        : catalogSnapshotFromPayload(nextPayload);

    final changed = ChangeDetectionEngine.detect(
      baseSnapshot: baseSnapshot,
      nextSnapshot: nextSnap,
    );

    if (changed.isEmpty) {
      return const ProductOutboxIntent(
        operation: 'patch',
        payload: {},
        clientRowVersionHint: null,
        skipEnqueue: true,
      );
    }

    // Reject forbidden fields defensively.
    changed.removeWhere(
      (key, _) => !ProductFieldDictionary.isPatchable(key),
    );
    if (changed.isEmpty) {
      return const ProductOutboxIntent(
        operation: 'patch',
        payload: {},
        clientRowVersionHint: null,
        skipEnqueue: true,
      );
    }

    final payload = <String, dynamic>{
      'id': productId,
      'company_id': organizationId,
      'branch_id': branchId,
      'contract_version': ProductSyncContractConfig.contractVersion,
      'dictionary_version': ProductFieldDictionary.version,
      'base_row_version': cloudRowVersion,
      'operation_id': operationId,
      'changed_fields': changed,
      // Values also at top-level for list-style consumers (subset only).
      ...changed,
    };

    return ProductOutboxIntent(
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
