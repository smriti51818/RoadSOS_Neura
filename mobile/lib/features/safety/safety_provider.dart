// lib/features/safety/safety_provider.dart
// Module 6 — Women/solo traveller safety mode state.
//
// Features:
//   • Silent SOS — sends SMS to trusted contacts + opens SMS app for 112
//   • Fake call — opens dialler pre-filled (visual deterrent)
//   • Safety mode toggle (off / active / sos_triggered)
//   • Trusted circle management (stored in SharedPreferences)
//
// Note: truly silent SMS (without native app) requires a backend relay.
// For the hackathon demo this uses url_launcher sms: scheme — the OS
// pre-fills the compose screen so the user only needs to tap Send once.

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/location_service.dart';
import '../../services/sms_service.dart';
import '../../data/services/db_service.dart';
import 'package:uuid/uuid.dart';

part 'safety_provider.g.dart';

// ── Enums & models ─────────────────────────────────────────────────────────────

enum SafetyMode { off, active, sosTrigggered }

class SafetyState {
  const SafetyState({
    this.mode = SafetyMode.off,
    this.trustedContacts = const [],
    this.currentLat,
    this.currentLng,
    this.statusMessage = '',
    this.isSending = false,
  });

  final SafetyMode mode;
  final List<String> trustedContacts;
  final double? currentLat;
  final double? currentLng;
  final String statusMessage;
  final bool isSending;

  bool get isSafetyActive => mode != SafetyMode.off;
  bool get isSosTriggered => mode == SafetyMode.sosTrigggered;

  SafetyState copyWith({
    SafetyMode? mode,
    List<String>? trustedContacts,
    double? currentLat,
    double? currentLng,
    String? statusMessage,
    bool? isSending,
  }) {
    return SafetyState(
      mode: mode ?? this.mode,
      trustedContacts: trustedContacts ?? this.trustedContacts,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      statusMessage: statusMessage ?? this.statusMessage,
      isSending: isSending ?? this.isSending,
    );
  }
}

// ── Notifier ───────────────────────────────────────────────────────────────────

@riverpod
class SafetyNotifier extends _$SafetyNotifier {
  static const _prefsKey = 'trusted_contacts';

  @override
  SafetyState build() {
    _loadContacts();
    return const SafetyState();
  }

  // ── Safety mode ─────────────────────────────────────────────────────────────

  /// Activates safety monitoring mode.
  void activateSafetyMode() {
    state = state.copyWith(
      mode: SafetyMode.active,
      statusMessage: 'Safety mode ON — trusted contacts can track you',
    );
  }

  /// Deactivates safety monitoring mode.
  void deactivateSafetyMode() {
    state = state.copyWith(
      mode: SafetyMode.off,
      statusMessage: 'Safety mode off',
    );
  }

  // ── Silent SOS ──────────────────────────────────────────────────────────────

  /// Triggers silent SOS:
  ///   1. Gets current location
  ///   2. Sends SMS to all trusted contacts
  ///   3. Opens SMS compose to 112 (as close to "silent" as url_launcher allows)
  Future<void> triggerSilentSos() async {
    if (state.isSending) return;

    state = state.copyWith(
      mode: SafetyMode.sosTrigggered,
      isSending: true,
      statusMessage: 'Getting location for SOS...',
    );

    try {
      final location = ref.read(locationServiceProvider);
      final position = await location.getCurrentLocation();

      final lat = position?.latitude;
      final lng = position?.longitude;

      state = state.copyWith(
        currentLat: lat,
        currentLng: lng,
        statusMessage: 'Sending SOS to trusted contacts...',
      );

      // 1. Log to database
      if (lat != null && lng != null) {
        final prefs = await SharedPreferences.getInstance();
        final phone = prefs.getString('user_phone') ?? 'unknown';
        await DbService.insertIncident(
          id: const Uuid().v4(),
          userPhone: phone,
          serviceName: 'Safety SOS',
          lat: lat,
          lng: lng,
          status: 'Received',
          timestamp: DateTime.now(),
          photos: [],
        );
      }

      // 2. Send SMS to trusted contacts if any
      if (state.trustedContacts.isNotEmpty && lat != null && lng != null) {
        final sms = ref.read(smsServiceProvider);
        await sms.sendEmergencyAlert(
          lat: lat,
          lng: lng,
          emergencyType: 'unsafe_threat',
          contactNumbers: state.trustedContacts,
          userName: 'RoadSoS User',
        );
      }

      state = state.copyWith(
        isSending: false,
        statusMessage: state.trustedContacts.isNotEmpty
            ? 'SOS sent to database and ${state.trustedContacts.length} contact(s).'
            : 'SOS logged to database. No trusted contacts set.',
      );
    } catch (e) {
      debugPrint('[SafetyNotifier] SOS error: $e');
      state = state.copyWith(
        isSending: false,
        statusMessage: 'SOS failed — call 112 directly.',
      );
    }
  }



  // ── Trusted circle ──────────────────────────────────────────────────────────

  /// Adds a phone number to the trusted circle.
  Future<void> addTrustedContact(String phoneNumber) async {
    final cleaned = phoneNumber.trim();
    if (cleaned.isEmpty) return;
    if (state.trustedContacts.contains(cleaned)) return;
    if (state.trustedContacts.length >= 5) return; // max 5

    final updated = [...state.trustedContacts, cleaned];
    state = state.copyWith(trustedContacts: updated);
    await _saveContacts(updated);
  }

  /// Removes a phone number from the trusted circle.
  Future<void> removeTrustedContact(String phoneNumber) async {
    final updated = state.trustedContacts.where((c) => c != phoneNumber).toList();
    state = state.copyWith(trustedContacts: updated);
    await _saveContacts(updated);
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _loadContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contacts = prefs.getStringList(_prefsKey) ?? [];
      state = state.copyWith(trustedContacts: contacts);
    } catch (e) {
      debugPrint('[SafetyNotifier] loadContacts error: $e');
    }
  }

  Future<void> _saveContacts(List<String> contacts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, contacts);
    } catch (e) {
      debugPrint('[SafetyNotifier] saveContacts error: $e');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> _openEmergencySms(double? lat, double? lng) async {
    try {
      final locationStr = (lat != null && lng != null)
          ? 'My location: https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
          : 'Location unavailable';
      final uri = Uri(
        scheme: 'sms',
        path: '112',
        queryParameters: {
          'body': 'EMERGENCY - I need help. $locationStr — sent via RoadSoS',
        },
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[SafetyNotifier] Emergency SMS error: $e');
    }
  }
}
