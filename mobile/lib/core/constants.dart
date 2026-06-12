// api_keys.dart is gitignored — real key values as Dart constants.
// Acts as defaultValue fallback so plain `flutter run` works without any flags.
// CI/CD can override via --dart-define=GEOAPIFY_API_KEY=... etc.
import 'api_keys.dart';

/// App-wide constants loaded from --dart-define at build time,
/// with fallback defaults from the gitignored api_keys.dart.
class AppConstants {
  AppConstants._();

  /// Backend API URL. Defaults to Android emulator localhost.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String mapplsApiKey = String.fromEnvironment(
    'MAPPLS_API_KEY',
    defaultValue: kMapplsApiKey,
  );
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: kGeminiApiKey,
  );
  static const String geoapifyApiKey = String.fromEnvironment(
    'GEOAPIFY_API_KEY',
    defaultValue: kGeoapifyApiKey,
  );
  static const String googlePlacesApiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: kGooglePlacesApiKey,
  );
  static const String mapboxApiKey = String.fromEnvironment(
    'MAPBOX_API_KEY',
    defaultValue: kMapboxApiKey,
  );
}

/// Hardcoded emergency numbers — these can never be overridden by AI.
class EmergencyNumbers {
  EmergencyNumbers._();

  static const Map<String, String> india = {
    'police': '100',
    'ambulance': '108',
    'fire': '101',
    'unified': '112',
    'nhai': '1033',
    'traffic': '103',
    'women': '1091',
    'women_alt': '181',
    'disaster': '108',
  };

  /// UN-standard unified emergency — works in 90+ countries.
  static const String globalUnified = '112';
}

/// Runtime configuration constants.
class AppConfig {
  AppConfig._();

  static const int emergencyPingIntervalSeconds = 10;
  static const int journeyPingIntervalSeconds = 60;
  static const int defaultUrbanRadiusKm = 5;
  static const int defaultRuralRadiusKm = 50;
  static const int maxResultsPerCategory = 5;

  /// Minimum trust score to show a result in emergency mode.
  static const int minTrustScoreEmergency = 3;

  /// Minimum trust score to show a result in browse mode.
  static const int minTrustScoreBrowse = 2;

  /// Below this fraction (0.0–1.0) show battery warning.
  static const double lowBatteryThreshold = 0.20;

  static const int apiTimeoutSeconds = 5;
  static const int offlineCacheExpiryDays = 7;
  static const String appVersion = '1.0.0';
}

/// Service category string constants.
class ServiceCategories {
  ServiceCategories._();

  static const String police = 'police';
  static const String hospital = 'hospital';
  static const String ambulance = 'ambulance';
  static const String fire = 'fire';
  static const String towing = 'towing';
  static const String breakdown = 'breakdown';
  static const String puncture = 'puncture';
  static const String helpline = 'helpline';

  /// Categories shown during an active emergency.
  static const List<String> emergency = [police, hospital, ambulance, fire];

  /// Categories shown in non-emergency / browse mode.
  static const List<String> nonEmergency = [towing, breakdown, puncture, helpline];
}
