// File 5 of 12 — Module 4
// mobile/lib/features/triage/triage_provider.dart
//
// Drives the two-step triage flow:
//   Step 1 — Emergency type (selected on home screen, passed as route param)
//   Step 2 — Who needs help (vehicle only / self / people / bystander)
//
// Architecture rules:
//   • Emergency session written to SQLite BEFORE any network call
//   • Police ping is fire-and-forget — never blocks UI
//   • SMS alert is fire-and-forget — never blocks UI
//   • Backend session start is parallel — local UUID used if API fails
//   • Navigation signals emitted via state flags; screen handles routing

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../data/models/victim_detail.dart';
import '../../data/remote/api_client.dart';
import '../../services/emergency_service.dart';
import '../../services/location_service.dart';
import '../../services/sms_service.dart';

part 'triage_provider.g.dart';

// ── State ──────────────────────────────────────────────────────────────────────

class TriageState {
  const TriageState({
    required this.emergencyType,
    required this.sessionId,
    this.victimType,
    this.currentStep = 1,
    this.isSubmitting = false,
    this.emergencyTriggered = false,
    this.position,
    this.readyForResults = false,
    this.resultsExtra,
  });

  /// From home screen grid selection: accident | fire | medical | unsafe.
  final String emergencyType;

  /// Filled in step 2: people_injured | vehicle_only | self | bystander.
  final String? victimType;

  /// 1 = "What happened?" (pre-filled from home), 2 = "Who needs help?".
  final int currentStep;

  /// True while [_triggerEmergency] background actions are firing.
  final bool isSubmitting;

  /// True once all three parallel actions have completed/resolved.
  final bool emergencyTriggered;

  /// Device GPS position — fetched in background, may be null briefly.
  final Position? position;

  /// UUID generated locally; may be updated if backend returns its own.
  final String sessionId;

  /// Navigation signal — screen pushes /results when true.
  final bool readyForResults;

  /// Params map to forward to /results via GoRouter extra.
  final Map<String, dynamic>? resultsExtra;

  TriageState copyWith({
    String? emergencyType,
    String? victimType,
    int? currentStep,
    bool? isSubmitting,
    bool? emergencyTriggered,
    Position? position,
    bool clearPosition = false,
    String? sessionId,
    bool? readyForResults,
    Map<String, dynamic>? resultsExtra,
    bool clearResultsExtra = false,
  }) =>
      TriageState(
        emergencyType: emergencyType ?? this.emergencyType,
        victimType: victimType ?? this.victimType,
        currentStep: currentStep ?? this.currentStep,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        emergencyTriggered: emergencyTriggered ?? this.emergencyTriggered,
        position: clearPosition ? null : (position ?? this.position),
        sessionId: sessionId ?? this.sessionId,
        readyForResults: readyForResults ?? this.readyForResults,
        resultsExtra:
            clearResultsExtra ? null : (resultsExtra ?? this.resultsExtra),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

/// Drives the triage screen. Auto-disposes when screen is popped.
///
/// Family key: [emergencyType] — passed from home screen grid tap.
@riverpod
class TriageNotifier extends _$TriageNotifier {
  @override
  Future<TriageState> build(String emergencyType) async {
    final sessionId = const Uuid().v4();

    // Kick off GPS fetch in background — does not block the screen render.
    ref.read(locationServiceProvider).getCurrentLocation().then((pos) {
      final cur = state.valueOrNull;
      if (cur != null && pos != null) {
        state = AsyncData(cur.copyWith(position: pos));
      }
    });

    return TriageState(emergencyType: emergencyType, sessionId: sessionId);
  }

  // ── Public actions ─────────────────────────────────────────────────────────

  /// Called when the user taps a triage card in step 2.
  ///
  /// For 'vehicle_only' and 'self': triggers emergency immediately.
  /// For 'people_injured' and 'bystander': only updates state — the screen
  /// navigates to /victims and calls [triggerEmergencyWithVictims] on return.
  void selectVictimType(String victimType) {
    final cur = state.valueOrNull;
    if (cur == null) return;

    state = AsyncData(cur.copyWith(victimType: victimType, currentStep: 2));

    if (victimType == 'vehicle_only' || victimType == 'self') {
      unawaited(_triggerEmergency());
    }
    // For people_injured / bystander: screen handles /victims navigation.
  }

  /// Called by the triage screen after /victims returns with data.
  Future<void> triggerEmergencyWithVictims({
    int? victimCount,
    List<VictimDetail>? victimDetails,
  }) async {
    await _triggerEmergency(
        victimCount: victimCount, victimDetails: victimDetails);
  }

  /// Clears the [readyForResults] navigation flag after the screen has acted.
  void clearResultsFlag() {
    final cur = state.valueOrNull;
    if (cur != null) {
      state = AsyncData(cur.copyWith(
        readyForResults: false,
        clearResultsExtra: true,
      ));
    }
  }

  // ── Core trigger ───────────────────────────────────────────────────────────

  Future<void> _triggerEmergency({
    int? victimCount,
    List<VictimDetail>? victimDetails,
  }) async {
    final cur = state.valueOrNull;
    if (cur == null) return;

    state = AsyncData(cur.copyWith(isSubmitting: true));

    // Fire background actions in parallel — each is independently error-handled.
    // NOTE: SMS is no longer triggered automatically here because launching 
    // the external SMS app interrupts the UI flow to the results/services page. 
    // Users can manually share their location from the results page.
    await Future.wait([
      _sendSilentPolicePing(cur),
      _startBackendSession(cur,
          victimCount: victimCount, victimDetails: victimDetails),
    ]);

    final updated = state.valueOrNull ?? cur;

    state = AsyncData(updated.copyWith(
      emergencyTriggered: true,
      isSubmitting: false,
      readyForResults: true,
      resultsExtra: {
        'emergencyType': updated.emergencyType,
        'victimType': updated.victimType ?? 'self',
        'sessionId': updated.sessionId,
        'position': updated.position,
        'victimCount': victimCount,
        'victimDetails': victimDetails ?? const <VictimDetail>[],
      },
    ));
  }

  // ── Parallel actions ───────────────────────────────────────────────────────

  /// Fire-and-forget police alert via EmergencyService.
  ///
  /// Creates the local SQLite session and starts the GPS ping timer.
  /// Never awaited — UI does not wait for this.
  Future<void> _sendSilentPolicePing(TriageState cur) async {
    try {
      final svc = ref.read(emergencyServiceProvider);
      final pos = cur.position;
      if (pos == null) {
        debugPrint('[TriageNotifier] Silent ping skipped — no position yet');
        return;
      }
      // Fire and forget — do not await
      unawaited(
        svc
            .startEmergency(
          position: pos,
          emergencyType: cur.emergencyType,
          victimType: cur.victimType ?? 'self',
          sessionId: cur.sessionId,
        )
            .then((_) {
          debugPrint('[TriageNotifier] Silent police ping sent ✓');
        }).catchError((e) {
          debugPrint('[TriageNotifier] Silent ping error (non-fatal): $e');
        }),
      );
    } catch (e) {
      debugPrint('[TriageNotifier] _sendSilentPolicePing error: $e');
    }
  }



  /// Registers the session with the backend.
  ///
  /// If the API returns a server-side session ID, it replaces the local UUID.
  /// Failure is swallowed — the local UUID is always used as fallback.
  /// Skipped entirely when only the emulator-localhost URL is configured.
  Future<void> _startBackendSession(
    TriageState cur, {
    int? victimCount,
    List<VictimDetail>? victimDetails,
  }) async {
    const _defaultUrl = 'http://10.0.2.2:8000';
    final apiUrl = AppConstants.apiBaseUrl;
    if (apiUrl.isEmpty || apiUrl == _defaultUrl) {
      debugPrint('[TriageNotifier] Backend session skipped (emulator URL)');
      return;
    }

    try {
      final pos = cur.position;
      final api = ref.read(apiClientProvider);
      final serverSessionId = await api.startEmergency(
        lat: pos?.latitude ?? 0.0,
        lng: pos?.longitude ?? 0.0,
        emergencyType: cur.emergencyType,
        victimType: cur.victimType ?? 'self',
        victimCount: victimCount,
        victimDetails: victimDetails,
      );
      if (serverSessionId != null && serverSessionId.isNotEmpty) {
        final updated = state.valueOrNull;
        if (updated != null) {
          state = AsyncData(updated.copyWith(sessionId: serverSessionId));
        }
        debugPrint('[TriageNotifier] Backend session ✓ id=$serverSessionId');
      }
    } catch (e) {
      debugPrint('[TriageNotifier] _startBackendSession error (using local): $e');
    }
  }
}
