// lib/services/connectivity_service.dart
// Module 5 — App-lifetime connectivity watcher.
//
// keepAlive: true so the subscription persists across screen navigations.
// Uses connectivity_plus v6 which returns List<ConnectivityResult>.
//
// Usage:
//   final svc = ref.read(connectivityServiceProvider);
//   svc.isOnline          // synchronous current state
//   svc.onConnectivityChanged  // Stream<bool> — true = online

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_service.g.dart';

class ConnectivityService {
  ConnectivityService() {
    _init();
  }

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Current connectivity state. Updated synchronously on change.
  bool get isOnline => _isOnline;

  /// Broadcasts true/false on every connectivity transition.
  Stream<bool> get onConnectivityChanged => _controller.stream;

  void _init() {
    // Seed with current state immediately.
    _connectivity.checkConnectivity().then((results) {
      _isOnline = _eval(results);
      if (!_controller.isClosed) _controller.add(_isOnline);
    });

    // Listen for future changes.
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = _eval(results);
      if (online == _isOnline) return; // skip no-op transitions
      _isOnline = online;
      if (!_controller.isClosed) _controller.add(_isOnline);
      debugPrint('[ConnectivityService] ${online ? 'Online ✓' : 'Offline ✗'}');
    });
  }

  /// Evaluates a v6 result list to a boolean.
  bool _eval(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<void> dispose() async {
    await _sub?.cancel();
    if (!_controller.isClosed) await _controller.close();
  }
}

/// App-lifetime connectivity service — survives screen navigation.
@Riverpod(keepAlive: true)
ConnectivityService connectivityService(ConnectivityServiceRef ref) {
  final svc = ConnectivityService();
  ref.onDispose(svc.dispose);
  return svc;
}
