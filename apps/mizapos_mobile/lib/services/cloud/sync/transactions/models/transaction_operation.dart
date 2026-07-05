/// Lifecycle operations for transaction aggregates — ADR-TX-005.
enum TransactionOperation {
  create,
  update,
  post,
  cancel;

  String get wireValue => name;

  static TransactionOperation? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final op in TransactionOperation.values) {
      if (op.name == raw) return op;
    }
    return null;
  }

  static TransactionOperation parseRequired(String raw) {
    return parse(raw) ??
        (throw FormatException('Unsupported transaction operation: $raw'));
  }
}
