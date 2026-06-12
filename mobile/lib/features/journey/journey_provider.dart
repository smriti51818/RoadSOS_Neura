// lib/features/journey/journey_provider.dart
// Module 6 — Journey mode state and blackspot detection.
//
// Architecture:
//   • JourneyNotifier manages active journey state (not app-lifetime)
//   • Blackspot detection runs on each location update
//   • ETA SMS sent via SMSService on journey start when shareEtaWith is given
//   • Waypoints are pre-cached from the destination name (simulated offsets)
//   • KNOWN_BLACKSPOTS — 5 real NH accident hotspots hardcoded as seed data

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/location_service.dart';
import '../../services/sms_service.dart';
import '../../core/constants.dart';

part 'journey_provider.g.dart';

// ── Models ─────────────────────────────────────────────────────────────────────

/// A waypoint along the active journey route.
class CachedWaypoint {
  const CachedWaypoint({
    required this.lat,
    required this.lng,
    required this.label,
    this.isReached = false,
  });

  final double lat;
  final double lng;
  final String label;
  final bool isReached;

  CachedWaypoint copyWith({bool? isReached}) {
    return CachedWaypoint(
      lat: lat,
      lng: lng,
      label: label,
      isReached: isReached ?? this.isReached,
    );
  }
}

/// An accident blackspot near the current or planned route.
class BlackspotWarning {
  const BlackspotWarning({
    required this.name,
    required this.highway,
    required this.lat,
    required this.lng,
    required this.reason,
    required this.distanceKm,
  });

  final String name;
  final String highway;
  final double lat;
  final double lng;
  final String reason;
  final double distanceKm;
}

/// Full journey session state.
class JourneyState {
  const JourneyState({
    this.isActive = false,
    this.destination = '',
    this.shareEtaWith,
    this.waypoints = const [],
    this.blackspots = const [],
    this.currentLat,
    this.currentLng,
    this.startedAt,
    this.etaMinutes,
    this.distanceCoveredKm = 0.0,
    this.totalDistanceKm,
    this.routeGeometry,
    this.statusMessage = '',
  });

  final bool isActive;
  final String destination;
  final String? shareEtaWith;
  final List<CachedWaypoint> waypoints;
  final List<BlackspotWarning> blackspots;
  final double? currentLat;
  final double? currentLng;
  final DateTime? startedAt;
  final int? etaMinutes;
  final double distanceCoveredKm;
  final double? totalDistanceKm;
  final List<LatLng>? routeGeometry;
  final String statusMessage;

  bool get hasBlackspots => blackspots.isNotEmpty;

  int get reachedWaypoints => waypoints.where((w) => w.isReached).length;

  JourneyState copyWith({
    bool? isActive,
    String? destination,
    String? shareEtaWith,
    List<CachedWaypoint>? waypoints,
    List<BlackspotWarning>? blackspots,
    double? currentLat,
    double? currentLng,
    DateTime? startedAt,
    int? etaMinutes,
    double? distanceCoveredKm,
    double? totalDistanceKm,
    List<LatLng>? routeGeometry,
    String? statusMessage,
  }) {
    return JourneyState(
      isActive: isActive ?? this.isActive,
      destination: destination ?? this.destination,
      shareEtaWith: shareEtaWith ?? this.shareEtaWith,
      waypoints: waypoints ?? this.waypoints,
      blackspots: blackspots ?? this.blackspots,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      startedAt: startedAt ?? this.startedAt,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      distanceCoveredKm: distanceCoveredKm ?? this.distanceCoveredKm,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      routeGeometry: routeGeometry ?? this.routeGeometry,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

// ── Notifier ───────────────────────────────────────────────────────────────────

@riverpod
class JourneyNotifier extends _$JourneyNotifier {
  // ── Live Blackspots Cache ───────────────────────────────────────────────────
  List<BlackspotWarning> _liveBlackspots = [];

  static const double _blackspotRadiusKm = 50.0;

  StreamSubscription<Position>? _locationSub;

  @override
  JourneyState build() => const JourneyState();

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Starts a journey to [destination], optionally sharing ETA with [shareEtaWith].
  Future<void> startJourney({
    required String destination,
    String? shareEtaWith,
  }) async {
    if (destination.trim().isEmpty) return;

    state = state.copyWith(statusMessage: 'Getting your location...');

    final location = ref.read(locationServiceProvider);
    final position = await location.getCurrentLocation();

    if (position == null) {
      state = state.copyWith(
        statusMessage: 'Could not get location. Check GPS permissions.',
      );
      return;
    }

    // Fetch real route from Mapbox
    List<LatLng>? routeGeometry;
    List<CachedWaypoint> waypoints = [];
    int? etaMinutes;
    double? totalDistanceKm;

    try {
      // 1. Geocode Destination
      final geoUrl = Uri.parse(
          'https://api.geoapify.com/v1/geocode/search?text=${Uri.encodeComponent(destination)}&limit=1&apiKey=${AppConstants.geoapifyApiKey}');
      final geoRes = await http.get(geoUrl);
      if (geoRes.statusCode == 200) {
        final geoData = jsonDecode(geoRes.body);
        if (geoData['features'] != null && geoData['features'].isNotEmpty) {
          final destLat = geoData['features'][0]['properties']['lat'] as double;
          final destLng = geoData['features'][0]['properties']['lon'] as double;

          // 2. OSRM Directions API
          final dirUrl = Uri.parse(
              'http://router.project-osrm.org/route/v1/driving/${position.longitude},${position.latitude};$destLng,$destLat?overview=full&geometries=polyline');
          final dirRes = await http.get(dirUrl);
          if (dirRes.statusCode == 200) {
            final dirData = jsonDecode(dirRes.body);
            if (dirData['routes'] != null && dirData['routes'].isNotEmpty) {
              final route = dirData['routes'][0];
              etaMinutes = (route['duration'] as num).toDouble() ~/ 60;
              totalDistanceKm = (route['distance'] as num).toDouble() / 1000.0;

              final geometry = route['geometry'] as String;
              final points = PolylinePoints.decodePolyline(geometry);
              routeGeometry = points.map((p) => LatLng(p.latitude, p.longitude)).toList();
              
              waypoints = [
                CachedWaypoint(lat: position.latitude, lng: position.longitude, label: 'Start'),
                CachedWaypoint(lat: destLat, lng: destLng, label: destination),
              ];
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[JourneyNotifier] Geoapify error: $e');
    }

    // Fallback if Geoapify fails or isn't configured
    if (routeGeometry == null) {
      waypoints = _buildWaypoints(destination, position.latitude, position.longitude);
    }

    // Fetch live safety data from Overpass API (unlit roads, construction, hazards)
    await _fetchLiveHazards(position.latitude, position.longitude);

    // Detect nearby blackspots from the newly fetched live data
    final blackspots = _detectBlackspots(position.latitude, position.longitude);

    state = JourneyState(
      isActive: true,
      destination: destination,
      shareEtaWith: shareEtaWith,
      waypoints: waypoints,
      blackspots: blackspots,
      currentLat: position.latitude,
      currentLng: position.longitude,
      startedAt: DateTime.now(),
      etaMinutes: etaMinutes,
      totalDistanceKm: totalDistanceKm,
      routeGeometry: routeGeometry,
      statusMessage: blackspots.isNotEmpty
          ? '⚠️ ${blackspots.length} accident blackspot(s) ahead'
          : 'Journey active — stay safe',
    );

    // Share location via SMS if contact provided (no ETA — unknown without routing)
    if (shareEtaWith != null && shareEtaWith.isNotEmpty) {
      await _sendEtaSms(
        contactNumber: shareEtaWith,
        destination: destination,
        lat: position.latitude,
        lng: position.longitude,
        etaMinutes: null,
      );
    }

    // Start listening for location updates
    _startLocationTracking(position.latitude, position.longitude);
  }

  /// Fetches location suggestions for the autocomplete search bar.
  Future<List<String>> fetchLocationSuggestions(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final url = Uri.parse(
          'https://api.geoapify.com/v1/geocode/autocomplete?text=${Uri.encodeComponent(query)}&limit=5&apiKey=${AppConstants.geoapifyApiKey}');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['features'] != null) {
          final features = data['features'] as List;
          return features
              .map((f) => f['properties']['formatted'] as String?)
              .where((s) => s != null)
              .cast<String>()
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[JourneyNotifier] Autocomplete error: $e');
    }
    return [];
  }

  /// Stops the active journey and cancels location tracking.
  Future<void> stopJourney() async {
    await _locationSub?.cancel();
    _locationSub = null;
    state = const JourneyState(statusMessage: 'Journey ended');
  }

  /// Checks for new blackspots at [lat]/[lng] (called on location update).
  void updateLocation(double lat, double lng) {
    if (!state.isActive) return;

    final blackspots = _detectBlackspots(lat, lng);

    // Mark waypoints as reached (within 0.5 km)
    final updatedWaypoints = state.waypoints.map((w) {
      if (w.isReached) return w;
      final d = _haversine(lat, lng, w.lat, w.lng);
      return d <= 0.5 ? w.copyWith(isReached: true) : w;
    }).toList();

    state = state.copyWith(
      currentLat: lat,
      currentLng: lng,
      blackspots: blackspots,
      waypoints: updatedWaypoints,
      statusMessage: blackspots.isNotEmpty
          ? '⚠️ ${blackspots.length} blackspot(s) ahead — drive carefully'
          : 'Journey active — stay safe',
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _startLocationTracking(double startLat, double startLng) {
    _locationSub?.cancel();
    try {
      _locationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 200, // update every 200m
        ),
      ).listen(
        (pos) => updateLocation(pos.latitude, pos.longitude),
        onError: (e) => debugPrint('[JourneyNotifier] Location error: $e'),
      );
    } catch (e) {
      debugPrint('[JourneyNotifier] Could not start location stream: $e');
    }
  }

  /// Builds 3 simulated waypoints offset from current position.
  List<CachedWaypoint> _buildWaypoints(
    String destination,
    double lat,
    double lng,
  ) {
    return [
      CachedWaypoint(
        lat: lat + 0.18,
        lng: lng + 0.12,
        label: 'Via Main Highway',
      ),
      CachedWaypoint(
        lat: lat + 0.36,
        lng: lng + 0.24,
        label: 'Midpoint checkpoint',
      ),
      CachedWaypoint(
        lat: lat + 0.54,
        lng: lng + 0.36,
        label: destination,
      ),
    ];
  }

  /// Fetches live hazards from Overpass API within a 15km bounding box
  Future<void> _fetchLiveHazards(double lat, double lng) async {
    try {
      final delta = 0.15; // roughly 15km
      final s = lat - delta;
      final n = lat + delta;
      final w = lng - delta;
      final e = lng + delta;

      // Query for unlit roads (night hazard) and construction
      final query = '''
      [out:json][timeout:10];
      (
        way["lit"="no"]["highway"~"primary|secondary|trunk"]($s,$w,$n,$e);
        way["highway"="construction"]($s,$w,$n,$e);
      );
      out center;
      ''';

      final url = Uri.parse('https://overpass-api.de/api/interpreter');
      final res = await http.post(url, body: query);
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final elements = data['elements'] as List;
        
        _liveBlackspots = elements.map((el) {
          final center = el['center'] ?? {};
          final tags = el['tags'] ?? {};
          final isUnlit = tags['lit'] == 'no';
          
          return BlackspotWarning(
            name: tags['name'] ?? (isUnlit ? 'Unlit Highway Segment' : 'Construction Zone'),
            highway: tags['ref'] ?? tags['highway'] ?? 'Unknown Road',
            lat: center['lat'] as double? ?? 0.0,
            lng: center['lon'] as double? ?? 0.0,
            reason: isUnlit 
                ? 'High risk during night hours due to zero street lighting.' 
                : 'Active construction zone. High risk of debris and uneven roads.',
            distanceKm: 0.0, // calculated later
          );
        }).where((b) => b.lat != 0.0 && b.lng != 0.0).toList();
        
        debugPrint('[JourneyNotifier] Fetched ${_liveBlackspots.length} live hazards via Overpass');
      }
    } catch (e) {
      debugPrint('[JourneyNotifier] Failed to fetch live hazards: $e');
    }
  }

  /// Checks which live blackspots are within [_blackspotRadiusKm] of [lat]/[lng].
  List<BlackspotWarning> _detectBlackspots(double lat, double lng) {
    final result = <BlackspotWarning>[];
    for (final bs in _liveBlackspots) {
      final d = _haversine(lat, lng, bs.lat, bs.lng);
      if (d <= _blackspotRadiusKm) {
        result.add(BlackspotWarning(
          name: bs.name,
          highway: bs.highway,
          lat: bs.lat,
          lng: bs.lng,
          reason: bs.reason,
          distanceKm: d,
        ));
      }
    }
    // Sort by distance (nearest first)
    result.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return result;
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

  Future<void> _sendEtaSms({
    required String contactNumber,
    required String destination,
    required double lat,
    required double lng,
    int? etaMinutes,
  }) async {
    try {
      final sms = ref.read(smsServiceProvider);
      // sendLocationUpdate opens native SMS app pre-filled with location.
      // userName field repurposed to carry journey context.
      final etaStr = etaMinutes != null ? '~$etaMinutes min' : 'ETA unknown';
      await sms.sendLocationUpdate(
        contactNumbers: [contactNumber],
        lat: lat,
        lng: lng,
        userName: 'RoadSoS Journey to $destination ($etaStr)',
      );
      debugPrint('[JourneyNotifier] ETA SMS sent to $contactNumber');
    } catch (e) {
      debugPrint('[JourneyNotifier] ETA SMS error (non-fatal): $e');
    }
  }
}
