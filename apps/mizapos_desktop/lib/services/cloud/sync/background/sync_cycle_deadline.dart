import 'dart:async';

class SyncCycleDeadline {
  SyncCycleDeadline(this.timeout)
      : startedAt = DateTime.now().toUtc(),
        _stopwatch = Stopwatch()..start() {
    _timer = Timer(timeout, _expire);
  }

  final Duration timeout;
  final DateTime startedAt;
  final Stopwatch _stopwatch;
  final Completer<void> _expiredSignal = Completer<void>();

  late final Timer _timer;
  bool _expired = false;
  String _phase = 'starting';

  DateTime get expiresAt => startedAt.add(timeout);
  Duration get elapsed => _stopwatch.elapsed;
  String get phase => _phase;
  bool get isExpired => _expired || elapsed >= timeout;

  void checkpoint(String phase) {
    _phase = phase;
    throwIfExpired();
  }

  void throwIfExpired() {
    if (isExpired) {
      _expire();
      throw exception();
    }
  }

  Future<T> runStep<T>(
    String phase,
    Future<T> Function() action,
  ) async {
    checkpoint(phase);
    final result = await action();
    checkpoint(phase);
    return result;
  }

  Future<void> wait(Duration delay, String phase) async {
    checkpoint(phase);
    final remaining = timeout - elapsed;
    if (remaining <= Duration.zero) throw exception();

    final waitCompleter = Completer<void>();
    final timer = Timer(
      delay < remaining ? delay : remaining,
      waitCompleter.complete,
    );
    try {
      await Future.any([waitCompleter.future, _expiredSignal.future]);
    } finally {
      timer.cancel();
    }
    checkpoint(phase);
  }

  SyncCycleTimeoutException exception() {
    return SyncCycleTimeoutException(
      timeout: timeout,
      elapsed: elapsed,
      phase: phase,
    );
  }

  void dispose() {
    _timer.cancel();
    _stopwatch.stop();
  }

  void _expire() {
    _expired = true;
    if (!_expiredSignal.isCompleted) {
      _expiredSignal.complete();
    }
  }
}

class SyncCycleTimeoutException implements Exception {
  const SyncCycleTimeoutException({
    required this.timeout,
    required this.elapsed,
    required this.phase,
  });

  final Duration timeout;
  final Duration elapsed;
  final String phase;

  @override
  String toString() {
    return 'sync_cycle_timeout: phase=$phase '
        'timeout_ms=${timeout.inMilliseconds} '
        'elapsed_ms=${elapsed.inMilliseconds}';
  }
}
