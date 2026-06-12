import 'package:flutter/foundation.dart';

/// Emergency contact numbers for a specific country.
@immutable
class EmergencyNumbersConfig {
  final String? police;
  final String? ambulance;
  final String? fire;
  final String unified;
  final String? coastGuard;
  final String? disaster;

  const EmergencyNumbersConfig({
    this.police,
    this.ambulance,
    this.fire,
    required this.unified,
    this.coastGuard,
    this.disaster,
  });

  factory EmergencyNumbersConfig.fromJson(Map<String, dynamic> json) {
    return EmergencyNumbersConfig(
      police: json['police'] as String?,
      ambulance: json['ambulance'] as String?,
      fire: json['fire'] as String?,
      unified: json['unified'] as String? ?? '112',
      coastGuard: json['coast_guard'] as String?,
      disaster: json['disaster'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'police': police,
      'ambulance': ambulance,
      'fire': fire,
      'unified': unified,
      'coast_guard': coastGuard,
      'disaster': disaster,
    };
  }

  /// Returns [unified] — always has a value regardless of country config.
  String get primaryNumber => unified;
}

/// Per-country configuration controlling map providers, radii, and data sources.
@immutable
class CountryConfig {
  final String countryCode;
  final String name;
  final EmergencyNumbersConfig emergencyNumbers;

  /// Map provider: 'mappls' (India) | 'osm' (global)
  final String mapProvider;

  /// Ordered list of data source adapters to use for this country.
  final List<String> dataSources;

  final int urbanRadiusKm;
  final int ruralRadiusKm;
  final bool isSupported;

  const CountryConfig({
    required this.countryCode,
    required this.name,
    required this.emergencyNumbers,
    required this.mapProvider,
    required this.dataSources,
    required this.urbanRadiusKm,
    required this.ruralRadiusKm,
    required this.isSupported,
  });

  factory CountryConfig.fromJson(Map<String, dynamic> json) {
    final rawNumbers = json['emergency_numbers'];
    final numbers = rawNumbers is Map<String, dynamic>
        ? EmergencyNumbersConfig.fromJson(rawNumbers)
        : EmergencyNumbersConfig(unified: '112');

    final rawSources = json['data_sources'];
    final sources = rawSources is List
        ? List<String>.from(rawSources.map((s) => s.toString()))
        : <String>['osm'];

    return CountryConfig(
      countryCode: json['country_code'] as String? ?? 'DEFAULT',
      name: json['name'] as String? ?? 'Unknown',
      emergencyNumbers: numbers,
      mapProvider: json['map_provider'] as String? ?? 'osm',
      dataSources: sources,
      urbanRadiusKm: (json['urban_radius_km'] as num?)?.toInt() ?? 10,
      ruralRadiusKm: (json['rural_radius_km'] as num?)?.toInt() ?? 100,
      isSupported: json['is_supported'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'country_code': countryCode,
      'name': name,
      'emergency_numbers': emergencyNumbers.toJson(),
      'map_provider': mapProvider,
      'data_sources': dataSources,
      'urban_radius_km': urbanRadiusKm,
      'rural_radius_km': ruralRadiusKm,
      'is_supported': isSupported,
    };
  }

  /// Returns the global default config when country is unknown or unsupported.
  factory CountryConfig.defaultConfig() {
    return CountryConfig(
      countryCode: 'DEFAULT',
      name: 'Global',
      emergencyNumbers: const EmergencyNumbersConfig(unified: '112'),
      mapProvider: 'osm',
      dataSources: const ['hdx', 'osm'],
      urbanRadiusKm: 10,
      ruralRadiusKm: 100,
      isSupported: true,
    );
  }
}
