import 'dart:convert';
import 'package:http/http.dart' as http;

/// DbService sends data to the Next.js web dashboard API server.
/// The Next.js server securely connects to Neon Postgres.
/// 
/// WHY: Android blocks direct TCP connections to port 5432 (raw Postgres protocol).
/// HTTP (port 80/443) is always allowed. This is also correct production architecture.
///
/// To test on an emulator, the Next.js dev server must be running.
/// The emulator's localhost maps to 10.0.2.2 on Android.
/// For a real device on the same WiFi, use your Mac's local IP (e.g. 192.168.1.x:3000).
class DbService {
  // For Android emulator: 10.0.2.2 maps to host machine's localhost.
  // For a real device on the same WiFi, change to your Mac's IP, e.g. 192.168.1.x:3000
  static const String baseUrl = 'http://192.168.0.102:3000/api';

  static Future<void> upsertUser(String phone, String name, String bloodGroup) async {
    if (phone.isEmpty) return;

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'name': name,
              'blood_group': bloodGroup,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('[DbService] upsertUser failed: $e');
      rethrow;
    }
  }

  static Future<void> insertIncident({
    required String id,
    required String userPhone,
    required String serviceName,
    required double lat,
    required double lng,
    required String status,
    required DateTime timestamp,
    required List<String> photos,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/incidents'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': id,
              'user_phone': userPhone.isEmpty ? null : userPhone,
              'service_name': serviceName,
              'lat': lat,
              'lng': lng,
              'status': status,
              'timestamp': timestamp.toIso8601String(),
              'photos': photos.join(','),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('[DbService] insertIncident failed: $e');
      rethrow;
    }
  }
}
