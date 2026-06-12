// File 10 of 12 — Module 4
// mobile/lib/services/sms_service.dart
//
// SMS alert service using url_launcher sms: URI scheme.
//
// Design rules:
//   • NEVER throw — SMS failure must never block the emergency flow
//   • Uses sms: URI scheme — no Twilio, no server-side SMS required
//   • Works offline — uses the native SMS app

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/victim_detail.dart';

part 'sms_service.g.dart';

class SMSService {
  // ── Public API ─────────────────────────────────────────────────────────────

  /// Sends a full emergency alert SMS to all [contactNumbers].
  ///
  /// Opens the native SMS app pre-filled with the emergency message.
  /// Returns true if the SMS app was launched successfully.
  Future<bool> sendEmergencyAlert({
    required double lat,
    required double lng,
    required String emergencyType,
    required List<String> contactNumbers,
    String? userName,
    int? victimCount,
    List<VictimDetail>? victimDetails,
  }) async {
    if (contactNumbers.isEmpty) {
      debugPrint('[SMSService] No contacts — skipping');
      return false;
    }
    try {
      final message = _buildEmergencyMessage(
        lat: lat,
        lng: lng,
        emergencyType: emergencyType,
        userName: userName,
        victimCount: victimCount,
        victimDetails: victimDetails,
      );

      final uri = Uri(
        scheme: 'sms',
        path: contactNumbers.join(';'),
        queryParameters: {'body': message},
      );

      debugPrint('[SMSService] Launching emergency SMS URI: $uri');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      debugPrint('[SMSService] Emergency SMS launched ✓');
      return true;
    } catch (e) {
      debugPrint('[SMSService] sendEmergencyAlert error: $e');
      return false;
    }
  }

  /// Opens native SMS app pre-filled with location.
  ///
  /// If [contactNumbers] is empty, opens a blank compose screen so the user
  /// can type a recipient manually — never silently fails in an emergency.
  Future<bool> sendLocationUpdate({
    required double lat,
    required double lng,
    required List<String> contactNumbers,
    String? userName,
  }) async {
    try {
      final name = userName ?? 'Someone you know';
      final time = DateFormat('HH:mm, dd MMM yyyy').format(DateTime.now());
      final latF = lat.toStringAsFixed(6);
      final lngF = lng.toStringAsFixed(6);

      final message = '📍 RoadSoS: $name needs help. '
          'Location: https://maps.google.com/?q=$latF,$lngF ($time)';

      // path = recipients (empty string → blank compose, user enters number)
      final uri = Uri(
        scheme: 'sms',
        path: contactNumbers.join(';'), // semicolon works on both Android & iOS
        queryParameters: {'body': message},
      );

      debugPrint('[SMSService] Launching SMS URI: $uri');

      // Use externalApplication so Android always opens the default SMS app,
      // not a WebView. Don't gate on canLaunchUrl — on some Android 11+
      // devices it returns false even when the SMS app is available.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      debugPrint('[SMSService] SMS app launched ✓');
      return true;
    } catch (e) {
      debugPrint('[SMSService] sendLocationUpdate error: $e');
      return false;
    }
  }

  // ── Message builder ────────────────────────────────────────────────────────

  String _buildEmergencyMessage({
    required double lat,
    required double lng,
    required String emergencyType,
    String? userName,
    int? victimCount,
    List<VictimDetail>? victimDetails,
  }) {
    final name = userName ?? 'Someone you know';
    final latF = lat.toStringAsFixed(6);
    final lngF = lng.toStringAsFixed(6);
    final time = DateFormat('HH:mm, dd MMM yyyy').format(DateTime.now());

    final typeLabel = _emergencyTypeLabel(emergencyType);
    final victimSummary = _buildVictimSummary(victimCount, victimDetails);

    return '🚨 ROADSOS EMERGENCY ALERT\n'
        '\n'
        '$name needs emergency help.\n'
        '\n'
        '📍 Location: $latF, $lngF\n'
        '🗺️ Maps: https://maps.google.com/?q=$latF,$lngF\n'
        '\n'
        'Emergency: $typeLabel\n'
        'Victims: $victimSummary\n'
        'Time: $time\n'
        '\n'
        'This is an automated RoadSoS alert. '
        'Call them or go to their location.';
  }

  String _buildVictimSummary(
    int? victimCount,
    List<VictimDetail>? victimDetails,
  ) {
    if (victimDetails != null && victimDetails.isNotEmpty) {
      final parts = victimDetails.map((v) {
        final flags = <String>[];
        if (v.needsPediatricUnit) flags.add('Child');
        if (v.isSenior) flags.add('Senior');
        if (v.needsFireRescue) flags.add('Trapped/Fire');
        final flagStr = flags.isNotEmpty ? ' (${flags.join(', ')})' : '';
        return '${v.ageGroupLabel}$flagStr';
      }).toList();
      final count = victimDetails.length;
      return '$count ${count == 1 ? 'person' : 'people'} — ${parts.join('; ')}';
    }
    final count = victimCount ?? 1;
    return '$count ${count == 1 ? 'person' : 'people'}';
  }

  String _emergencyTypeLabel(String type) {
    switch (type) {
      case 'accident':
        return 'Road Accident / Injury';
      case 'fire':
        return 'Fire on Road';
      case 'medical':
        return 'Medical Emergency';
      case 'unsafe':
        return 'Unsafe / Threat';
      default:
        return type;
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

@riverpod
SMSService smsService(SmsServiceRef ref) => SMSService();
