/// Shared line/tax/total computation for transaction post pipelines.
class PostAmounts {
  const PostAmounts({
    required this.lineSubtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.grandTotal,
  });

  final double lineSubtotal;
  final double discountAmount;
  final double taxAmount;
  final double grandTotal;

  double get netAmount => grandTotal - taxAmount;
}

PostAmounts computePostAmounts({
  required List<Map<String, dynamic>> lines,
  required double discountAmount,
  required double taxPercent,
  double? headerTotal,
}) {
  var lineSubtotal = 0.0;
  for (final line in lines) {
    final qty = _lineDouble(line['quantity']);
    final price = _lineUnitPrice(line);
    lineSubtotal += _lineDouble(line['line_total'], fallback: qty * price);
  }
  final discount = discountAmount;
  final taxable = (lineSubtotal - discount).clamp(0.0, double.infinity);
  final tax = taxable * (taxPercent / 100.0);
  final computedTotal = taxable + tax;
  final grandTotal = headerTotal ?? computedTotal;
  return PostAmounts(
    lineSubtotal: lineSubtotal,
    discountAmount: discount,
    taxAmount: tax,
    grandTotal: grandTotal,
  );
}

double _lineUnitPrice(Map<String, dynamic> line) {
  if (line.containsKey('unit_price')) {
    return _lineDouble(line['unit_price']);
  }
  return _lineDouble(line['unit_cost']);
}

double _lineDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
