// lib/services/places_service.dart
//
// Unified places fetch — routes by category:
//   Emergency (hospital, police, fire, ambulance) → Geoapify
//   Vehicle non-emergency (towing, breakdown, puncture) → Google Places
//
// OSM Overpass removed: all public mirrors block emulator/datacenter IPs
// (HTTP 403, 406, DNS failures) making it unreliable as a fallback.
// If both APIs fail for a category, an empty list is returned — the results
// screen falls through to the SQLite cache, then shows "unavailable".
//
// Keys injected at build time via --dart-define=GEOAPIFY_API_KEY=... etc.,
// OR via defaultValue fallbacks in AppConstants (from gitignored api_keys.dart).

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models/service_model.dart';
import 'google_places_service.dart';

const _radiusM = 10000; // 10 km
const _maxResults = 20;
const _timeout = Duration(seconds: 20);

class PlacesService {
  const PlacesService({
    required this.geoapifyKey,
    required this.googlePlacesKey,
  });

  final String geoapifyKey;
  final String googlePlacesKey;

  bool get _hasGeoapifyKey => geoapifyKey.isNotEmpty;

  // ── Category routing ───────────────────────────────────────────────────────

  static const _vehicleCategories = {'towing', 'breakdown', 'puncture', 'fuel'};
  static const _emergencyCategories = {'hospital', 'ambulance', 'police', 'fire'};

  // ── Public entry point ─────────────────────────────────────────────────────

  /// Fetches services for [categories], routing each to the right data source:
  ///   • Emergency  → Geoapify (global, quality POIs)
  ///   • Vehicle    → Google Places Text Search (keyword queries per category)
  Future<List<ServiceModel>> fetchNearbyServices({
    required double lat,
    required double lng,
    required List<String> categories,
    required String countryCode,
  }) async {
    debugPrint('[PlacesService] geoapify=${_hasGeoapifyKey ? "✓" : "✗"} '
        'gplaces=${googlePlacesKey.isNotEmpty ? "✓" : "✗"} '
        'categories=$categories');

    final emergency = categories.where(_emergencyCategories.contains).toList();
    final vehicle   = categories.where(_vehicleCategories.contains).toList();
    final results   = <ServiceModel>[];

    // Emergency categories — Geoapify
    if (emergency.isNotEmpty) {
      results.addAll(await _fetchEmergency(lat, lng, emergency, countryCode));
    }

    // Vehicle non-emergency — Google Places
    if (vehicle.isNotEmpty) {
      results.addAll(await _fetchVehicle(lat, lng, vehicle, countryCode));
    }

    results.sort((a, b) => (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999));
    return results;
  }

  /// Emergency fetch: Geoapify only.
  Future<List<ServiceModel>> _fetchEmergency(
    double lat, double lng,
    List<String> cats,
    String countryCode,
  ) async {
    if (!_hasGeoapifyKey) {
      debugPrint('[PlacesService] No Geoapify key — skipping emergency fetch for $cats');
      return const [];
    }
    try {
      final results = await _fetchFromGeoapify(lat, lng, cats, countryCode);
      debugPrint('[PlacesService] Geoapify → ${results.length} emergency services');
      return results;
    } catch (e) {
      debugPrint('[PlacesService] Geoapify failed: $e');
      return const [];
    }
  }

  /// Vehicle fetch: Google Places only.
  Future<List<ServiceModel>> _fetchVehicle(
    double lat, double lng,
    List<String> cats,
    String countryCode,
  ) async {
    try {
      final gResults = await GooglePlacesService(apiKey: googlePlacesKey)
          .fetchNearbyServices(
        lat: lat,
        lng: lng,
        categories: cats,
        countryCode: countryCode,
      );
      debugPrint('[PlacesService] Google Places → ${gResults.length} vehicle services');
      return gResults;
    } catch (e) {
      debugPrint('[PlacesService] Google Places failed: $e');
      return const [];
    }
  }

  // ── Geoapify Places API v2 ─────────────────────────────────────────────────
  // Docs: https://apidocs.geoapify.com/docs/places/
  //
  // filter=circle:lon,lat,radius_metres  (lon before lat — Geoapify convention)
  // bias=proximity:lon,lat               (sorts results closest-first)

  Future<List<ServiceModel>> _fetchFromGeoapify(
    double lat,
    double lng,
    List<String> categories,
    String countryCode,
  ) async {
    final geoapifyCategories = _toGeoapifyCategories(categories);
    if (geoapifyCategories.isEmpty) return const [];

    final uri = Uri.https('api.geoapify.com', '/v2/places', {
      'categories': geoapifyCategories.join(','),
      'filter': 'circle:$lng,$lat,$_radiusM',
      'bias': 'proximity:$lng,$lat',
      'limit': '$_maxResults',
      'apiKey': geoapifyKey,
    });

    debugPrint('[PlacesService] Geoapify → $categories at ($lat,$lng)');

    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(_timeout);

    if (response.statusCode != 200) {
      debugPrint('[PlacesService] Geoapify error body: ${response.body}');
      throw Exception('HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (body['features'] as List<dynamic>?) ?? [];
    debugPrint('[PlacesService] Geoapify raw features: ${features.length}');

    final services = features
        .map((f) => _parseFeature(f as Map<String, dynamic>, lat, lng, countryCode))
        .whereType<ServiceModel>()
        .toList();

    debugPrint('[PlacesService] Geoapify parsed services: ${services.length}');
    return services;
  }

  // ── Response parser ────────────────────────────────────────────────────────

  ServiceModel? _parseFeature(
    Map<String, dynamic> feature,
    double userLat,
    double userLng,
    String countryCode,
  ) {
    final props = feature['properties'] as Map<String, dynamic>?;
    if (props == null) return null;

    final name = (props['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;

    // Geoapify geometry coordinates are [lon, lat]
    final geom = feature['geometry'] as Map<String, dynamic>?;
    final coords = geom?['coordinates'] as List<dynamic>?;
    if (coords == null || coords.length < 2) return null;
    final lng = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();

    final rawCats = (props['categories'] as List<dynamic>?)
            ?.map((c) => c.toString())
            .toList() ??
        [];
    final category = _geoapifyCategoryToOurs(rawCats);
    if (category == null) return null;

    // Phone — check multiple possible locations in the response
    final raw = (props['datasource'] as Map<String, dynamic>?)?['raw']
        as Map<String, dynamic>?;
    final phone = _firstNonEmpty([
      raw?['phone']?.toString(),
      raw?['contact:phone']?.toString(),
      raw?['contact:mobile']?.toString(),
    ]);

    // Address — use formatted string if available, else build from parts
    final address = (props['formatted'] as String?)?.trim() ??
        [
          props['housenumber'],
          props['street'],
          props['suburb'],
          props['city'],
          props['state'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    // Geoapify returns distance in metres when bias is set
    final distanceM = (props['distance'] as num?)?.toDouble();

    return ServiceModel(
      id: 'geoapify_${props['place_id'] ?? '${lat}_$lng'}',
      name: name,
      category: category,
      subcategory: rawCats.firstOrNull,
      lat: lat,
      lng: lng,
      phonePrimary: phone,
      address: address.isNotEmpty ? address : null,
      countryCode: countryCode,
      is24hr: raw?['opening_hours'] == '24/7',
      // Trust 4: Geoapify aggregates govt datasets + OSM + commercial sources
      trustScore: 4,
      source: 'geoapify',
      distanceKm: distanceM != null
          ? distanceM / 1000
          : _haversineKm(userLat, userLng, lat, lng),
    );
  }

  // ── Category mapping ───────────────────────────────────────────────────────

  List<String> _toGeoapifyCategories(List<String> cats) {
    // Verified valid Geoapify v2 category names — confirmed from API error body.
    // NOTE: healthcare.clinic is INVALID — use healthcare.hospital only.
    // NOTE: commercial.vehicle.car_repair is INVALID — Geoapify has no vehicle
    //       repair category. towing/breakdown/puncture use Google Places only.
    // helpline has no POI category — handled as static numbers by the caller.
    const map = <String, List<String>>{
      'hospital':  ['healthcare.hospital'],
      'ambulance': ['healthcare.hospital'],
      'police':    ['service.police'],
      'fire':      ['service.fire_station'],
      // towing / breakdown / puncture intentionally omitted → Google Places only
    };
    return cats.expand((c) => map[c] ?? <String>[]).toSet().toList();
  }

  String? _geoapifyCategoryToOurs(List<String> cats) {
    for (final c in cats) {
      if (c.startsWith('healthcare')) return 'hospital';
      if (c.startsWith('service.police')) return 'police';
      if (c.startsWith('service.fire')) return 'fire';
    }
    return null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final s = v?.trim().replaceAll(RegExp(r'[\s\-()+]+'), '');
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
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
