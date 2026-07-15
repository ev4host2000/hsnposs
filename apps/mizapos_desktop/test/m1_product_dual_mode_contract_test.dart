import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/change_detection_engine.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/product_field_dictionary.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/product_sync_contract_config.dart';
import 'package:mizapos_desktop/services/cloud/sync/contract/product_update_contract.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_push_event.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_push_rejected_event.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_push_partial_settler.dart';
import 'package:mizapos_desktop/models/entities.dart';

void main() {
  setUp(() {
    ProductSyncContractConfig.resetToM1Defaults();
  });

  group('M1 Dual-mode defaults', () {
    test('patch flag defaults to false (Full Entity)', () {
      expect(ProductSyncContractConfig.productsPatchEnabled, isFalse);
      expect(ProductSyncContractConfig.dictionaryVersion, '1.0.0');
      expect(ProductSyncContractConfig.contractVersion, 2);
    });
  });

  group('ChangeDetectionEngine', () {
    test('detects only changed decimal/name; ignores stock_qty', () {
      final base = <String, Object?>{
        'name': 'Milk',
        'sale_price': '6.5000',
        'cost_price': '5.0000',
        'barcode': '123',
        'is_hidden': false,
        'is_frozen': false,
        'is_service': false,
        'sort_order': 0,
      };
      final next = Map<String, Object?>.from(base)
        ..['sale_price'] = 9.0
        ..['name'] = 'Milk';
      final changed = ChangeDetectionEngine.detect(
        baseSnapshot: base,
        nextSnapshot: next,
      );
      expect(changed.keys, ['sale_price']);
      expect(changed['sale_price'], '9.0000');
    });

    test('decimal equal after scale is no change', () {
      final field = ProductFieldDictionary.field('sale_price')!;
      final a = ChangeDetectionEngine.normalize(field, 6.5);
      final b = ChangeDetectionEngine.normalize(field, '6.5000');
      expect(ChangeDetectionEngine.valuesEqual(field, a, b), isTrue);
    });

    test('image empty_as_null: blank equals null', () {
      final field = ProductFieldDictionary.field('image_url')!;
      final a = ChangeDetectionEngine.normalize(field, null);
      final b = ChangeDetectionEngine.normalize(field, '  ');
      expect(ChangeDetectionEngine.valuesEqual(field, a, b), isTrue);
    });

    test('nullable barcode null is allowed change', () {
      final changed = ChangeDetectionEngine.detect(
        baseSnapshot: {'barcode': '123', 'name': 'A', 'sale_price': 1, 'cost_price': 1, 'is_hidden': false, 'is_frozen': false, 'is_service': false, 'sort_order': 0},
        nextSnapshot: {'barcode': null, 'name': 'A', 'sale_price': 1, 'cost_price': 1, 'is_hidden': false, 'is_frozen': false, 'is_service': false, 'sort_order': 0},
      );
      expect(changed.containsKey('barcode'), isTrue);
      expect(changed['barcode'], isNull);
    });

    test('stock_qty is not patchable / not detected', () {
      expect(ProductFieldDictionary.isPatchable('stock_qty'), isFalse);
      final changed = ChangeDetectionEngine.detect(
        baseSnapshot: {'name': 'A', 'sale_price': 1, 'cost_price': 1, 'is_hidden': false, 'is_frozen': false, 'is_service': false, 'sort_order': 0},
        nextSnapshot: {'name': 'A', 'sale_price': 1, 'cost_price': 1, 'is_hidden': false, 'is_frozen': false, 'is_service': false, 'sort_order': 0},
      );
      expect(changed.containsKey('stock_qty'), isFalse);
    });
  });

  group('ProductUpdateContract Dual-mode', () {
    final product = ProductEntity(
      id: 'p1',
      organizationId: 'o1',
      branchId: 'b1',
      name: 'Milk',
      salePrice: 9,
      costPrice: 5,
      stockQty: 10,
    );

    test('Full Entity when flag off (BC default)', () {
      ProductSyncContractConfig.productsPatchEnabled = false;
      final intent = ProductUpdateContract.buildIntent(
        operation: 'update',
        productId: 'p1',
        organizationId: 'o1',
        branchId: 'b1',
        operationId: 'op1',
        product: product,
        baseSnapshot: {'name': 'Milk', 'sale_price': 6.5, 'cost_price': 5, 'is_hidden': false, 'is_frozen': false, 'is_service': false, 'sort_order': 0},
        cloudRowVersion: 5,
      );
      expect(intent.operation, 'update');
      expect(intent.payload.containsKey('changed_fields'), isFalse);
      expect(intent.payload['name'], 'Milk');
      expect(intent.skipEnqueue, isFalse);
    });

    test('Native patch when flag on + base present', () {
      ProductSyncContractConfig.productsPatchEnabled = true;
      final intent = ProductUpdateContract.buildIntent(
        operation: 'update',
        productId: 'p1',
        organizationId: 'o1',
        branchId: 'b1',
        operationId: 'op1',
        product: product,
        baseSnapshot: {
          'name': 'Milk',
          'sale_price': 6.5,
          'cost_price': 5,
          'is_hidden': false,
          'is_frozen': false,
          'is_service': false,
          'sort_order': 0,
        },
        cloudRowVersion: 5,
      );
      expect(intent.operation, 'patch');
      expect(intent.payload['base_row_version'], 5);
      expect(intent.payload['operation_id'], 'op1');
      expect(intent.payload['dictionary_version'], '1.0.0');
      expect(intent.payload['contract_version'], 2);
      final changed = intent.payload['changed_fields'] as Map;
      expect(changed.keys, ['sale_price']);
      expect(intent.payload.containsKey('stock_qty'), isFalse);
    });

    test('falls back to Full when cloud base missing', () {
      ProductSyncContractConfig.productsPatchEnabled = true;
      final intent = ProductUpdateContract.buildIntent(
        operation: 'update',
        productId: 'p1',
        organizationId: 'o1',
        branchId: 'b1',
        operationId: 'op1',
        product: product,
        cloudRowVersion: null,
        baseSnapshot: null,
      );
      expect(intent.operation, 'update');
    });

    test('skip enqueue when patch detects no changes', () {
      ProductSyncContractConfig.productsPatchEnabled = true;
      final same = ProductEntity(
        id: 'p1',
        organizationId: 'o1',
        branchId: 'b1',
        name: 'Milk',
        salePrice: 6.5,
        costPrice: 5,
        stockQty: 99,
      );
      final intent = ProductUpdateContract.buildIntent(
        operation: 'update',
        productId: 'p1',
        organizationId: 'o1',
        branchId: 'b1',
        operationId: 'op1',
        product: same,
        baseSnapshot: {
          'name': 'Milk',
          'sale_price': 6.5,
          'cost_price': 5,
          'is_hidden': false,
          'is_frozen': false,
          'is_service': false,
          'sort_order': 0,
        },
        cloudRowVersion: 5,
      );
      expect(intent.skipEnqueue, isTrue);
    });

    test('create stays full payload', () {
      ProductSyncContractConfig.productsPatchEnabled = true;
      final intent = ProductUpdateContract.buildIntent(
        operation: 'create',
        productId: 'p1',
        organizationId: 'o1',
        branchId: 'b1',
        operationId: 'op1',
        product: product,
        cloudRowVersion: 1,
        baseSnapshot: {},
      );
      expect(intent.operation, 'create');
      expect(intent.payload['stock_qty'], 10);
    });
  });

  group('SyncPushEvent Update Contract v2', () {
    test('toJson emits patch contract fields', () {
      final event = SyncPushEvent(
        outboxId: 'o1',
        entityType: 'product',
        entityId: 'p1',
        operation: 'patch',
        payloadJson: {
          'changed_fields': {'sale_price': '9.0000'},
          'base_row_version': 5,
          'operation_id': 'o1',
          'dictionary_version': '1.0.0',
          'contract_version': 2,
          'sale_price': '9.0000',
        },
        clientRowVersion: 6,
        changedFields: {'sale_price': '9.0000'},
        baseRowVersion: 5,
        operationId: 'o1',
        dictionaryVersion: '1.0.0',
        contractVersion: 2,
      );
      final json = event.toJson();
      expect(json['operation'], 'patch');
      expect(json['changed_fields'], isA<Map>());
      expect(json['base_row_version'], 5);
      expect(json['operation_id'], 'o1');
      expect(json['dictionary_version'], '1.0.0');
      expect(json['contract_version'], 2);
    });

    test('legacy update toJson has no contract fields', () {
      final event = SyncPushEvent(
        outboxId: 'o1',
        entityType: 'product',
        entityId: 'p1',
        operation: 'update',
        payloadJson: {'name': 'Milk', 'sale_price': 1},
        clientRowVersion: 2,
      );
      final json = event.toJson();
      expect(json.containsKey('changed_fields'), isFalse);
      expect(json.containsKey('base_row_version'), isFalse);
    });
  });

  group('version_conflict / no_op settlement', () {
    test('version_conflict marks failed and invokes rebuild hook', () async {
      final failed = <String, String>{};
      final synced = <String>[];
      final rebuilt = <String>[];
      await SyncPushPartialSettler.settle(
        claimedIds: ['a', 'b'],
        rejectedEvents: const [
          SyncPushRejectedEvent(outboxId: 'a', errorCode: 'version_conflict'),
        ],
        accepted: 1,
        duplicates: 0,
        batchId: 'batch',
        markFailed: (id, err) async => failed[id] = err,
        markSynced: ({required outboxIds, required batchId}) async {
          synced.addAll(outboxIds);
        },
        releaseClaims: (_) async {},
        operationByOutboxId: {'a': 'patch', 'b': 'update'},
        onVersionConflict: (id) async => rebuilt.add(id),
      );
      expect(failed['a'], 'version_conflict');
      expect(rebuilt, ['a']);
      expect(synced, ['b']);
    });

    test('explicit no_op reject is treated as synced', () async {
      final synced = <String>[];
      await SyncPushPartialSettler.settle(
        claimedIds: ['a'],
        rejectedEvents: const [
          SyncPushRejectedEvent(outboxId: 'a', errorCode: 'no_op'),
        ],
        accepted: 0,
        duplicates: 0,
        batchId: 'batch',
        markFailed: (_, __) async {},
        markSynced: ({required outboxIds, required batchId}) async {
          synced.addAll(outboxIds);
        },
        releaseClaims: (_) async {},
      );
      expect(synced, ['a']);
    });
  });

  group('Migration / BC / Offline / Retry semantics (pure)', () {
    test('BC: full intent unchanged when patch disabled', () {
      ProductSyncContractConfig.productsPatchEnabled = false;
      final intent = ProductUpdateContract.buildIntent(
        operation: 'update',
        productId: 'p1',
        organizationId: 'o1',
        branchId: 'b1',
        operationId: 'op',
        product: ProductEntity(
          id: 'p1',
          organizationId: 'o1',
          branchId: 'b1',
          name: 'X',
          salePrice: 1,
          costPrice: 1,
          stockQty: 1,
        ),
      );
      expect(intent.operation, 'update');
      expect(intent.payload['stock_qty'], 1);
    });

    test('Offline rebuild: after conflict, new base uses cloudRowVersion', () {
      ProductSyncContractConfig.productsPatchEnabled = true;
      // Simulate post-pull mirror at v6 then rebuild patch for price only.
      final intent = ProductUpdateContract.buildIntent(
        operation: 'update',
        productId: 'p1',
        organizationId: 'o1',
        branchId: 'b1',
        operationId: 'op-rebuild',
        product: ProductEntity(
          id: 'p1',
          organizationId: 'o1',
          branchId: 'b1',
          name: 'NewName',
          salePrice: 7.5,
          costPrice: 5,
          stockQty: 10,
        ),
        baseSnapshot: {
          'name': 'NewName',
          'sale_price': 6.5,
          'cost_price': 5,
          'is_hidden': false,
          'is_frozen': false,
          'is_service': false,
          'sort_order': 0,
        },
        cloudRowVersion: 6,
      );
      expect(intent.operation, 'patch');
      expect(intent.payload['base_row_version'], 6);
      expect((intent.payload['changed_fields'] as Map).keys, ['sale_price']);
    });

    test('Replay: identical operation_id preserved in patch payload', () {
      ProductSyncContractConfig.productsPatchEnabled = true;
      final intent = ProductUpdateContract.buildIntent(
        operation: 'update',
        productId: 'p1',
        organizationId: 'o1',
        branchId: 'b1',
        operationId: 'stable-op-id',
        product: ProductEntity(
          id: 'p1',
          organizationId: 'o1',
          branchId: 'b1',
          name: 'A',
          salePrice: 2,
          costPrice: 1,
          stockQty: 0,
        ),
        baseSnapshot: {
          'name': 'A',
          'sale_price': 1,
          'cost_price': 1,
          'is_hidden': false,
          'is_frozen': false,
          'is_service': false,
          'sort_order': 0,
        },
        cloudRowVersion: 3,
      );
      expect(intent.payload['operation_id'], 'stable-op-id');
    });

    test('Performance: detect on small snapshot is O(fields)', () {
      final base = <String, Object?>{
        'name': 'A',
        'sale_price': 1,
        'cost_price': 1,
        'is_hidden': false,
        'is_frozen': false,
        'is_service': false,
        'sort_order': 0,
      };
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5000; i++) {
        ChangeDetectionEngine.detect(
          baseSnapshot: base,
          nextSnapshot: {...base, 'sale_price': 1.0 + (i % 2)},
        );
      }
      sw.stop();
      expect(sw.elapsedMilliseconds < 2000, isTrue,
          reason: '5000 detects should be fast locally');
    });
  });
}
