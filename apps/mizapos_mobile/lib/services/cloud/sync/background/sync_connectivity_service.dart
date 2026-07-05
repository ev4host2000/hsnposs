import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

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

  Stream<bool> get onOnlineChanged => _onlineController.stream;

  bool get isOnline => _online;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _online = await _probeOnline();
    _subscription = _connectivity.onConnectivityChanged.listen((results) async {
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

  Future<bool> _probeOnline({bool force = false}) async {
    try {
      final results = await _connectivity.checkConnectivity();
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
    _onlineController.close();
  }
}
