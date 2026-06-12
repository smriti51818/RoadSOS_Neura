// lib/core/interceptors/offline_interceptor.dart
// Module 5 — Dio interceptor for transparent SQLite cache fallback.
//
// Intercepts GET /api/services/nearby requests that fail due to network errors
// and returns previously-cached SQLite data wrapped in a synthetic Response.
//
// This keeps ApiClient callers blissfully unaware of offline state — they get
// a 200 response with a 'source: offline_cache' marker in the body.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../data/local/database.dart';
import '../../data/models/service_model.dart';

class OfflineInterceptor extends Interceptor {
  OfflineInterceptor({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  // Only intercept GET requests to the nearby-services endpoint.
  static const _targetPath = '/api/services/nearby';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final method = err.requestOptions.method.toUpperCase();
    final path = err.requestOptions.path;
    final isNetworkError = err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.unknown ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout;

    if (method == 'GET' && path.contains(_targetPath) && isNetworkError) {
      try {
        final cached = await _queryCached(err.requestOptions);
        if (cached.isNotEmpty) {
          debugPrint(
              '[OfflineInterceptor] Serving ${cached.length} cached services for $path');
          handler.resolve(
            Response(
              requestOptions: err.requestOptions,
              statusCode: 200,
              data: {
                'services': cached.map((s) => s.toJson()).toList(),
                'source': 'offline_cache',
              },
            ),
          );
          return;
        }
        debugPrint('[OfflineInterceptor] No cached services for $path');
      } catch (e) {
        debugPrint('[OfflineInterceptor] Cache fallback error: $e');
      }
    }

    handler.next(err);
  }

  Future<List<ServiceModel>> _queryCached(RequestOptions options) async {
    final params = options.queryParameters;
    final lat = (params['lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (params['lng'] as num?)?.toDouble() ?? 0.0;
    final category = params['category'] as String?;
    final minTrust = (params['min_trust_score'] as num?)?.toInt() ?? 1;

    final rows = await _db.servicesDao.getNearbyServices(
      lat: lat,
      lng: lng,
      radiusKm: 10,
      category: category,
      minTrustScore: minTrust,
    );

    return rows.map((r) {
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
        source: '${r.source}_cache',
        isActive: true,
      );
    }).toList();
  }
}
