// File 1 of 12 — Module 3
// mobile/lib/features/loading/loading_provider.dart
//
// Drives the sequential loading sequence shown on app launch:
//   1. Load emergency numbers from bundled asset JSON
//   2. Request GPS permission and detect country
//   3. Parse country_config.json into Riverpod state
//   4. Parse decision_trees.json for offline AI
//   5. Check connectivity / backend reachability
//   6. Mark complete → trigger navigation

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../data/models/country_config.dart';
import '../../data/remote/api_client.dart';
import '../../services/location_service.dart';

part 'loading_provider.g.dart';

// ── Safety tips ───────────────────────────────────────────────────────────────

const List<String> _kTips = [
  'Keep a first aid kit and reflective triangle in your vehicle',
  'Save 112, 108 and 100 as speed dial on your phone right now',
  'Always note the milestone number on highways',
  'Turn on hazard lights immediately after any accident',
  'Never move an injured person unless there is fire risk',
  'Keep a portable charger in your car at all times',
  'Note your blood group on a card in your wallet',
  'Reduce speed by 30 percent in rain',
  'Check tyre pressure before long highway drives',
  'Pull over if you feel sleepy — never drive drowsy',
];

// ── State ──────────────────────────────────────────────────────────────────────

/// Immutable snapshot of everything the loading screen needs to render.
class LoadingState {
  const LoadingState({
    required this.isComplete,
    required this.statusMessage,
    required this.progress,
    required this.currentTip,
    required this.emergencyNumbers,
    required this.detectedCountry,
    required this.locationDetected,
  });

  final bool isComplete;

  /// Short status line shown below the progress bar.
  final String statusMessage;

  /// 0.0 → 1.0 — drives the LinearProgressIndicator value.
  final double progress;

  /// Current rotating safety tip shown in the tip card.
  final String currentTip;

  /// Emergency numbers for the detected country — available before GPS loads
  /// because they come from a bundled asset, not the API.
  final Map<String, String> emergencyNumbers;

  /// ISO 3166-1 alpha-2 country code resolved from GPS. Defaults to 'IN'.
  final String detectedCountry;

  /// True once GPS permission was granted and a position was obtained.
  final bool locationDetected;

  factory LoadingState.initial() => const LoadingState(
        isComplete: false,
        statusMessage: 'Preparing RoadSoS…',
        progress: 0.0,
        currentTip: 'Keep a first aid kit and reflective triangle in your vehicle',
        emergencyNumbers: {
          'police': '100',
          'ambulance': '108',
          'fire': '101',
          'unified': '112',
        },
        detectedCountry: 'IN',
        locationDetected: false,
      );

  LoadingState copyWith({
    bool? isComplete,
    String? statusMessage,
    double? progress,
    String? currentTip,
    Map<String, String>? emergencyNumbers,
    String? detectedCountry,
    bool? locationDetected,
  }) =>
      LoadingState(
        isComplete: isComplete ?? this.isComplete,
        statusMessage: statusMessage ?? this.statusMessage,
        progress: progress ?? this.progress,
        currentTip: currentTip ?? this.currentTip,
        emergencyNumbers: emergencyNumbers ?? this.emergencyNumbers,
        detectedCountry: detectedCountry ?? this.detectedCountry,
        locationDetected: locationDetected ?? this.locationDetected,
      );
}

// ── Companion providers ────────────────────────────────────────────────────────

/// Emergency numbers for the user's detected country.
/// Written by [LoadingNotifier]; read by the whole app.
final emergencyNumbersProvider = StateProvider<Map<String, String>>(
  (ref) => const {
    'police': '100',
    'ambulance': '108',
    'fire': '101',
    'unified': '112',
  },
);

/// Country configuration map keyed by ISO code.
final countryConfigProvider = StateProvider<Map<String, CountryConfig>>(
  (ref) => const {},
);

/// Full decision-trees JSON used by the offline AI assistant.
final decisionTreesProvider = StateProvider<Map<String, dynamic>>(
  (ref) => const {},
);

/// Detected ISO country code — defaults to 'IN' until GPS resolves.
final detectedCountryProvider = StateProvider<String>((ref) => 'IN');

// ── Notifier ──────────────────────────────────────────────────────────────────

/// Drives the 6-step loading sequence.
///
/// Auto-disposes once the loading screen is popped — the companion
/// [StateProvider]s above survive the navigation.
@riverpod
class LoadingNotifier extends _$LoadingNotifier {
  Timer? _tipTimer;
  int _tipIndex = 0;

  @override
  Future<LoadingState> build() async {
    ref.onDispose(() => _tipTimer?.cancel());

    // Show something immediately so the screen isn't blank.
    state = AsyncData(LoadingState.initial());

    _startTipRotation();
    await _runLoadingSequence();

    return state.valueOrNull ?? LoadingState.initial();
  }

  // ── Public helper ──────────────────────────────────────────────────────────

  /// Returns true if the onboarding flow has never been completed.
  static Future<bool> shouldShowOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool('onboarding_complete') ?? false);
    } catch (_) {
      return false;
    }
  }

  // ── Loading sequence ───────────────────────────────────────────────────────

  Future<void> _runLoadingSequence() async {
    await _step1LoadEmergencyNumbers();
    await _step2DetectLocation();
    await _step3LoadCountryConfig();
    await _step4LoadDecisionTrees();
    await _step5CheckConnectivity();
    await _step6Complete();
  }

  /// Step 1 — Loads emergency_numbers.json from Flutter assets.
  ///
  /// This runs BEFORE GPS so the user always sees a valid emergency number
  /// even if location permission is denied.
  Future<void> _step1LoadEmergencyNumbers() async {
    _patch(statusMessage: 'Loading emergency contacts…', progress: 0.1);
    try {
      final raw = await rootBundle.loadString(
        'assets/data/emergency_numbers.json',
      );
      final list = jsonDecode(raw) as List<dynamic>;
      final country = state.valueOrNull?.detectedCountry ?? 'IN';
      final numbers = _extractForCountry(list, country);
      _patch(emergencyNumbers: numbers);
      ref.read(emergencyNumbersProvider.notifier).state = numbers;
    } catch (e) {
      debugPrint('[LoadingNotifier] emergency_numbers.json error: $e');
      // App continues with hardcoded India defaults.
    }
  }

  /// Step 2 — Requests GPS permission and detects country.
  Future<void> _step2DetectLocation() async {
    _patch(statusMessage: 'Detecting your location…', progress: 0.3);
    try {
      final svc = ref.read(locationServiceProvider);
      final granted = await svc.requestPermission();
      if (!granted) return;

      final pos = await svc.getCurrentLocation();
      if (pos == null) return;

      final code = await svc.getCountryCode(pos);
      _patch(detectedCountry: code, locationDetected: true);
      ref.read(detectedCountryProvider.notifier).state = code;

      // Reload numbers for the newly detected country.
      await _reloadNumbersForCountry(code);
    } catch (e) {
      debugPrint('[LoadingNotifier] location detection error: $e');
    }
  }

  /// Step 3 — Parses country_config.json.
  Future<void> _step3LoadCountryConfig() async {
    _patch(statusMessage: 'Loading country configuration…', progress: 0.5);
    try {
      final raw = await rootBundle.loadString(
        'assets/data/country_config.json',
      );
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final configs = map.map(
        (k, v) => MapEntry(
          k,
          CountryConfig.fromJson({
            'country_code': k,
            ...(v as Map<String, dynamic>),
          }),
        ),
      );
      ref.read(countryConfigProvider.notifier).state = configs;
    } catch (e) {
      debugPrint('[LoadingNotifier] country_config.json error: $e');
    }
  }

  /// Step 4 — Parses decision_trees.json for the offline AI assistant.
  Future<void> _step4LoadDecisionTrees() async {
    _patch(statusMessage: 'Preparing offline safety guide…', progress: 0.7);
    try {
      final raw = await rootBundle.loadString(
        'assets/data/decision_trees.json',
      );
      final trees = jsonDecode(raw) as Map<String, dynamic>;
      ref.read(decisionTreesProvider.notifier).state = trees;
    } catch (e) {
      debugPrint('[LoadingNotifier] decision_trees.json error: $e');
    }
  }

  /// Step 5 — Probes connectivity and optionally the backend.
  Future<void> _step5CheckConnectivity() async {
    _patch(statusMessage: 'Checking connectivity…', progress: 0.9);
    try {
      final result = await Connectivity().checkConnectivity();
      // connectivity_plus v5+ returns List<ConnectivityResult>
      final isOnline = result.any((r) => r != ConnectivityResult.none);
      if (!isOnline) {
        _patch(statusMessage: 'Offline mode — local data ready');
        return;
      }
      // Light backend probe — skipped when no real backend is configured.
      const _defaultUrl = 'http://10.0.2.2:8000';
      final apiUrl = AppConstants.apiBaseUrl;
      if (apiUrl.isNotEmpty && apiUrl != _defaultUrl) {
        await ref.read(apiClientProvider).getEmergencyNumbers('IN');
      }
    } catch (_) {
      // Network unavailable — app continues in offline mode.
    }
  }

  /// Step 6 — Marks loading complete after a brief pause.
  Future<void> _step6Complete() async {
    _patch(statusMessage: 'RoadSoS ready!', progress: 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _tipTimer?.cancel();
    _patch(isComplete: true);
  }

  // ── Tip rotation ───────────────────────────────────────────────────────────

  void _startTipRotation() {
    _tipTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) {
        _tipIndex = (_tipIndex + 1) % _kTips.length;
        _patch(currentTip: _kTips[_tipIndex]);
      },
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Immutably patches [state] with the supplied fields.
  void _patch({
    bool? isComplete,
    String? statusMessage,
    double? progress,
    String? currentTip,
    Map<String, String>? emergencyNumbers,
    String? detectedCountry,
    bool? locationDetected,
  }) {
    final cur = state.valueOrNull ?? LoadingState.initial();
    state = AsyncData(cur.copyWith(
      isComplete: isComplete,
      statusMessage: statusMessage,
      progress: progress,
      currentTip: currentTip,
      emergencyNumbers: emergencyNumbers,
      detectedCountry: detectedCountry,
      locationDetected: locationDetected,
    ));
  }

  Future<void> _reloadNumbersForCountry(String code) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/emergency_numbers.json',
      );
      final list = jsonDecode(raw) as List<dynamic>;
      final numbers = _extractForCountry(list, code);
      _patch(emergencyNumbers: numbers);
      ref.read(emergencyNumbersProvider.notifier).state = numbers;
    } catch (_) {}
  }

  Map<String, String> _extractForCountry(
    List<dynamic> entries,
    String code,
  ) {
    for (final entry in entries) {
      if ((entry as Map<String, dynamic>)['country_code'] == code) {
        return {
          if (entry['police'] != null) 'police': entry['police'].toString(),
          if (entry['ambulance'] != null)
            'ambulance': entry['ambulance'].toString(),
          if (entry['fire'] != null) 'fire': entry['fire'].toString(),
          if (entry['unified'] != null) 'unified': entry['unified'].toString(),
        };
      }
    }
    // Fallback — India hardcoded per spec (safety constraint).
    return const {
      'police': '100',
      'ambulance': '108',
      'fire': '101',
      'unified': '112',
    };
  }
}
