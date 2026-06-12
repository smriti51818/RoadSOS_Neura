// lib/services/osm_service.dart
//
// Fetches real nearby emergency services from OpenStreetMap via Overpass API.
//
// Uses the `http` package (not Dio) to send a clean form-encoded POST — Dio
// adds Accept: application/json headers that cause some Overpass mirrors to
// return 406. The http package sends exactly the headers we specify, nothing
// more.
//
// Mirrors tried in order:
//   1. overpass-api.de        (global primary)
//   2. overpass.openstreetmap.ru  (Russian mirror, independent infra)
//   3. overpass.kumi.systems  (EU mirror — last resort, may rate-limit)

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models/service_model.dart';

class OsmService {
  static const _endpoints = [
    'https://overpass.openstreetmap.fr/api/interpreter',  // French mirror — most stable
    'https://overpass-api.de/api/interpreter',            // Primary but sometimes 406
    'https://overpass.openstreetmap.ru/api/interpreter',  // RU mirror, independent infra
    'https://overpass.kumi.systems/api/interpreter',      // EU mirror — last resort
  ];

  /// Search radius in metres. 10 km covers any urban area.
  static const _radiusM = 10000;

  static const _timeout = Duration(seconds: 20); // per-mirror timeout

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetches nearby services for [categories] around ([lat], [lng]).
  ///
  /// Throws on failure — caller decides how to handle it.
  // Vehicle service categories share OSM shop=car_repair/tyres tags.
  // When fetching for exactly one vehicle category, results are relabeled so
  // they appear under the correct section (towing vs breakdown vs puncture).
  static const _vehicleCategories = {'towing', 'breakdown', 'puncture'};

  Future<List<ServiceModel>> fetchNearbyServices({
    required double lat,
    required double lng,
    required List<String> categories,
    required String countryCode,
  }) async {
    final tags = _categoriesToTags(categories);
    if (tags.isEmpty) return const [];

    final query = _buildQuery(lat, lng, tags);
    debugPrint('[OsmService] Querying for $tags at ($lat,$lng)');

    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final elements = await _postQuery(endpoint, query);
        var services = _parseElements(elements, lat, lng, countryCode);
        services.sort(
            (a, b) => (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999));
        debugPrint('[OsmService] ${services.length} services from $endpoint');

        // Relabel vehicle results to match the specifically requested category
        if (categories.length == 1 && _vehicleCategories.contains(categories.first)) {
          final forced = categories.first;
          services = services.map((s) => s.copyWith(category: forced)).toList();
        }
        return services;
      } catch (e) {
        debugPrint('[OsmService] $endpoint failed: $e');
        lastError = e;
      }
    }
    throw lastError ?? Exception('All Overpass mirrors failed');
  }

  // ── HTTP (plain http package — no extra headers) ───────────────────────────

  Future<List<dynamic>> _postQuery(String endpoint, String query) async {
    final response = await http
        .post(
          Uri.parse(endpoint),
          // Only send what Overpass needs. No Accept header — the response
          // format is declared inside the query itself via [out:json].
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          // http package encodes the Map correctly:  data=<url-encoded query>
          body: {'data': query},
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['elements'] as List<dynamic>?) ?? [];
  }

  // ── Query builder ──────────────────────────────────────────────────────────

  // Tags use a "key:value" format where key is "amenity" or "shop".
  // e.g. "amenity:hospital", "shop:car_repair", "shop:tyres"
  String _buildQuery(double lat, double lng, List<String> tags) {
    final parts = tags.expand((tag) {
      final colon = tag.indexOf(':');
      final key = colon >= 0 ? tag.substring(0, colon) : 'amenity';
      final value = colon >= 0 ? tag.substring(colon + 1) : tag;
      return [
        'node[$key=$value](around:$_radiusM,$lat,$lng);',
        'way[$key=$value](around:$_radiusM,$lat,$lng);',
      ];
    }).join('');
    // [out:json]  → response format declared in query, not HTTP Accept header
    // out center  → gives lat/lng centre for way elements too
    // body qt     → include tags, sort by distance (fastest output mode)
    return '[out:json][timeout:20];($parts);out center body qt;';
  }

  List<String> _categoriesToTags(List<String> categories) {
    final result = <String>{};
    for (final cat in categories) {
      switch (cat) {
        case 'hospital':
          result.addAll(['amenity:hospital', 'amenity:clinic']);
        case 'ambulance':
          result.addAll(['amenity:hospital', 'amenity:ambulance_station']);
        case 'police':
          result.add('amenity:police');
        case 'fire':
          result.add('amenity:fire_station');
        case 'towing':
        case 'breakdown':
          result.add('shop:car_repair');
        case 'puncture':
          result.addAll(['shop:tyres', 'shop:car_repair']);
        // helpline has no OSM POI — handled as static numbers by the caller
      }
    }
    return result.toList();
  }

  // ── Response parser ────────────────────────────────────────────────────────

  List<ServiceModel> _parseElements(
    List<dynamic> elements,
    double userLat,
    double userLng,
    String countryCode,
  ) {
    final services = <ServiceModel>[];

    for (final raw in elements) {
      final e = raw as Map<String, dynamic>;
      final tags = (e['tags'] as Map<String, dynamic>?) ?? {};

      // Skip unnamed POIs — a hospital with no name is useless in an emergency
      final name = (tags['name'] as String?)?.trim() ??
          (tags['name:en'] as String?)?.trim() ??
          '';
      if (name.isEmpty) continue;

      // Coordinates: nodes have lat/lon directly; ways have a centre object
      final double? lat;
      final double? lng;
      if (e['type'] == 'node') {
        lat = (e['lat'] as num?)?.toDouble();
        lng = (e['lon'] as num?)?.toDouble();
      } else {
        final centre = e['center'] as Map<String, dynamic>?;
        lat = (centre?['lat'] as num?)?.toDouble();
        lng = (centre?['lon'] as num?)?.toDouble();
      }
      if (lat == null || lng == null) continue;

      final amenity = (tags['amenity'] as String?) ?? '';
      final shop = (tags['shop'] as String?) ?? '';
      final category = _tagToCategory(amenity, shop);
      if (category == null) continue;

      services.add(ServiceModel(
        id: 'osm_${e['id']}',
        name: name,
        category: category,
        subcategory: amenity,
        lat: lat,
        lng: lng,
        phonePrimary: _extractPhone(tags),
        phoneSecondary: null,
        address: _extractAddress(tags),
        countryCode: countryCode,
        is24hr: tags['opening_hours'] == '24/7',
        // Trust 3 = community-verified. OSM is crowd-sourced, not govt-verified.
        trustScore: 3,
        source: 'osm',
        distanceKm: _haversine(userLat, userLng, lat, lng),
      ));
    }

    return services;
  }

  // ── Tag helpers ────────────────────────────────────────────────────────────

  String? _extractPhone(Map<String, dynamic> tags) {
    final raw = (tags['phone'] as String?) ??
        (tags['contact:phone'] as String?) ??
        (tags['contact:mobile'] as String?) ??
        (tags['telephone'] as String?);
    if (raw == null || raw.trim().isEmpty) return null;
    // Strip spaces, dashes, parens — keep + and digits
    final normalised = raw.trim().replaceAll(RegExp(r'[\s\-()+]+'), '');
    return normalised.isEmpty ? null : normalised;
  }

  String? _extractAddress(Map<String, dynamic> tags) {
    final parts = [
      tags['addr:housenumber'],
      tags['addr:street'],
      tags['addr:suburb'],
      tags['addr:city'],
      tags['addr:state'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();

    if (parts.isNotEmpty) return parts.join(', ');
    final full = (tags['addr:full'] as String?)?.trim();
    return (full != null && full.isNotEmpty) ? full : null;
  }

  String? _tagToCategory(String amenity, String shop) {
    switch (amenity) {
      case 'hospital':
      case 'clinic':
      case 'doctors':
        return 'hospital';
      case 'ambulance_station':
        return 'ambulance';
      case 'police':
        return 'police';
      case 'fire_station':
        return 'fire';
    }
    switch (shop) {
      case 'car_repair':
      case 'car_service':
        return 'breakdown';
      case 'tyres':
        return 'puncture';
    }
    return null;
  }

  // ── Haversine ──────────────────────────────────────────────────────────────

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
