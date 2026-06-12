// lib/data/remote/api_client.dart
// Module 5 (updated) — HTTP client for the RoadSoS FastAPI backend.
//
// Changes from Module 4:
//   • Constructor now accepts an optional [AppDatabase] so the
//     OfflineInterceptor can serve cached responses when offline.
//   • OfflineInterceptor added to Dio interceptor stack.
//
// All methods return null / empty / false on failure — never throw.
// This ensures the app degrades gracefully to the offline cache.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/interceptors/offline_interceptor.dart';
import '../../data/local/database.dart';
import '../models/service_model.dart';
import '../models/victim_detail.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient({AppDatabase? db}) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: Duration(seconds: AppConfig.apiTimeoutSeconds),
      receiveTimeout: Duration(seconds: AppConfig.apiTimeoutSeconds),
      headers: {'Content-Type': 'application/json'},
    ));

    // Offline cache interceptor — runs first so it can resolve before errors
    // reach the error logger.
    if (db != null) {
      _dio.interceptors.add(OfflineInterceptor(db: db));
    }

    // Error logger — runs after the offline interceptor so cache hits are
    // not logged as errors.
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, handler) {
        _logError('DioException', e);
        handler.next(e);
      },
    ));
  }

  // ── Service endpoints ──────────────────────────────────────────────────────

  /// Fetches nearby services from the backend.
  ///
  /// Returns an empty list on any error.
  Future<List<ServiceModel>> getNearbyServices({
    required double lat,
    required double lng,
    String? category,
    String? countryCode,
    int minTrustScore = 1,
  }) async {
    try {
      final response = await _dio.get(
        '/api/services/nearby',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          if (category != null) 'category': category,
          if (countryCode != null) 'country_code': countryCode,
          'min_trust_score': minTrustScore,
        },
      );
      final data = response.data as Map<String, dynamic>?;
      final rawList = data?['services'] as List<dynamic>?;
      if (rawList == null) return [];
      return rawList
          .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log('getNearbyServices', e);
      return [];
    }
  }

  /// Returns emergency numbers for [countryCode] or null on failure.
  Future<Map<String, String>?> getEmergencyNumbers(String countryCode) async {
    try {
      final response = await _dio.get(
        '/api/services/emergency-numbers/$countryCode',
      );
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return null;
      return data.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      _log('getEmergencyNumbers', e);
      return null;
    }
  }

  // ── Emergency endpoints ────────────────────────────────────────────────────

  /// Starts an emergency session on the backend.
  ///
  /// Returns the session ID string, or null if the request fails.
  Future<String?> startEmergency({
    required double lat,
    required double lng,
    required String emergencyType,
    required String victimType,
    String? userPhone,
    int? victimCount,
    List<VictimDetail>? victimDetails,
  }) async {
    try {
      final response = await _dio.post(
        '/api/emergency/start',
        data: {
          'lat': lat,
          'lng': lng,
          'emergency_type': emergencyType,
          'victim_type': victimType,
          if (userPhone != null) 'user_phone': userPhone,
          if (victimCount != null) 'victim_count': victimCount,
          if (victimDetails != null && victimDetails.isNotEmpty)
            'victim_details':
                victimDetails.map((v) => v.toJson()).toList(),
        },
      );
      final data = response.data as Map<String, dynamic>?;
      return data?['session_id'] as String?;
    } catch (e) {
      _log('startEmergency', e);
      return null;
    }
  }

  /// Sends a location ping for an active session.
  ///
  /// Returns true if the ping was accepted.
  Future<bool> pingEmergency({
    required String sessionId,
    required double lat,
    required double lng,
    double? accuracyM,
  }) async {
    try {
      await _dio.post(
        '/api/emergency/ping',
        data: {
          'session_id': sessionId,
          'lat': lat,
          'lng': lng,
          if (accuracyM != null) 'accuracy_m': accuracyM,
        },
      );
      return true;
    } catch (e) {
      _log('pingEmergency', e);
      return false;
    }
  }

  /// Resolves (closes) an active emergency session.
  Future<bool> resolveEmergency(String sessionId) async {
    try {
      await _dio.post(
        '/api/emergency/resolve',
        data: {'session_id': sessionId},
      );
      return true;
    } catch (e) {
      _log('resolveEmergency', e);
      return false;
    }
  }

  /// Uploads an image as proof/context for an active emergency.
  /// 
  /// In a real backend, this would use MultipartFile. Here we simulate success.
  Future<bool> uploadProof({
    required String sessionId,
    String? imagePath,
    String? details,
  }) async {
    try {
      // Simulation of a multipart upload for the hackathon
      await Future.delayed(const Duration(seconds: 1));
      
      // If we had a real endpoint:
      // final formData = FormData.fromMap({
      //   'session_id': sessionId,
      //   'file': await MultipartFile.fromFile(imagePath),
      //   if (details != null) 'details': details,
      // });
      // await _dio.post('/api/emergency/proof', data: formData);
      
      debugPrint('[ApiClient] Simulated photo upload for $sessionId with details: $details');
      return true;
    } catch (e) {
      _log('uploadProof', e);
      return false;
    }
  }

  /// Reports a data quality issue for a service.
  Future<bool> reportService({
    required String serviceId,
    required String reportType,
  }) async {
    try {
      await _dio.post(
        '/api/services/report',
        data: {
          'service_id': serviceId,
          'report_type': reportType,
        },
      );
      return true;
    } catch (e) {
      _log('reportService', e);
      return false;
    }
  }

  // ── Logging helpers ────────────────────────────────────────────────────────

  void _log(String method, Object error) {
    debugPrint('[ApiClient] $method failed: $error');
  }

  void _logError(String type, DioException e) {
    debugPrint(
      '[ApiClient] $type — '
      'status: ${e.response?.statusCode} '
      'message: ${e.message} '
      'body: ${e.response?.data}',
    );
  }
}

/// Riverpod provider for [ApiClient].
///
/// Passes the local database so the OfflineInterceptor can serve cached
/// responses when the backend is unreachable.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(db: ref.read(databaseProvider)),
);
