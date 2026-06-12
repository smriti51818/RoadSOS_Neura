import 'package:flutter/foundation.dart';

/// Represents a single emergency or non-emergency service (hospital, police, etc.).
@immutable
class ServiceModel {
  final String id;
  final String name;
  final String category;
  final String? subcategory;
  final double lat;
  final double lng;
  final String? phonePrimary;
  final String? phoneSecondary;
  final String? address;
  final String countryCode;
  final String? stateCode;
  final bool is24hr;

  /// Trust score 1–5. Only scores ≥ 3 shown in emergency mode.
  final int trustScore;

  /// Data source identifier (e.g. "data_gov_in", "osm", "mappls").
  final String source;

  final String? verifiedDate;
  final bool isActive;

  /// Distance from user in km — null until calculated.
  final double? distanceKm;

  const ServiceModel({
    required this.id,
    required this.name,
    required this.category,
    this.subcategory,
    required this.lat,
    required this.lng,
    this.phonePrimary,
    this.phoneSecondary,
    this.address,
    required this.countryCode,
    this.stateCode,
    this.is24hr = false,
    required this.trustScore,
    required this.source,
    this.verifiedDate,
    this.isActive = true,
    this.distanceKm,
  });

  /// Creates a [ServiceModel] from a JSON map returned by the backend.
  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    return ServiceModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unknown',
      category: json['category'] as String? ?? '',
      subcategory: json['subcategory'] as String?,
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      phonePrimary: json['phone_primary'] as String?,
      phoneSecondary: json['phone_secondary'] as String?,
      address: json['address'] as String?,
      countryCode: json['country_code'] as String? ?? 'IN',
      stateCode: json['state_code'] as String?,
      is24hr: json['is_24hr'] as bool? ?? false,
      trustScore: (json['trust_score'] as num?)?.toInt() ?? 1,
      source: json['source'] as String? ?? 'unknown',
      verifiedDate: json['verified_date'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'subcategory': subcategory,
      'lat': lat,
      'lng': lng,
      'phone_primary': phonePrimary,
      'phone_secondary': phoneSecondary,
      'address': address,
      'country_code': countryCode,
      'state_code': stateCode,
      'is_24hr': is24hr,
      'trust_score': trustScore,
      'source': source,
      'verified_date': verifiedDate,
      'is_active': isActive,
      'distance_km': distanceKm,
    };
  }

  ServiceModel copyWith({
    String? id,
    String? name,
    String? category,
    String? subcategory,
    double? lat,
    double? lng,
    String? phonePrimary,
    String? phoneSecondary,
    String? address,
    String? countryCode,
    String? stateCode,
    bool? is24hr,
    int? trustScore,
    String? source,
    String? verifiedDate,
    bool? isActive,
    double? distanceKm,
  }) {
    return ServiceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      phonePrimary: phonePrimary ?? this.phonePrimary,
      phoneSecondary: phoneSecondary ?? this.phoneSecondary,
      address: address ?? this.address,
      countryCode: countryCode ?? this.countryCode,
      stateCode: stateCode ?? this.stateCode,
      is24hr: is24hr ?? this.is24hr,
      trustScore: trustScore ?? this.trustScore,
      source: source ?? this.source,
      verifiedDate: verifiedDate ?? this.verifiedDate,
      isActive: isActive ?? this.isActive,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }

  /// Human-readable distance string, e.g. "0.8 km" or "1.2 km".
  String get formattedDistance {
    if (distanceKm == null) return '';
    return '${distanceKm!.toStringAsFixed(1)} km';
  }

  /// Human-readable label for the trust score.
  String get trustLabel {
    switch (trustScore) {
      case 5:
        return 'Govt Verified';
      case 4:
        return 'Verified';
      case 3:
        return 'Community Verified';
      case 2:
        return 'Unverified';
      default:
        return 'Unreviewed';
    }
  }

  /// Returns true if this service meets the emergency trust threshold (≥ 3).
  bool get isEmergencyTrusted => trustScore >= 3;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ServiceModel($id, $name, $category)';
}
