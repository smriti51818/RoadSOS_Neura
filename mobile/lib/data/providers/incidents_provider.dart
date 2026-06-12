import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/service_model.dart';
import '../services/db_service.dart';

class IncidentRecord {
  final String id;
  final DateTime timestamp;
  final ServiceModel service;
  final List<String> photos;
  final String status;

  IncidentRecord({
    required this.id,
    required this.timestamp,
    required this.service,
    required this.photos,
    required this.status,
  });
}

class IncidentsNotifier extends StateNotifier<List<IncidentRecord>> {
  IncidentsNotifier() : super([]);

  /// Used by the live tracking screen — the caller builds the record
  /// (so it has the ID to poll updates against) and passes it here.
  void addIncidentRecord(IncidentRecord record) async {
    state = [record, ...state];

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';

      await DbService.insertIncident(
        id: record.id,
        userPhone: phone,
        serviceName: record.service.name,
        lat: record.service.lat,
        lng: record.service.lng,
        status: record.status,
        timestamp: record.timestamp,
        photos: record.photos,
      );
    } catch (e) {
      print('[IncidentsNotifier] Failed to save: $e');
    }
  }

  /// Legacy helper — keeps other call-sites working.
  void addIncident({
    required ServiceModel service,
    required List<String> photos,
  }) {
    addIncidentRecord(IncidentRecord(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      service: service,
      photos: photos,
      status: 'Received',
    ));
  }
}

final incidentsProvider = StateNotifierProvider<IncidentsNotifier, List<IncidentRecord>>((ref) {
  return IncidentsNotifier();
});
