import 'dart:async';

/// Propagates an absolute operation deadline through async calls using a Zone.
abstract final class CloudOperationDeadline {
  static final Object _zoneKey = Object();

  static Future<T> run<T>({
    required DateTime deadline,
    required Future<T> Function() action,
  }) {
    return runZoned(
      action,
      zoneValues: {_zoneKey: deadline.toUtc()},
    );
  }

  static Duration? get remaining {
    final deadline = Zone.current[_zoneKey];
    if (deadline is! DateTime) return null;
    final value = deadline.difference(DateTime.now().toUtc());
    return value.isNegative ? Duration.zero : value;
  }

  static Duration cap(Duration configured) {
    final budget = remaining;
    if (budget == null || budget >= configured) return configured;
    return budget;
  }
}
