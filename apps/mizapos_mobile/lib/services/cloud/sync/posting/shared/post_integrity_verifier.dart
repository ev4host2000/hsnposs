import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_context.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/models/posting_integrity_exception.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/shared/post_amounts.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:sqflite/sqflite.dart';

/// Shared pre-finalize integrity checks for sales/purchase post pipelines.
class PostIntegrityVerifier {
  PostIntegrityVerifier._();

  static Future<void> verify({
    required PostingContext context,
    required String referenceType,
    required Future<Map<String, Object?>?> Function(
      DatabaseExecutor txn,
      String documentId,
    ) loadReturn,
    required List<PostInventoryEffectView> inventory,
    required List<PostAccountingEffectView> accounting,
    String statusColumn = 'invoiceStatus',
  }) async {
    final idempotentReplay = context.stageData['idempotent_replay'] == true;
    final header = context.aggregate.header;
    final extra = header is MapTransactionHeader ? header.extra : const {};
    final invoiceId = header.id;

    if (inventory.isEmpty || accounting.isEmpty) {
      throw const PostingIntegrityException(
        'Inventory and accounting effects must be planned before integrity',
      );
    }

    final lines = _aggregateLineMaps(context.aggregate);
    if (lines.isEmpty) {
      throw const PostingIntegrityException('At least one line is required');
    }

    final lineSubtotal = _asDouble(extra['line_subtotal']);
    final discountAmount = _asDouble(extra['discount_amount']);
    final taxPercent = _asDouble(extra['tax_percent']);
    final headerTotal = _asDouble(extra['total']);

    if (headerTotal < -1e-9) {
      throw const PostingIntegrityException('Invoice total must not be negative');
    }
    if (discountAmount < -1e-9) {
      throw const PostingIntegrityException('Discount must not be negative');
    }
    if (taxPercent < -1e-9) {
      throw const PostingIntegrityException('Tax percent must not be negative');
    }

    var computedLineSum = 0.0;
    for (final line in lines) {
      final qty = _asDouble(line['quantity']);
      final price = line.containsKey('unit_price')
          ? _asDouble(line['unit_price'])
          : _asDouble(line['unit_cost']);
      if (qty <= 0) {
        throw const PostingIntegrityException('Line quantity must be > 0');
      }
      if (price < 0) {
        throw const PostingIntegrityException('Line unit price must not be negative');
      }
      computedLineSum += _asDouble(line['line_total'], fallback: qty * price);
    }

    if ((computedLineSum - lineSubtotal).abs() > 1e-6) {
      throw PostingIntegrityException(
        'Line subtotal mismatch: lines=$computedLineSum header=$lineSubtotal',
      );
    }

    final amounts = computePostAmounts(
      lines: lines,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      headerTotal: headerTotal,
    );

    final computedOnly = computePostAmounts(
      lines: lines,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
    );
    if ((computedOnly.grandTotal - headerTotal).abs() > 1e-6) {
      throw PostingIntegrityException(
        'Header total mismatch: computed=${computedOnly.grandTotal} header=$headerTotal',
      );
    }

    if ((amounts.grandTotal - headerTotal).abs() > 1e-6) {
      throw PostingIntegrityException(
        'Header total mismatch: computed=${amounts.grandTotal} header=$headerTotal',
      );
    }

    final taxable = (lineSubtotal - discountAmount).clamp(0.0, double.infinity);
    if ((amounts.lineSubtotal - lineSubtotal).abs() > 1e-6 ||
        (amounts.discountAmount - discountAmount).abs() > 1e-6) {
      throw const PostingIntegrityException('Discount or subtotal integrity failed');
    }
    if ((taxable * (taxPercent / 100.0) - amounts.taxAmount).abs() > 1e-6) {
      throw const PostingIntegrityException('Tax amount integrity failed');
    }

    if (inventory.length != lines.length) {
      throw PostingIntegrityException(
        'Stock movement count ${inventory.length} != line count ${lines.length}',
      );
    }

    var debitCreditSum = 0.0;
    for (final entry in accounting) {
      debitCreditSum += entry.amountSigned;
    }
    if (debitCreditSum.abs() > 1e-6) {
      throw PostingIntegrityException(
        'Accounting not balanced: sum(amount_signed)=$debitCreditSum',
      );
    }

    final seenIds = <String>{};
    for (final effect in inventory) {
      if (effect.movementId.isEmpty) {
        throw const PostingIntegrityException('Movement UUID is required');
      }
      if (!seenIds.add(effect.movementId)) {
        throw PostingIntegrityException('Duplicate movement UUID ${effect.movementId}');
      }
    }
    for (final effect in accounting) {
      if (effect.entryId.isEmpty) {
        throw const PostingIntegrityException('Accounting entry UUID is required');
      }
      if (!seenIds.add(effect.entryId)) {
        throw PostingIntegrityException('Duplicate accounting UUID ${effect.entryId}');
      }
    }

    if (!idempotentReplay) {
      final document = await loadReturn(context.txn, invoiceId);
      final dbStatus = (document?[statusColumn] ?? '').toString();
      if (dbStatus == 'posted') {
        throw const PostingIntegrityException(
          'Document is already posted',
        );
      }
    }

    final movementRows = await context.txn.query(
      'stockMovements',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, invoiceId],
    );
    if (movementRows.length > inventory.length) {
      throw PostingIntegrityException(
        'Unexpected stock movements in DB: ${movementRows.length}',
      );
    }

    final ledgerRows = await context.txn.query(
      'partnerLedger',
      columns: const ['id'],
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, invoiceId],
    );
    if (ledgerRows.length > accounting.length) {
      throw PostingIntegrityException(
        'Unexpected ledger entries in DB: ${ledgerRows.length}',
      );
    }
  }

  static List<Map<String, dynamic>> _aggregateLineMaps(
    TransactionAggregate aggregate,
  ) {
    return aggregate.lines.map((line) {
      if (line is MapTransactionLine) {
        return Map<String, dynamic>.from(line.fields)
          ..putIfAbsent('line_id', () => line.lineId);
      }
      return line.toJson();
    }).toList();
  }

  static double _asDouble(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class PostInventoryEffectView {
  const PostInventoryEffectView({required this.movementId});
  final String movementId;
}

class PostAccountingEffectView {
  const PostAccountingEffectView({
    required this.entryId,
    required this.amountSigned,
  });
  final String entryId;
  final double amountSigned;
}
