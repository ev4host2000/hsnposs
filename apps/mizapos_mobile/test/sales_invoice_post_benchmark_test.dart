import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/sales_invoice/sales_invoice_posting_pipeline.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_post_local_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/sales_invoice_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/database_service.dart';

import 'isolated_test_database.dart';
import 'sync_integration_test_helpers.dart';

/// Reference benchmarks for sales-invoice post (not CI gates).
void main() {
  const companyId = '550e8400-e29b-41d4-a716-446655440000';
  const branchId = '660e8400-e29b-41d4-a716-446655440001';
  const customerId = 'c100e840-e29b-41d4-a716-446655440040';
  const productId = 'a100e840-e29b-41d4-a716-446655440020';
  const userId = '990e8400-e29b-41d4-a716-446655440004';

  late DatabaseService databaseService;

  setUpAll(() async {
    await setUpIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await tearDownIsolatedTestDatabase();
  });

  setUp(() async {
    databaseService = DatabaseService();
    await prepareSyncIntegrationTest(databaseService: databaseService);
  });

  Future<void> seedInvoices(int count) async {
    final db = await databaseService.database;
    for (final table in [
      'salesInvoices',
      'salesInvoiceItems',
      'stockMovements',
      'partnerLedger',
      'sync_outbox',
      'customers',
      'products',
    ]) {
      await db.delete(table);
    }

    await db.insert('customers', {
      'id': customerId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Bench Customer',
      'creditLimit': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('products', {
      'id': productId,
      'organizationId': companyId,
      'branchId': branchId,
      'name': 'Bench Product',
      'salePrice': 10.0,
      'costPrice': 5.0,
      'stockQty': 1000000.0,
      'isHidden': 0,
      'isFrozen': 0,
      'isService': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });

    for (var i = 0; i < count; i++) {
      final invoiceId =
          'b100e840-e29b-41d4-a716-4466554${(40000 + i).toString().padLeft(5, '0')}';
      final lineId =
          'b200e840-e29b-41d4-a716-4466554${(50000 + i).toString().padLeft(5, '0')}';
      await db.insert('salesInvoices', {
        'id': invoiceId,
        'organizationId': companyId,
        'branchId': branchId,
        'customerId': customerId,
        'invoiceDate': DateTime.now().toIso8601String(),
        'total': 20.0,
        'paymentType': 'cash',
        'invoiceStatus': 'draft',
        'createdBy': userId,
        'discountAmount': 0,
        'taxPercent': 0,
        'lineSubtotal': 20.0,
        'paidAmount': 0,
        'transactionVersion': 0,
        'rowVersion': 1,
      });
      await db.insert('salesInvoiceItems', {
        'id': lineId,
        'invoiceId': invoiceId,
        'productId': productId,
        'quantity': 2,
        'unitPrice': 10,
        'lineTotal': 20,
      });
    }
  }

  Future<Map<String, double>> benchmarkPost(int invoiceCount) async {
    await seedInvoices(invoiceCount);
    final db = await databaseService.database;
    final invoices = await db.query(
      'salesInvoices',
      columns: const ['id'],
      orderBy: 'id ASC',
    );

    final service = SalesInvoicePostLocalService(
      databaseService: databaseService,
    );

    final sw = Stopwatch()..start();
    for (final row in invoices) {
      final id = row['id']!.toString();
      final result = await service.postDraft(invoiceId: id);
      expect(result.ok, isTrue, reason: id);
    }
    sw.stop();

    return {
      'count': invoiceCount.toDouble(),
      'totalMs': sw.elapsedMilliseconds.toDouble(),
      'avgMs': sw.elapsedMilliseconds / invoiceCount,
    };
  }

  Future<Map<String, double>> benchmarkPipelineOnly(int invoiceCount) async {
    await seedInvoices(invoiceCount);
    final db = await databaseService.database;
    final invoices = await db.query('salesInvoices', columns: const ['id']);

    final sw = Stopwatch()..start();
    for (final row in invoices) {
      final invoiceId = row['id']!.toString();
      final lines = await db.query(
        'salesInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      final invoice = await db.query(
        'salesInvoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      final header = invoice.first;
      final aggregate = MapTransactionAggregate.fromParts(
        header: {
          'id': invoiceId,
          'company_id': header['organizationId'],
          'branch_id': header['branchId'],
          'document_type': 'sales_invoice',
          'status': 'draft',
          'transaction_version': header['transactionVersion'],
          'row_version': header['rowVersion'],
          'customer_id': header['customerId'],
          'total': header['total'],
          'line_subtotal': header['lineSubtotal'],
          'tax_percent': header['taxPercent'],
          'discount_amount': header['discountAmount'],
          'created_by_user_id': header['createdBy'],
        },
        lines: lines
            .map(
              (l) => {
                'line_id': l['id'],
                'product_id': l['productId'],
                'quantity': l['quantity'],
                'unit_price': l['unitPrice'],
                'line_total': l['lineTotal'],
              },
            )
            .toList(),
      );

      await db.transaction((txn) async {
        await SalesInvoicePostingPipeline.create().run(
          PostingContext(
            aggregate: aggregate,
            txn: txn,
            entityType: SalesInvoiceSyncConstants.entityType,
          ),
        );
      });
    }
    sw.stop();

    return {
      'count': invoiceCount.toDouble(),
      'totalMs': sw.elapsedMilliseconds.toDouble(),
      'avgMs': sw.elapsedMilliseconds / invoiceCount,
    };
  }

  test('performance report — post local service', () async {
    final report = <String, Map<String, double>>{};
    for (final n in [100, 500, 1000]) {
      report['post_$n'] = await benchmarkPost(n);
      report['sqlite_pipeline_$n'] = await benchmarkPipelineOnly(n);
    }

    // ignore: avoid_print
    print('\n=== Sales Invoice Post Performance Report ===');
    for (final entry in report.entries) {
      final data = entry.value;
      // ignore: avoid_print
      print(
        '${entry.key}: total=${data['totalMs']}ms avg=${data['avgMs']?.toStringAsFixed(2)}ms',
      );
    }
    // ignore: avoid_print
    print('Note: Push/Pull/HTTP require live backend — not measured here.');
    // ignore: avoid_print
    print('SQLite pipeline = pipeline stages only (no outbox).');
    // ignore: avoid_print
    print('Post local service = pipeline + outbox enqueue.\n');

    expect(report.length, 6);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
