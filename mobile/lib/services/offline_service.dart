// lib/services/offline_service.dart
// Module 5 — Offline-first data access layer.
//
// Single responsibility surface for all SQLite ↔ network sync operations:
//   • readCachedServices  — SQLite → ServiceModel list
//   • cacheServices       — ServiceModel list → SQLite (keyed by geo-region)
//   • loadEmergencyNumbers — asset JSON → country numbers map
//   • syncUnsyncedPings   — upload queued pings when connectivity restored
//   • clearExpiredCache   — prune rows older than AppConfig.offlineCacheExpiryDays

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/constants.dart';
import '../data/local/database.dart';
import '../data/models/service_model.dart';
import '../data/remote/api_client.dart';

part 'offline_service.g.dart';

class OfflineService {
  OfflineService({required AppDatabase db, required ApiClient apiClient})
      : _db = db,
        _apiClient = apiClient;

  final AppDatabase _db;
  final ApiClient _apiClient;

  // ── Service cache ────────────────────────────────────────────────────────────

  /// Returns cached [ServiceModel]s near [lat]/[lng] within [radiusKm].
  ///
  /// Optionally filtered by [category] and [minTrustScore]. Never throws —
  /// returns an empty list on any database error.
  Future<List<ServiceModel>> readCachedServices({
    required double lat,
    required double lng,
    double radiusKm = 10,
    String? category,
    int minTrustScore = 1,
  }) async {
    try {
      final rows = await _db.servicesDao.getNearbyServices(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        category: category,
        minTrustScore: minTrustScore,
      );
      return rows.map((r) => _rowToModel(r, lat, lng)).toList();
    } catch (e) {
      debugPrint('[OfflineService] readCachedServices error: $e');
      return const [];
    }
  }

  /// Writes [services] to the SQLite cache, keyed by a ~1-degree geo-region.
  ///
  /// Non-fatal — errors are logged and swallowed.
  Future<void> cacheServices(
    List<ServiceModel> services, {
    required double lat,
    required double lng,
  }) async {
    if (services.isEmpty) return;
    try {
      final regionId = '${(lat * 10).round()}_${(lng * 10).round()}';
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      for (final s in services) {
        await _db.servicesDao.insertService(
          CachedServicesCompanion(
            name: Value(s.name),
            category: Value(s.category),
            subcategory: Value(s.subcategory),
            lat: Value(s.lat),
            lng: Value(s.lng),
            phonePrimary: Value(s.phonePrimary),
            phoneSecondary: Value(s.phoneSecondary),
            address: Value(s.address),
            countryCode: Value(s.countryCode),
            stateCode: Value(s.stateCode),
            is24hr: Value(s.is24hr),
            trustScore: Value(s.trustScore),
            source: Value(s.source),
            regionId: Value(regionId),
            cachedAtMs: Value(nowMs),
          ),
        );
      }
      debugPrint(
          '[OfflineService] Cached ${services.length} services (region: $regionId)');
    } catch (e) {
      debugPrint('[OfflineService] cacheServices error (non-fatal): $e');
    }
  }

  // ── Emergency numbers ────────────────────────────────────────────────────────

  /// Loads emergency numbers for [countryCode] from the bundled asset JSON.
  ///
  /// Falls back to [EmergencyNumbers.india] if the country is not found.
  Future<Map<String, String>> loadEmergencyNumbers(String countryCode) async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/emergency_numbers.json');
      final list = jsonDecode(raw) as List<dynamic>;
      for (final targetCode in [countryCode, 'IN']) {
        for (final entry in list) {
          final e = entry as Map<String, dynamic>;
          if (e['country_code'] == targetCode) {
            final result = <String, String>{};
            for (final key in [
              'police', 'ambulance', 'fire', 'unified', 'nhai', 'traffic',
            ]) {
              if (e[key] != null) result[key] = e[key].toString();
            }
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('[OfflineService] loadEmergencyNumbers error: $e');
    }
    return Map.from(EmergencyNumbers.india);
  }

  // ── Ping sync ────────────────────────────────────────────────────────────────

  /// Uploads locally-queued location pings to the backend.
  ///
  /// Safe to call on every connectivity-restored event — skips immediately
  /// when no real backend is configured or when there are no unsynced pings.
  Future<void> syncUnsyncedPings() async {
    const defaultUrl = 'http://10.0.2.2:8000';
    const apiUrl = AppConstants.apiBaseUrl;
    if (apiUrl.isEmpty || apiUrl == defaultUrl) return;

    try {
      final pings = await _db.emergencyDao.getUnsyncedPings();
      if (pings.isEmpty) return;

      debugPrint('[OfflineService] Syncing ${pings.length} queued ping(s)');

      for (final ping in pings) {
        final ok = await _apiClient.pingEmergency(
          sessionId: ping.sessionId,
          lat: ping.lat,
          lng: ping.lng,
          accuracyM: ping.accuracyM,
        );
        if (ok) await _db.emergencyDao.markPingSynced(ping.id);
      }
    } catch (e) {
      debugPrint('[OfflineService] syncUnsyncedPings error (non-fatal): $e');
    }
  }

  // ── Decision tree ────────────────────────────────────────────────────────────

  /// Loads the offline AI decision tree from the bundled JSON asset.
  ///
  /// Returns a map keyed by scenario name (e.g. 'breakdown', 'accident_injury').
  /// Each entry has 'steps' (List<String>) and 'call_first' (String).
  Future<Map<String, dynamic>> getDecisionTrees() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/decision_trees.json');
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (e) {
      debugPrint('[OfflineService] getDecisionTrees error: $e');
      return const {};
    }
  }

  // ── Cache expiry ─────────────────────────────────────────────────────────────

  /// Prunes cached service rows older than [AppConfig.offlineCacheExpiryDays].
  Future<void> clearExpiredCache() async {
    try {
      await _db.servicesDao.clearOldCache(AppConfig.offlineCacheExpiryDays);
      debugPrint('[OfflineService] Expired cache cleared');
    } catch (e) {
      debugPrint('[OfflineService] clearExpiredCache error (non-fatal): $e');
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  ServiceModel _rowToModel(CachedService r, double userLat, double userLng) {
    return ServiceModel(
      id: r.id.toString(),
      name: r.name,
      category: r.category,
      subcategory: r.subcategory,
      lat: r.lat,
      lng: r.lng,
      phonePrimary: r.phonePrimary,
      phoneSecondary: r.phoneSecondary,
      address: r.address,
      countryCode: r.countryCode,
      stateCode: r.stateCode,
      is24hr: r.is24hr,
      trustScore: r.trustScore,
      source: r.source,
      isActive: true,
      distanceKm: _haversine(userLat, userLng, r.lat, r.lng),
    );
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

/// App-lifetime offline service — survives screen navigation.
@Riverpod(keepAlive: true)
OfflineService offlineService(OfflineServiceRef ref) {
  return OfflineService(
    db: ref.read(databaseProvider),
    apiClient: ref.read(apiClientProvider),
  );
}
