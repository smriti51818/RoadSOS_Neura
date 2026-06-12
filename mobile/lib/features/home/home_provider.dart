// File 3 of 12 — Module 3 (updated Module 5)
// mobile/lib/features/home/home_provider.dart
//
// Drives the home screen state:
//   - Location + country detection
//   - Emergency numbers lookup
//   - Battery monitoring
//   - Nearest-services fetch (live or offline cache via OfflineService)
//   - Emergency / Non-Emergency mode toggle
//
// Module 5 changes:
//   - Wired ConnectivityService (keepAlive) for live isOnline updates
//   - Fixed connectivity_plus v6 API (List<ConnectivityResult>)
//   - fetchNearestServices fallback now reads from OfflineService
//   - Connectivity-restored event triggers OfflineService.syncUnsyncedPings()

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/constants.dart';
import '../../data/models/service_model.dart';
import '../../data/remote/api_client.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../services/offline_service.dart';
import '../../services/osm_service.dart';
import '../loading/loading_provider.dart';

part 'home_provider.g.dart';

// ── Enums ──────────────────────────────────────────────────────────────────────

/// Which half of the home screen toggle is selected.
enum HomeMode { emergency, nonEmergency }

/// Possible emergency types surfaced on the home screen grid.
enum EmergencyType {
  accidentInjury,
  fireOnRoad,
  medicalEmergency,
  unsafeThreat,
}

// ── State ──────────────────────────────────────────────────────────────────────

/// Complete snapshot of everything the home screen needs to render.
class HomeState {
  const HomeState({
    required this.mode,
    required this.currentPosition,
    required this.countryCode,
    required this.emergencyNumbers,
    required this.nearestServices,
    required this.isLoadingServices,
    required this.isOnline,
    required this.batteryLevel,
    required this.showBatteryWarning,
    required this.locationLabel,
  });

  final HomeMode mode;
  final Position? currentPosition;
  final String countryCode;

  /// Emergency numbers for the detected country.
  final Map<String, String> emergencyNumbers;

  /// Up to 3 nearest services shown on the home screen preview.
  final List<ServiceModel> nearestServices;

  /// True while [HomeNotifier.fetchNearestServices] is running.
  final bool isLoadingServices;
  final bool isOnline;

  /// Battery fraction 0.0–1.0, or null if unavailable.
  final double? batteryLevel;

  /// True when batteryLevel < [AppConfig.lowBatteryThreshold].
  final bool showBatteryWarning;

  /// Human-readable location label, e.g. "Mumbai, MH" or "Detecting…".
  final String locationLabel;

  factory HomeState.initial() => const HomeState(
        mode: HomeMode.emergency,
        currentPosition: null,
        countryCode: 'IN',
        emergencyNumbers: {
          'police': '100',
          'ambulance': '108',
          'fire': '101',
          'unified': '112',
        },
        nearestServices: [],
        isLoadingServices: false,
        isOnline: true,
        batteryLevel: null,
        showBatteryWarning: false,
        locationLabel: 'Detecting…',
      );

  HomeState copyWith({
    HomeMode? mode,
    Position? currentPosition,
    bool clearPosition = false,
    String? countryCode,
    Map<String, String>? emergencyNumbers,
    List<ServiceModel>? nearestServices,
    bool? isLoadingServices,
    bool? isOnline,
    double? batteryLevel,
    bool? showBatteryWarning,
    String? locationLabel,
  }) =>
      HomeState(
        mode: mode ?? this.mode,
        currentPosition: clearPosition
            ? null
            : (currentPosition ?? this.currentPosition),
        countryCode: countryCode ?? this.countryCode,
        emergencyNumbers: emergencyNumbers ?? this.emergencyNumbers,
        nearestServices: nearestServices ?? this.nearestServices,
        isLoadingServices: isLoadingServices ?? this.isLoadingServices,
        isOnline: isOnline ?? this.isOnline,
        batteryLevel: batteryLevel ?? this.batteryLevel,
        showBatteryWarning: showBatteryWarning ?? this.showBatteryWarning,
        locationLabel: locationLabel ?? this.locationLabel,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

/// Manages home screen state.
///
/// Initialization is kicked off immediately after build returns; the screen
/// renders [HomeState.initial] while data loads, then updates progressively.
@riverpod
class HomeNotifier extends _$HomeNotifier {
  StreamSubscription<bool>? _connectivitySub;

  @override
  Future<HomeState> build() async {
    state = AsyncData(HomeState.initial());

    // Subscribe to live connectivity changes for the lifetime of this notifier.
    // Uses keepAlive ConnectivityService so the subscription persists across
    // screen navigations.
    final connSvc = ref.read(connectivityServiceProvider);
    _connectivitySub = connSvc.onConnectivityChanged.listen(_onConnectivityChange);
    ref.onDispose(() => _connectivitySub?.cancel());

    unawaited(_initialize());
    return HomeState.initial();
  }

  // ── Public actions ─────────────────────────────────────────────────────────

  /// Switches between emergency and non-emergency mode.
  ///
  /// Only a UI toggle — no service refetch; the grid content changes instantly.
  void toggleMode(HomeMode mode) {
    final cur = state.valueOrNull ?? HomeState.initial();
    state = AsyncData(cur.copyWith(mode: mode));
  }

  /// Fetches nearest services from the backend, falling back to local cache.
  ///
  /// Skipped when no real backend is configured (emulator-only default URL).
  Future<void> fetchNearestServices() async {
    final cur = state.valueOrNull ?? HomeState.initial();
    final pos = cur.currentPosition;
    if (pos == null) return;

    // Skip when the backend URL is the compile-time default — it only resolves
    // inside an Android emulator and always times out on physical devices.
    const defaultUrl = 'http://10.0.2.2:8000';
    const apiUrl = AppConstants.apiBaseUrl;
    if (apiUrl.isEmpty || apiUrl == defaultUrl) {
      debugPrint('[HomeNotifier] fetchNearestServices skipped (emulator URL)');
      // Still try to serve from cache for offline preview.
      await _loadServicesFromCache(cur, pos);
      return;
    }

    state = AsyncData(cur.copyWith(isLoadingServices: true));

    try {
      final services = await ref.read(apiClientProvider).getNearbyServices(
            lat: pos.latitude,
            lng: pos.longitude,
            countryCode: cur.countryCode,
            minTrustScore: AppConfig.minTrustScoreEmergency,
          );

      if (services.isNotEmpty) {
        final trimmed = services.take(3).toList();
        state = AsyncData(
          (state.valueOrNull ?? HomeState.initial()).copyWith(
            nearestServices: trimmed,
            isLoadingServices: false,
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('[HomeNotifier] fetchNearestServices live error: $e');
    }

    // Live fetch empty or failed — fall back to OSM.
    try {
      final osm = OsmService();
      final services = await osm.fetchNearbyServices(
        lat: pos.latitude,
        lng: pos.longitude,
        categories: ['hospital', 'police', 'fire', 'ambulance'],
        countryCode: cur.countryCode,
      );

      if (services.isNotEmpty) {
        final trimmed = services.take(3).toList();
        state = AsyncData(
          (state.valueOrNull ?? HomeState.initial()).copyWith(
            nearestServices: trimmed,
            isLoadingServices: false,
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('[HomeNotifier] fetchNearestServices OSM error: $e');
    }

    // OSM empty or failed — fall back to cache.
    await _loadServicesFromCache(
      state.valueOrNull ?? cur,
      pos,
    );
  }

  /// Refreshes GPS position and re-fetches services.
  Future<void> refreshLocation() async {
    final svc = ref.read(locationServiceProvider);
    final pos = await svc.getCurrentLocation();
    if (pos == null) return;

    final code = await svc.getCountryCode(pos);
    final label = await _buildLocationLabel(pos, code);

    state = AsyncData(
      (state.valueOrNull ?? HomeState.initial()).copyWith(
        currentPosition: pos,
        countryCode: code,
        locationLabel: label,
      ),
    );

    await fetchNearestServices();
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> _initialize() async {
    final svc = ref.read(locationServiceProvider);

    // 1. Get position
    final pos = await svc.getCurrentLocation();

    // 2. Detect country
    final code = pos != null ? await svc.getCountryCode(pos) : 'IN';

    // 3. Build location label
    final label = pos != null
        ? await _buildLocationLabel(pos, code)
        : 'Detecting…';

    // 4. Resolve emergency numbers from the loading screen cache first.
    final loadedNumbers = ref.read(emergencyNumbersProvider);
    final numbers = loadedNumbers.isNotEmpty
        ? loadedNumbers
        : EmergencyNumbers.india;

    // 5. Battery check
    final battery = await svc.getBatteryLevel();
    final lowBattery = svc.isLowBattery(battery);

    // 6. Connectivity — read from ConnectivityService (v6 safe).
    final isOnline = ref.read(connectivityServiceProvider).isOnline;

    // Commit everything at once.
    state = AsyncData(
      HomeState(
        mode: HomeMode.emergency,
        currentPosition: pos,
        countryCode: code,
        emergencyNumbers: numbers,
        nearestServices: const [],
        isLoadingServices: pos != null,
        isOnline: isOnline,
        batteryLevel: battery,
        showBatteryWarning: lowBattery,
        locationLabel: label,
      ),
    );

    // 7. Fetch services if we have a position.
    if (pos != null) {
      await fetchNearestServices();
    }
  }

  // ── Connectivity listener ──────────────────────────────────────────────────

  /// Called by ConnectivityService whenever the device goes online/offline.
  void _onConnectivityChange(bool online) {
    final cur = state.valueOrNull;
    if (cur == null) return;

    state = AsyncData(cur.copyWith(isOnline: online));
    debugPrint('[HomeNotifier] Connectivity changed → ${online ? 'online' : 'offline'}');

    if (online) {
      // Back online — upload any pings that were queued while offline.
      ref.read(offlineServiceProvider).syncUnsyncedPings();
    }
  }

  // ── Cache fallback ─────────────────────────────────────────────────────────

  Future<void> _loadServicesFromCache(HomeState cur, Position pos) async {
    try {
      final cached = await ref.read(offlineServiceProvider).readCachedServices(
            lat: pos.latitude,
            lng: pos.longitude,
            radiusKm: AppConfig.defaultUrbanRadiusKm.toDouble(),
            minTrustScore: AppConfig.minTrustScoreEmergency,
          );
      final trimmed = cached.take(3).toList();
      state = AsyncData(
        (state.valueOrNull ?? cur).copyWith(
          nearestServices: trimmed,
          isLoadingServices: false,
        ),
      );
      if (cached.isNotEmpty) {
        debugPrint(
            '[HomeNotifier] Loaded ${trimmed.length} services from cache');
      }
    } catch (e) {
      debugPrint('[HomeNotifier] Cache read error: $e');
      state = AsyncData(
        (state.valueOrNull ?? cur).copyWith(
          nearestServices: const [],
          isLoadingServices: false,
        ),
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Converts a [Position] to "City, State" using the geocoding package.
  ///
  /// Falls back gracefully to the country code on any error.
  Future<String> _buildLocationLabel(Position pos, String country) async {
    try {
      final placemarks = await _reversegeocode(pos.latitude, pos.longitude);
      if (placemarks == null) return country;
      final city = placemarks['locality'] ?? '';
      final adminArea = placemarks['administrativeArea'] ?? '';
      if (city.isNotEmpty && adminArea.isNotEmpty) return '$city, $adminArea';
      if (city.isNotEmpty) return city;
    } catch (_) {}
    return country;
  }

  /// Thin wrapper so unit tests can mock reverse geocoding.
  Future<Map<String, String?>?> _reversegeocode(
    double lat,
    double lng,
  ) async {
    try {
      return await _tryGeocode(lat, lng);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String?>?> _tryGeocode(double lat, double lng) async {
    // Calls geocoding.placemarkFromCoordinates via dynamic dispatch.
    // Returns null until geocoding is fully wired in a later module.
    return null;
    // TODO: uncomment when geocoding is fully wired:
    // final marks = await placemarkFromCoordinates(lat, lng);
    // if (marks.isEmpty) return null;
    // return {
    //   'locality': marks.first.locality,
    //   'administrativeArea': marks.first.administrativeArea,
    // };
  }
}

// ── Connectivity provider ─────────────────────────────────────────────────────

/// True when the device has any active network connection.
///
/// Module 5: now delegates to ConnectivityService (keepAlive) for consistency.
/// Uses the service's synchronous getter so there's no Future overhead.
@riverpod
bool isOnline(IsOnlineRef ref) {
  return ref.watch(connectivityServiceProvider).isOnline;
}
