// lib/services/google_places_service.dart
//
// Fetches nearby non-emergency vehicle services using Google Places API (New)
// Text Search endpoint — keyword queries return far more relevant results than
// the structured-type Nearby Search for towing/breakdown/puncture/fuel.
//
// Strategy per category:
//   • Run all keyword queries for that category concurrently
//   • Merge results and deduplicate by place ID
//   • Sort by distance (haversine from user location)
//
// API key injected via --dart-define=GOOGLE_PLACES_API_KEY=...
// Text Search docs: https://developers.google.com/maps/documentation/places/web-service/text-search

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models/service_model.dart';

const _textSearchEndpoint = 'https://places.googleapis.com/v1/places:searchText';
const _radiusM    = 10000.0; // 10 km search radius
const _maxResults = 10;      // per query term — cap billing surface
const _timeout    = Duration(seconds: 15);

/// Fields requested — charged per field, keep this minimal.
const _fieldMask =
    'places.id,places.displayName,places.formattedAddress,places.location,'
    'places.internationalPhoneNumber,places.nationalPhoneNumber,'
    'places.types,places.businessStatus,places.regularOpeningHours,'
    'places.rating,places.userRatingCount';

// ── Keyword query lists ────────────────────────────────────────────────────────

const _towingQueries = [
  'towing service',
  'tow truck',
  'vehicle recovery',
  'breakdown recovery',
];

const _breakdownQueries = [
  'roadside assistance',
  'emergency mechanic',
  'mobile mechanic',
  'vehicle assistance',
];

const _punctureQueries = [
  'puncture repair',
  'tire repair',
  'tyre repair',
  'flat tire repair',
];

const _fuelQueries = [
  'fuel delivery',
  'emergency fuel',
];

/// Maps our internal category string → the list of text queries to run.
const _categoryQueries = <String, List<String>>{
  'towing':    _towingQueries,
  'breakdown': _breakdownQueries,
  'puncture':  _punctureQueries,
  'fuel':      _fuelQueries,
};

// ── Service ────────────────────────────────────────────────────────────────────

class GooglePlacesService {
  const GooglePlacesService({required this.apiKey});

  final String apiKey;
  bool get _hasKey => apiKey.isNotEmpty;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetches services for [categories] using keyword Text Search.
  ///
  /// Each category runs all its query terms concurrently, results are merged
  /// and deduplicated by place ID before being returned sorted by distance.
  Future<List<ServiceModel>> fetchNearbyServices({
    required double lat,
    required double lng,
    required List<String> categories,
    required String countryCode,
  }) async {
    if (!_hasKey) {
      debugPrint('[GooglePlaces] No API key — skipping');
      return const [];
    }

    final seen    = <String>{};
    final results = <ServiceModel>[];

    for (final category in categories) {
      final queries = _categoryQueries[category];
      if (queries == null || queries.isEmpty) {
        debugPrint('[GooglePlaces] No queries defined for category: $category');
        continue;
      }

      // Run all query terms for this category concurrently.
      final futures = queries.map((q) => _textSearch(
            query: q,
            lat: lat,
            lng: lng,
            category: category,
            countryCode: countryCode,
          ));

      final batches = await Future.wait(futures, eagerError: false);
      int added = 0;
      for (final batch in batches) {
        for (final s in batch) {
          if (seen.add(s.id)) {
            results.add(s);
            added++;
          }
        }
      }
      debugPrint('[GooglePlaces] $category → $added unique results '
          '(${queries.length} queries)');
    }

    results.sort((a, b) => (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999));
    debugPrint('[GooglePlaces] Total: ${results.length} services');
    return results;
  }

  // ── Text Search (New) ──────────────────────────────────────────────────────

  Future<List<ServiceModel>> _textSearch({
    required String query,
    required double lat,
    required double lng,
    required String category,
    required String countryCode,
  }) async {
    try {
      debugPrint('[GooglePlaces] textSearch "$query" near ($lat,$lng)');

      final body = jsonEncode({
        'textQuery': query,
        'maxResultCount': _maxResults,
        'locationBias': {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': _radiusM,
          },
        },
        // Prefer results in the user's country without hard-excluding others.
        'regionCode': countryCode.toLowerCase(),
      });

      final response = await http
          .post(
            Uri.parse(_textSearchEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': apiKey,
              'X-Goog-FieldMask': _fieldMask,
            },
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
            '[GooglePlaces] HTTP ${response.statusCode} for "$query": '
            '${response.body.substring(0, response.body.length.clamp(0, 200))}');
        return const [];
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final places  = (decoded['places'] as List<dynamic>?) ?? [];
      debugPrint('[GooglePlaces] "$query" → ${places.length} raw results');

      return places
          .map((p) => _parsePlace(
                p as Map<String, dynamic>,
                lat, lng, category, countryCode,
              ))
          .whereType<ServiceModel>()
          .toList();
    } catch (e) {
      debugPrint('[GooglePlaces] textSearch "$query" error: $e');
      return const [];
    }
  }

  // ── Response parser ────────────────────────────────────────────────────────

  ServiceModel? _parsePlace(
    Map<String, dynamic> place,
    double userLat,
    double userLng,
    String category,
    String countryCode,
  ) {
    // displayName is a localised object: { "text": "...", "languageCode": "..." }
    final name =
        (place['displayName'] as Map<String, dynamic>?)?['text'] as String?;
    if (name == null || name.trim().isEmpty) return null;

    final loc = place['location'] as Map<String, dynamic>?;
    final lat = (loc?['latitude']  as num?)?.toDouble();
    final lng = (loc?['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    // Skip permanently closed places.
    final status = (place['businessStatus'] as String?) ?? '';
    if (status.contains('PERMANENTLY_CLOSED') ||
        status.contains('CLOSED_PERMANENTLY')) {
      return null;
    }

    // Phone — prefer international format.
    final phone =
        (place['internationalPhoneNumber'] as String?)?.trim().isNotEmpty == true
            ? (place['internationalPhoneNumber'] as String).trim()
            : (place['nationalPhoneNumber'] as String?)?.trim();

    final address = (place['formattedAddress'] as String?)?.trim();

    // 24h detection: any weekday description mentions "24 hours".
    final hours = place['regularOpeningHours'] as Map<String, dynamic>?;
    final is24hr =
        (hours?['weekdayDescriptions'] as List<dynamic>?)
            ?.any((d) => d.toString().toLowerCase().contains('24 hours')) ==
        true;

    final id = (place['id'] as String?) ?? '${lat}_$lng';

    // Trust score: 4 for Google Places text-search results.
    // (5 = government/official, 4 = aggregated verified business listings)
    return ServiceModel(
      id: 'gplaces_$id',
      name: name.trim(),
      category: category,
      subcategory: (place['types'] as List<dynamic>?)?.firstOrNull?.toString(),
      lat: lat,
      lng: lng,
      phonePrimary: phone,
      address: address,
      countryCode: countryCode,
      is24hr: is24hr,
      trustScore: 4,
      source: 'google_places',
      distanceKm: _haversineKm(userLat, userLng, lat, lng),
    );
  }

  // ── Haversine ──────────────────────────────────────────────────────────────

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
