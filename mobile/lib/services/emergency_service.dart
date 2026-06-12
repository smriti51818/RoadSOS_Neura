// File 11 of 12 — Module 4
// mobile/lib/services/emergency_service.dart
//
// Persistent emergency lifecycle service.
//
// Design rules:
//   • SQLite session created FIRST — before any network call
//   • API call is fire-and-forget — never blocks session creation
//   • Ping timer runs on AppConfig.emergencyPingIntervalSeconds cadence
//   • keepAlive: true — persists across screen navigations
//   • stopEmergency() cleans up timer and marks session resolved locally

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../data/local/database.dart';
import '../data/remote/api_client.dart';
import '../services/location_service.dart';
import '../services/sms_service.dart';

part 'emergency_service.g.dart';

class EmergencyService {
  EmergencyService({
    required ApiClient apiClient,
    required AppDatabase db,
    required LocationService locationService,
    required SMSService smsService,
  })  : _apiClient = apiClient,
        _db = db,
        _locationService = locationService,
        _smsService = smsService;

  final ApiClient _apiClient;
  final AppDatabase _db;
  final LocationService _locationService;
  // ignore: unused_field — reserved for live-location SMS updates in Module 6
  final SMSService _smsService;

  Timer? _pingTimer;
  String? _activeSessionId;

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get hasActiveEmergency => _activeSessionId != null;
  String? get activeSessionId => _activeSessionId;

  /// Starts an emergency session.
  ///
  /// Step 1: Writes to SQLite immediately — works with no network.
  /// Step 2: Fires API call in background (fire-and-forget).
  /// Step 3: Starts GPS ping timer.
  /// Step 4: Returns local sessionId immediately — never null.
  Future<String> startEmergency({
    required Position position,
    required String emergencyType,
    required String victimType,
    String? sessionId,
    String? userPhone,
    int? victimCount,
  }) async {
    final sid = sessionId ?? const Uuid().v4();

    // ── Step 1: Local session first ─────────────────────────────────────────
    try {
      await _db.emergencyDao.insertSession(
        EmergencySessionsLocalCompanion(
          sessionId: Value(sid),
          emergencyType: Value(emergencyType),
          victimType: Value(victimType),
          lat: Value(position.latitude),
          lng: Value(position.longitude),
          countryCode: const Value('IN'),
          isActive: const Value(true),
          startedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
          userPhone: Value(userPhone),
          victimCount: Value(victimCount),
        ),
      );
      debugPrint('[EmergencyService] Local session created: $sid');
    } catch (e) {
      debugPrint('[EmergencyService] SQLite session error (non-fatal): $e');
    }

    // ── Step 2: Active session reference ────────────────────────────────────
    _activeSessionId = sid;

    // ── Step 3: FastAPI → Neon DB (fire-and-forget) ─────────────────────────
    // The FastAPI backend writes the session to Neon DB.
    // Skipped when only the emulator localhost is configured.
    const _defaultUrl = 'http://10.0.2.2:8000';
    final apiUrl = AppConstants.apiBaseUrl;
    if (apiUrl.isNotEmpty && apiUrl != _defaultUrl) {
      Future(() async {
        try {
          await _apiClient.startEmergency(
            lat: position.latitude,
            lng: position.longitude,
            emergencyType: emergencyType,
            victimType: victimType,
            userPhone: userPhone,
            victimCount: victimCount,
          );
          debugPrint('[EmergencyService] Backend session registered → Neon ✓');
        } catch (e) {
          debugPrint('[EmergencyService] Backend session error (non-fatal): $e');
        }
      });
    }

    // ── Step 4: Start ping timer ─────────────────────────────────────────────
    _startPingTimer(sid, position);

    return sid;
  }

  /// Marks the session resolved and cancels the ping timer.
  Future<void> stopEmergency(String sessionId) async {
    _pingTimer?.cancel();
    _pingTimer = null;
    _activeSessionId = null;

    try {
      await _db.emergencyDao.markSessionResolved(sessionId);
      debugPrint('[EmergencyService] Session resolved locally: $sessionId');
    } catch (e) {
      debugPrint('[EmergencyService] SQLite resolve error (non-fatal): $e');
    }

    // Resolve in Neon via FastAPI (fire-and-forget)
    const defaultUrl = 'http://10.0.2.2:8000';
    const resolveUrl = AppConstants.apiBaseUrl;
    if (resolveUrl.isNotEmpty && resolveUrl != defaultUrl) {
      _apiClient.resolveEmergency(sessionId).ignore();
    }
  }

  Future<void> dispose() async {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // All database persistence is handled by the FastAPI backend → Neon DB.
  // Flutter only maintains a local SQLite queue (emergency_sessions_local,
  // location_pings_local) for offline resilience. These sync to Neon when
  // the backend becomes reachable via syncUnsyncedPings() in OfflineService.

  // ── Private helpers ────────────────────────────────────────────────────────

  void _startPingTimer(String sessionId, Position initialPos) {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      Duration(seconds: AppConfig.emergencyPingIntervalSeconds),
      (_) async {
        try {
          final pos = await _locationService.getCurrentLocation();
          if (pos == null) return;

          // Persist ping to SQLite (offline queue)
          await _db.emergencyDao.insertPing(
            LocationPingsLocalCompanion(
              sessionId: Value(sessionId),
              lat: Value(pos.latitude),
              lng: Value(pos.longitude),
              accuracyM: Value(pos.accuracy),
              pinggedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
            ),
          );

          // Relay ping to FastAPI → Neon DB when backend is configured
          const defaultUrl = 'http://10.0.2.2:8000';
          const pingUrl = AppConstants.apiBaseUrl;
          if (pingUrl.isNotEmpty && pingUrl != defaultUrl) {
            _apiClient
                .pingEmergency(
              sessionId: sessionId,
              lat: pos.latitude,
              lng: pos.longitude,
              accuracyM: pos.accuracy,
            )
                .ignore();
          }

          debugPrint(
            '[EmergencyService] Ping sent: '
            '${pos.latitude.toStringAsFixed(4)}, '
            '${pos.longitude.toStringAsFixed(4)}',
          );
        } catch (e) {
          debugPrint('[EmergencyService] Ping error (non-fatal): $e');
        }
      },
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Persistent emergency service — survives screen navigation.
///
/// keepAlive: true ensures the ping timer keeps running when the user
/// navigates from triage → results → back.
@Riverpod(keepAlive: true)
EmergencyService emergencyService(EmergencyServiceRef ref) {
  final svc = EmergencyService(
    apiClient: ref.read(apiClientProvider),
    db: ref.read(databaseProvider),
    locationService: ref.read(locationServiceProvider),
    smsService: ref.read(smsServiceProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
}
