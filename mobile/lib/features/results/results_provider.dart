// File 8 of 12 — Module 4 (updated Module 5)
// mobile/lib/features/results/results_provider.dart
//
// Drives the results screen: fetches nearby services, starts ping timer,
// handles SMS location share, and emergency resolution.
//
// Module 5 changes:
//   • _cacheServices now delegates to OfflineService.cacheServices()
//   • _loadFromCache now delegates to OfflineService.readCachedServices()
//   • Removed _cachedServiceToModel (moved into OfflineService)
//
// Architecture rules:
//   • Shows cached data while fetching fresh (offline-first)
//   • Trust score >= 3 filter applied in emergency mode
//   • Ping timer sends GPS updates every AppConfig.emergencyPingIntervalSeconds
//   • resolveEmergency() sets emergencyResolved flag — screen navigates to home

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../data/local/database.dart';
import '../../data/models/service_model.dart';
import '../../data/models/victim_detail.dart';
import '../../data/remote/api_client.dart';
import '../../services/location_service.dart';
import '../../services/offline_service.dart';
import '../../services/osm_service.dart';
import '../../services/places_service.dart';
import '../../services/sms_service.dart';

part 'results_provider.g.dart';

// ── Data source enum ───────────────────────────────────────────────────────────

/// Where the currently displayed services came from.
enum ServicesSource {
  /// Live data fetched from the custom backend API.
  api,

  /// Real data fetched from Geoapify / Google Places.
  osm,

  /// Previously fetched real data loaded from the local SQLite cache.
  cache,

  /// All sources failed — no services to display.
  unavailable,
}

// ── State ──────────────────────────────────────────────────────────────────────

class ResultsState {
  const ResultsState({
    required this.sessionId,
    required this.emergencyType,
    required this.victimType,
    required this.victimDetails,
    required this.servicesByCategory,
    required this.allServices,
    required this.isLoading,
    required this.isOnline,
    required this.dataSource,
    required this.countryCode,
    required this.emergencyNumbers,
    required this.locationShared,
    required this.emergencyResolved,
    this.victimCount,
    this.position,
  });

  final String sessionId;
  final String emergencyType;
  final String victimType;
  final int? victimCount;
  final List<VictimDetail> victimDetails;
  final Position? position;

  /// Services grouped by category string.
  final Map<String, List<ServiceModel>> servicesByCategory;

  /// Flat list of all services for easy iteration.
  final List<ServiceModel> allServices;

  final bool isLoading;
  final bool isOnline;

  /// Where the currently displayed services came from.
  final ServicesSource dataSource;

  final String countryCode;
  final Map<String, String> emergencyNumbers;

  /// True once the user has tapped "Share location via SMS".
  final bool locationShared;

  /// True after resolveEmergency() completes — triggers navigation to home.
  final bool emergencyResolved;

  factory ResultsState.empty() => const ResultsState(
        sessionId: '',
        emergencyType: 'accident',
        victimType: 'self',
        victimDetails: [],
        servicesByCategory: {},
        allServices: [],
        isLoading: true,
        isOnline: true,
        dataSource: ServicesSource.unavailable,
        countryCode: 'IN',
        emergencyNumbers: {
          'police': '100',
          'ambulance': '108',
          'fire': '101',
          'unified': '112',
        },
        locationShared: false,
        emergencyResolved: false,
      );

  ResultsState copyWith({
    String? sessionId,
    String? emergencyType,
    String? victimType,
    int? victimCount,
    List<VictimDetail>? victimDetails,
    Position? position,
    Map<String, List<ServiceModel>>? servicesByCategory,
    List<ServiceModel>? allServices,
    bool? isLoading,
    bool? isOnline,
    ServicesSource? dataSource,
    String? countryCode,
    Map<String, String>? emergencyNumbers,
    bool? locationShared,
    bool? emergencyResolved,
  }) =>
      ResultsState(
        sessionId: sessionId ?? this.sessionId,
        emergencyType: emergencyType ?? this.emergencyType,
        victimType: victimType ?? this.victimType,
        victimCount: victimCount ?? this.victimCount,
        victimDetails: victimDetails ?? this.victimDetails,
        position: position ?? this.position,
        servicesByCategory: servicesByCategory ?? this.servicesByCategory,
        allServices: allServices ?? this.allServices,
        isLoading: isLoading ?? this.isLoading,
        isOnline: isOnline ?? this.isOnline,
        dataSource: dataSource ?? this.dataSource,
        countryCode: countryCode ?? this.countryCode,
        emergencyNumbers: emergencyNumbers ?? this.emergencyNumbers,
        locationShared: locationShared ?? this.locationShared,
        emergencyResolved: emergencyResolved ?? this.emergencyResolved,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

/// Drives the results screen. Auto-disposes on pop.
///
/// Family keys: sessionId, emergencyType, victimType, lat, lng, victimCount,
/// victimDetailsJson. Stable primitive types allow Riverpod to cache correctly.
@riverpod
class ResultsNotifier extends _$ResultsNotifier {
  Timer? _pingTimer;

  @override
  Future<ResultsState> build({
    required String sessionId,
    required String emergencyType,
    required String victimType,
    double? lat,
    double? lng,
    int? victimCount,
    String victimDetailsJson = '[]',
    String nonEmergencyCategory = '',
  }) async {
    ref.onDispose(() {
      _pingTimer?.cancel();
      _pingTimer = null;
    });

    // Reconstruct victim details from JSON string (family param must be primitive).
    final victimDetails = _parseVictimDetails(victimDetailsJson);

    // Reconstruct a lightweight Position-like object from lat/lng primitives.
    final pos = (lat != null && lng != null)
        ? await _positionFromLatLng(lat, lng)
        : null;

    // Detect country first so emergency numbers load for the right locale.
    final countryCode = await _detectCountryCode(pos);
    final numbers = await _loadEmergencyNumbers(emergencyType,
        countryCode: countryCode);

    final initial = ResultsState(
      sessionId: sessionId,
      emergencyType: emergencyType,
      victimType: victimType,
      victimCount: victimCount,
      victimDetails: victimDetails,
      position: pos,
      servicesByCategory: const {},
      allServices: const [],
      isLoading: true,
      isOnline: true,
      dataSource: ServicesSource.unavailable,
      countryCode: countryCode,
      emergencyNumbers: numbers,
      locationShared: false,
      emergencyResolved: false,
    );

    state = AsyncData(initial);

    // Fetch services without blocking build().
    unawaited(_fetchServices());

    // Ping timer only makes sense during an active emergency session.
    if (nonEmergencyCategory.isEmpty) _startPingTimer();

    return initial;
  }

  // ── Public actions ─────────────────────────────────────────────────────────

  /// Opens the native SMS app pre-filled with a location-share message.
  Future<void> shareLocationViaSMS() async {
    final cur = state.valueOrNull ?? ResultsState.empty();
    final pos = cur.position;
    if (pos == null) {
      debugPrint('[ResultsNotifier] No position for SMS share');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final contacts = prefs.getStringList('emergency_contacts') ?? [];
      final userName = prefs.getString('user_name');
      final sms = ref.read(smsServiceProvider);

      await sms.sendLocationUpdate(
        lat: pos.latitude,
        lng: pos.longitude,
        contactNumbers: contacts,
        userName: userName,
      );

      state = AsyncData(cur.copyWith(locationShared: true));
    } catch (e) {
      debugPrint('[ResultsNotifier] shareLocationViaSMS error: $e');
    }
  }

  /// Resolves the emergency, stops pinging, and flags navigation to home.
  Future<void> resolveEmergency() async {
    _pingTimer?.cancel();
    _pingTimer = null;

    final cur = state.valueOrNull ?? ResultsState.empty();

    // Mark resolved in SQLite
    try {
      final db = ref.read(databaseProvider);
      await db.emergencyDao.markSessionResolved(cur.sessionId);
    } catch (e) {
      debugPrint('[ResultsNotifier] SQLite resolve error: $e');
    }

    // Fire-and-forget to API (skipped when no real backend is configured)
    const defaultUrl = 'http://10.0.2.2:8000';
    const apiUrl = AppConstants.apiBaseUrl;
    if (apiUrl.isNotEmpty && apiUrl != defaultUrl) {
      ref.read(apiClientProvider).resolveEmergency(cur.sessionId).ignore();
    }

    state = AsyncData(cur.copyWith(emergencyResolved: true));
  }

  // ── Service fetching ───────────────────────────────────────────────────────
  //
  // Reliability-first chain:
  //   1. Custom backend API    — curated, highest quality
  //   2. Geoapify / Google Places — real POIs, global
  //   3. SQLite cache (via OfflineService) — previously fetched real data
  //   4. Unavailable state     — honest error + national emergency numbers

  Future<void> _fetchServices() async {
    final cur = state.valueOrNull ?? ResultsState.empty();

    // GPS may not have resolved yet — fetch fresh if missing.
    Position? pos = cur.position;
    if (pos == null) {
      debugPrint('[ResultsNotifier] Position null — fetching from GPS');
      pos = await ref.read(locationServiceProvider).getCurrentLocation();
      if (pos != null) {
        state = AsyncData((state.valueOrNull ?? cur).copyWith(position: pos));
      }
    }

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity.any((r) => r != ConnectivityResult.none);

    final categories = _getPriorityCategories(
        cur.emergencyType, cur.victimDetails, cur.victimType);

    const defaultUrl = 'http://10.0.2.2:8000';
    const apiUrl = AppConstants.apiBaseUrl;
    final backendAvailable = apiUrl.isNotEmpty && apiUrl != defaultUrl;

    if (isOnline && pos != null) {
      // ── Step 1: Custom backend ─────────────────────────────────────────────
      if (backendAvailable) {
        try {
          final raw = await ref.read(apiClientProvider).getNearbyServices(
                lat: pos.latitude,
                lng: pos.longitude,
                countryCode: cur.countryCode,
                minTrustScore: AppConfig.minTrustScoreEmergency,
              );
          if (raw.isNotEmpty) {
            final services = _attachDistances(raw, pos);
            unawaited(_cacheServices(services, pos));
            _applyServicesState(cur, services,
                isOnline: true, source: ServicesSource.api);
            debugPrint(
                '[ResultsNotifier] Loaded ${services.length} services from API');
            return;
          }
          debugPrint('[ResultsNotifier] API empty — trying Places');
        } catch (e) {
          debugPrint('[ResultsNotifier] API failed: $e — trying Places');
        }
      } else {
        debugPrint(
            '[ResultsNotifier] Backend skipped (emulator URL) — going to Places');
      }

      // ── Step 2: Geoapify / Google Places ──────────────────────────────────
      try {
        final places = PlacesService(
          geoapifyKey: AppConstants.geoapifyApiKey,
          googlePlacesKey: AppConstants.googlePlacesApiKey,
        );
        final services = await places.fetchNearbyServices(
          lat: pos.latitude,
          lng: pos.longitude,
          categories: categories,
          countryCode: cur.countryCode,
        );
        if (services.isNotEmpty) {
          unawaited(_cacheServices(services, pos));
          _applyServicesState(cur, services,
              isOnline: true, source: ServicesSource.osm);
          debugPrint(
              '[ResultsNotifier] Loaded ${services.length} services '
              '(source: ${services.first.source})');
          return;
        }
        debugPrint('[ResultsNotifier] Places empty — trying OSM');
      } catch (e) {
        debugPrint('[ResultsNotifier] Places failed: $e — trying OSM');
      }

      // ── Step 3: OSM Overpass ──────────────────────────────────────────────
      try {
        final osm = OsmService();
        final services = await osm.fetchNearbyServices(
          lat: pos.latitude,
          lng: pos.longitude,
          categories: categories,
          countryCode: cur.countryCode,
        );
        if (services.isNotEmpty) {
          unawaited(_cacheServices(services, pos));
          _applyServicesState(cur, services,
              isOnline: true, source: ServicesSource.osm);
          debugPrint('[ResultsNotifier] Loaded ${services.length} services from OSM');
          return;
        }
        debugPrint('[ResultsNotifier] OSM empty — trying cache');
      } catch (e) {
        debugPrint('[ResultsNotifier] OSM failed: $e — trying cache');
      }
    } else {
      debugPrint('[ResultsNotifier] Offline — going straight to cache');
    }

    // ── Step 4: SQLite cache via OfflineService ────────────────────────────
    await _loadFromCache(cur, pos, categories, isOnline: isOnline);
  }

  /// Applies services to state with given [source] badge.
  void _applyServicesState(
    ResultsState cur,
    List<ServiceModel> services, {
    required bool isOnline,
    required ServicesSource source,
  }) {
    state = AsyncData(
      (state.valueOrNull ?? cur).copyWith(
        servicesByCategory: _groupByCategory(services),
        allServices: services,
        isLoading: false,
        isOnline: isOnline,
        dataSource: source,
      ),
    );
  }

  /// Attaches haversine distances and sorts by distance ascending.
  List<ServiceModel> _attachDistances(
      List<ServiceModel> services, Position pos) {
    return services
        .map((s) {
          final d = _haversine(pos.latitude, pos.longitude, s.lat, s.lng);
          return s.copyWith(distanceKm: d);
        })
        .toList()
      ..sort((a, b) => (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999));
  }

  /// Caches services via [OfflineService] — fire-and-forget safe.
  Future<void> _cacheServices(List<ServiceModel> services, Position pos) async {
    await ref.read(offlineServiceProvider).cacheServices(
          services,
          lat: pos.latitude,
          lng: pos.longitude,
        );
  }

  /// Loads from SQLite cache via [OfflineService]. Shows unavailable if empty.
  Future<void> _loadFromCache(
    ResultsState cur,
    Position? pos,
    List<String> categories, {
    required bool isOnline,
  }) async {
    try {
      final offline = ref.read(offlineServiceProvider);
      final cached = <ServiceModel>[];

      for (final cat in categories) {
        final rows = await offline.readCachedServices(
          lat: pos?.latitude ?? 0,
          lng: pos?.longitude ?? 0,
          radiusKm: AppConfig.defaultUrbanRadiusKm.toDouble(),
          category: cat,
          minTrustScore: AppConfig.minTrustScoreEmergency,
        );
        cached.addAll(rows);
      }

      if (cached.isNotEmpty) {
        cached.sort(
            (a, b) => (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999));
        _applyServicesState(cur, cached,
            isOnline: isOnline, source: ServicesSource.cache);
        debugPrint(
            '[ResultsNotifier] Loaded ${cached.length} services from cache');
        return;
      }
    } catch (e) {
      debugPrint('[ResultsNotifier] Cache read error: $e');
    }

    // Nothing available — show honest unavailable state.
    debugPrint('[ResultsNotifier] No services available from any source');
    state = AsyncData(
      (state.valueOrNull ?? cur).copyWith(
        servicesByCategory: const {},
        allServices: const [],
        isLoading: false,
        isOnline: isOnline,
        dataSource: ServicesSource.unavailable,
      ),
    );
  }

  // ── Ping timer ─────────────────────────────────────────────────────────────

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      Duration(seconds: AppConfig.emergencyPingIntervalSeconds),
      (_) async {
        try {
          final cur = state.valueOrNull;
          if (cur == null || cur.sessionId.isEmpty) return;

          final pos =
              await ref.read(locationServiceProvider).getCurrentLocation();
          if (pos == null) return;

          final db = ref.read(databaseProvider);
          await db.emergencyDao.insertPing(
            LocationPingsLocalCompanion(
              sessionId: Value(cur.sessionId),
              lat: Value(pos.latitude),
              lng: Value(pos.longitude),
              accuracyM: Value(pos.accuracy),
              pinggedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
            ),
          );

          const defaultUrl = 'http://10.0.2.2:8000';
          const pingUrl = AppConstants.apiBaseUrl;
          if (pingUrl.isNotEmpty && pingUrl != defaultUrl) {
            ref
                .read(apiClientProvider)
                .pingEmergency(
                  sessionId: cur.sessionId,
                  lat: pos.latitude,
                  lng: pos.longitude,
                  accuracyM: pos.accuracy,
                )
                .ignore();
          }
        } catch (e) {
          debugPrint('[ResultsNotifier] Ping error (non-fatal): $e');
        }
      },
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<String> _getPriorityCategories(
    String emergencyType,
    List<VictimDetail> victims,
    String victimType,
  ) {
    if (nonEmergencyCategory.isNotEmpty) return [nonEmergencyCategory];
    if (victimType == 'vehicle_only') return ['police', 'towing'];

    final cats = <String>[];
    if (emergencyType == 'accident' || emergencyType == 'medical') {
      cats.add('ambulance');
      cats.add('hospital');
    }
    if (emergencyType == 'fire' ||
        victims.any((v) => v.needsFireRescue)) {
      cats.add('fire');
    }
    if (!cats.contains('police')) cats.add('police');
    return cats;
  }

  Map<String, List<ServiceModel>> _groupByCategory(
    List<ServiceModel> services,
  ) {
    final map = <String, List<ServiceModel>>{};
    for (final s in services) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    return map;
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

  List<VictimDetail> _parseVictimDetails(String json) {
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => VictimDetail.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Position?> _positionFromLatLng(double lat, double lng) async {
    try {
      return Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _detectCountryCode(Position? pos) async {
    if (pos == null) return 'IN';
    try {
      return await ref.read(locationServiceProvider).getCountryCode(pos);
    } catch (_) {
      return 'IN';
    }
  }

  Future<Map<String, String>> _loadEmergencyNumbers(
    String emergencyType, {
    String countryCode = 'IN',
  }) async {
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
              'police', 'ambulance', 'fire', 'unified', 'nhai', 'traffic'
            ]) {
              if (e[key] != null) result[key] = e[key].toString();
            }
            return result;
          }
        }
      }
    } catch (_) {}
    return EmergencyNumbers.india;
  }
}
