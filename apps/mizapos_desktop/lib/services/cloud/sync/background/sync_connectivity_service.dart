import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// جودة الرابط التقريبية لاختيار حجم دفعات المزامنة.
enum SyncLinkQuality {
  offline,
  constrained,
  standard,
  fast,
}

/// مراقبة حالة الاتصال — online/offline للمزامنة الخلفية.
class SyncConnectivityService {
  SyncConnectivityService({
    Connectivity? connectivity,
    Future<bool> Function()? onlineOverride,
  })  : _connectivity = connectivity ?? Connectivity(),
        _onlineOverride = onlineOverride;

  final Connectivity _connectivity;
  final Future<bool> Function()? _onlineOverride;

  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online = true;
  bool _started = false;
  SyncLinkQuality _linkQuality = SyncLinkQuality.standard;

  Stream<bool> get onOnlineChanged => _onlineController.stream;

  bool get isOnline => _online;

  SyncLinkQuality get linkQuality => _linkQuality;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _online = await _probeOnline();
    _subscription = _connectivity.onConnectivityChanged.listen((results) async {
      _linkQuality = _qualityFromResults(results);
      final next = _resultsOnline(results) && await _probeOnline(force: true);
      if (next == _online) return;
      _online = next;
      _onlineController.add(_online);
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }

  Future<bool> refresh() async {
    if (_onlineOverride != null) {
      _online = await _onlineOverride();
      return _online;
    }
    _online = await _probeOnline(force: true);
    return _online;
  }

  /// يحدّث جودة الرابط ويعيد حجم دفعة مناسب.
  Future<int> recommendedBatchSize({int fallback = 50}) async {
    try {
      final results = await _connectivity.checkConnectivity();
      _linkQuality = _qualityFromResults(results);
    } on Object {
      // نحتفظ بآخر تقدير معروف.
    }
    return batchSizeForQuality(_linkQuality, fallback: fallback);
  }

  Future<int> recommendedPullPageLimit({int fallback = 200}) async {
    final batch = await recommendedBatchSize(fallback: fallback ~/ 4);
    if (batch <= 25) return 100;
    if (batch >= 80) return 500;
    return fallback;
  }

  static int batchSizeForQuality(
    SyncLinkQuality quality, {
    int fallback = 50,
  }) {
    switch (quality) {
      case SyncLinkQuality.offline:
        return fallback;
      case SyncLinkQuality.constrained:
        return 20;
      case SyncLinkQuality.standard:
        return 50;
      case SyncLinkQuality.fast:
        return 100;
    }
  }

  bool _resultsOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    );
  }

  SyncLinkQuality _qualityFromResults(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return SyncLinkQuality.offline;
    }
    if (results.any(
      (r) =>
          r == ConnectivityResult.ethernet || r == ConnectivityResult.wifi,
    )) {
      return SyncLinkQuality.fast;
    }
    if (results.any((r) => r == ConnectivityResult.mobile)) {
      return SyncLinkQuality.constrained;
    }
    if (results.any((r) => r == ConnectivityResult.vpn)) {
      return SyncLinkQuality.standard;
    }
    return SyncLinkQuality.standard;
  }

  Future<bool> _probeOnline({bool force = false}) async {
    try {
      final results = await _connectivity.checkConnectivity();
      _linkQuality = _qualityFromResults(results);
      if (!_resultsOnline(results)) return false;
      return true;
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('SyncConnectivityService: probe failed: $e');
      }
      return force ? false : _online;
    }
  }

  void dispose() {
    unawaited(stop());
    unawaited(_onlineController.close());
  }
}
