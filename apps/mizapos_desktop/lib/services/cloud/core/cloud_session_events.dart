import 'dart:async';

/// أحداث جلسة Miza Cloud — انتهاء صلاحية، إلخ.
class CloudSessionEvents {
  CloudSessionEvents._();

  static final StreamController<void> _expiredController =
      StreamController<void>.broadcast();

  static Stream<void> get onSessionExpired => _expiredController.stream;

  static void notifySessionExpired() {
    if (!_expiredController.isClosed) {
      _expiredController.add(null);
    }
  }
}
