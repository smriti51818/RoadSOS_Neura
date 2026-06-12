import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../core/constants.dart';

/// Provides GPS location, reverse geocoding, and battery level utilities.
///
/// All methods degrade gracefully — never throw, always return a safe default.
class LocationService {
  final Battery _battery = Battery();

  /// Returns the current device position or null if unavailable.
  ///
  /// Checks and requests location permission before attempting to get location.
  /// Uses high accuracy with a 10-second timeout.
  Future<Position?> getCurrentLocation() async {
    try {
      final granted = await requestPermission();
      if (!granted) {
        debugPrint('[LocationService] Permission denied');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } on LocationServiceDisabledException {
      debugPrint('[LocationService] Location service disabled');
      return null;
    } on TimeoutException catch (_) {
      debugPrint('[LocationService] Timed out getting location');
      return null;
    } catch (e) {
      debugPrint('[LocationService] Error getting location: $e');
      return null;
    }
  }

  /// Requests location permission.
  ///
  /// Returns true if [LocationPermission.always] or [LocationPermission.whileInUse].
  Future<bool> requestPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      debugPrint('[LocationService] Permission error: $e');
      return false;
    }
  }

  /// Returns the ISO 3166-1 alpha-2 country code for [position].
  ///
  /// Falls back to 'IN' if reverse geocoding fails — this is acceptable
  /// since RoadSoS is primarily used in India.
  Future<String> getCountryCode(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final code = placemarks.first.isoCountryCode;
        if (code != null && code.isNotEmpty) return code.toUpperCase();
      }
    } catch (e) {
      debugPrint('[LocationService] Reverse geocode error: $e');
    }
    
    // Fallback roughly for contiguous US if reverse geocoding fails
    if (position.longitude >= -125.0 && 
        position.longitude <= -65.0 && 
        position.latitude >= 24.0 && 
        position.latitude <= 49.0) {
      return 'US';
    }
    
    return 'IN';
  }

  /// Stub — always returns false for Module 1.
  ///
  /// TODO: Implement via population density check using census data.
  /// Population density < 400/km² → rural.
  Future<bool> isRural(Position position) async {
    return false;
  }

  /// Returns a continuous stream of location updates.
  ///
  /// Default interval is 10 seconds (emergency ping frequency).
  /// Uses a 10-metre distance filter to avoid trivial updates.
  Stream<Position> getLocationStream({
    int intervalMs = 10000,
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: 10,
        timeLimit: Duration(milliseconds: intervalMs),
      ),
    );
  }

  /// Returns the battery level as a fraction 0.0–1.0, or null on error.
  Future<double?> getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      return level / 100.0;
    } catch (e) {
      debugPrint('[LocationService] Battery level error: $e');
      return null;
    }
  }

  /// Returns true if [level] is below the low-battery threshold (20%).
  bool isLowBattery(double? level) {
    return level != null && level < AppConfig.lowBatteryThreshold;
  }
}

/// Riverpod provider for [LocationService].
final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);
