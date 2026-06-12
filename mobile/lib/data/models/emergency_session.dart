import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'victim_detail.dart';

/// Represents an active or resolved emergency session.
@immutable
class EmergencySession {
  final String sessionId;
  final String? userPhone;
  final DateTime startedAt;

  /// Emergency type: 'accident' | 'fire' | 'medical' | 'unsafe'
  final String emergencyType;

  /// Victim type: 'people_injured' | 'vehicle_only' | 'self' | 'bystander'
  final String victimType;

  final double lat;
  final double lng;
  final String countryCode;
  final int? victimCount;
  final List<VictimDetail> victimDetails;
  final bool isActive;
  final DateTime? resolvedAt;

  const EmergencySession({
    required this.sessionId,
    this.userPhone,
    required this.startedAt,
    required this.emergencyType,
    required this.victimType,
    required this.lat,
    required this.lng,
    required this.countryCode,
    this.victimCount,
    this.victimDetails = const [],
    this.isActive = true,
    this.resolvedAt,
  });

  factory EmergencySession.fromJson(Map<String, dynamic> json) {
    final rawVictims = json['victim_details'];
    final List<VictimDetail> victims = rawVictims is List
        ? rawVictims
            .map((v) => VictimDetail.fromJson(v as Map<String, dynamic>))
            .toList()
        : [];

    return EmergencySession(
      sessionId: json['session_id'] as String? ?? '',
      userPhone: json['user_phone'] as String?,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : DateTime.now(),
      emergencyType: json['emergency_type'] as String? ?? 'accident',
      victimType: json['victim_type'] as String? ?? 'self',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      countryCode: json['country_code'] as String? ?? 'IN',
      victimCount: (json['victim_count'] as num?)?.toInt(),
      victimDetails: victims,
      isActive: json['is_active'] as bool? ?? true,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'user_phone': userPhone,
      'started_at': startedAt.toIso8601String(),
      'emergency_type': emergencyType,
      'victim_type': victimType,
      'lat': lat,
      'lng': lng,
      'country_code': countryCode,
      'victim_count': victimCount,
      'victim_details': victimDetails.map((v) => v.toJson()).toList(),
      'is_active': isActive,
      'resolved_at': resolvedAt?.toIso8601String(),
    };
  }

  EmergencySession copyWith({
    String? sessionId,
    String? userPhone,
    DateTime? startedAt,
    String? emergencyType,
    String? victimType,
    double? lat,
    double? lng,
    String? countryCode,
    int? victimCount,
    List<VictimDetail>? victimDetails,
    bool? isActive,
    DateTime? resolvedAt,
  }) {
    return EmergencySession(
      sessionId: sessionId ?? this.sessionId,
      userPhone: userPhone ?? this.userPhone,
      startedAt: startedAt ?? this.startedAt,
      emergencyType: emergencyType ?? this.emergencyType,
      victimType: victimType ?? this.victimType,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      countryCode: countryCode ?? this.countryCode,
      victimCount: victimCount ?? this.victimCount,
      victimDetails: victimDetails ?? this.victimDetails,
      isActive: isActive ?? this.isActive,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }

  /// Creates a new session with a generated UUID and current timestamp.
  factory EmergencySession.create({
    required String emergencyType,
    required String victimType,
    required double lat,
    required double lng,
    required String countryCode,
    String? userPhone,
  }) {
    return EmergencySession(
      sessionId: const Uuid().v4(),
      userPhone: userPhone,
      startedAt: DateTime.now(),
      emergencyType: emergencyType,
      victimType: victimType,
      lat: lat,
      lng: lng,
      countryCode: countryCode,
      isActive: true,
    );
  }
}
