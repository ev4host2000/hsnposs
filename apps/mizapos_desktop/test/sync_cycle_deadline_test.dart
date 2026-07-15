import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_cycle_deadline.dart';

void main() {
  test('deadline interrupts retry waits without leaving a timer running',
      () async {
    final deadline = SyncCycleDeadline(const Duration(milliseconds: 30));
    final stopwatch = Stopwatch()..start();
    try {
      await expectLater(
        deadline.wait(const Duration(seconds: 5), 'retry_wait'),
        throwsA(
          isA<SyncCycleTimeoutException>()
              .having((e) => e.phase, 'phase', 'retry_wait'),
        ),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    } finally {
      deadline.dispose();
    }
  });

  test('an active atomic step settles before timeout is surfaced', () async {
    final deadline = SyncCycleDeadline(const Duration(milliseconds: 20));
    var operationSettled = false;
    try {
      await expectLater(
        deadline.runStep('sqlite_transaction', () async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          operationSettled = true;
        }),
        throwsA(
          isA<SyncCycleTimeoutException>()
              .having((e) => e.phase, 'phase', 'sqlite_transaction'),
        ),
      );
      expect(operationSettled, isTrue);
    } finally {
      deadline.dispose();
    }
  });
}
