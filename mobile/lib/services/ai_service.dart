// lib/services/ai_service.dart
// Module 6 — AI guidance service.
//
// 7-layer safety system:
//   1. System prompt restricts topic to road safety only
//   2. Temperature 0.1 — deterministic, no hallucinations
//   3. _validateResponse() rejects forbidden medical/legal content
//   4. Safety filters in Gemini API config (BLOCK_LOW_AND_ABOVE)
//   5. Falls back to offline decision tree on any validation failure
//   6. Source badge tells user which layer answered
//   7. Disclaimer shown under every AI message
//
// Self-referential @riverpod notifier: build() returns this so callers can
// use ref.read(aiServiceProvider.notifier) to invoke methods.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/constants.dart';
import 'offline_service.dart';

part 'ai_service.g.dart';

// ── Models ─────────────────────────────────────────────────────────────────────

enum AiSource { gemini, offline }

class AiResponse {
  const AiResponse({
    required this.text,
    required this.source,
    required this.isOnline,
    this.scenario,
  });

  final String text;
  final AiSource source;
  final bool isOnline;

  /// Matched scenario key from decision tree (e.g. 'breakdown').
  final String? scenario;

  bool get isOfflineFallback => source == AiSource.offline;

  String get sourceLabel {
    if (source == AiSource.gemini) return 'AI guidance — verify with operator';
    return '⚠️ Device is offline — Rule-based protocol';
  }

  Color get sourceBadgeColor {
    if (source == AiSource.gemini) return const Color(0xFF1E3A5F);
    return const Color(0xFF451A03); // Amber dark
  }

  Color get sourceBadgeBorderColor {
    if (source == AiSource.gemini) return const Color(0xFF1D4ED8);
    return const Color(0xFFD97706); // Amber border
  }

  Color get sourceLabelColor {
    if (source == AiSource.gemini) return const Color(0xFF93C5FD);
    return const Color(0xFFFCD34D); // Amber text
  }
}

// ── Service ────────────────────────────────────────────────────────────────────

@riverpod
class AiService extends _$AiService {
  @override
  AiService build() => this;

  // ── Constants ────────────────────────────────────────────────────────────────

  static const String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/'
      'models/gemini-1.5-flash:generateContent';

  static const String _systemPrompt = '''
You are RoadSoS Emergency Assistant helping people at road accidents in India.

YOUR ONLY ALLOWED OUTPUTS:
1. Which emergency number to call right now
2. Immediate safety steps (maximum 5 steps)
3. Which service to contact (ambulance/police/fire)

YOU MUST NEVER:
- Diagnose medical conditions
- Prescribe any medication or dosage
- Give legal advice about fault or liability
- Respond to anything unrelated to road safety
- Make up statistics or emergency numbers
- Say it is safe to move an injured person

IF UNSURE: Always say exactly:
"Call 112 immediately and follow operator instructions."

FIRST AID: Follow Indian Red Cross guidelines only.

RESPONSE FORMAT — use exactly this structure:
IMMEDIATE: [one sentence, most urgent action]
STEPS:
1. [action]
2. [action]
3. [action]
CALL: [number] — [service name]
NOTE: [one safety caveat if needed]

Maximum 5 steps. Never exceed this format.
''';

  static const Map<String, List<String>> _keywords = {
    'breakdown': [
      'tyre', 'burst', 'engine', 'fuel', 'stuck',
      'breakdown', 'flat', 'smoke', 'battery', 'stalled',
      'puncture', 'overheating', 'wont start',
    ],
    'accident_injury': [
      'accident', 'crash', 'collision', 'injured', 'hurt',
      'bleeding', 'unconscious', 'hit', 'fell', 'knocked',
      'died', 'serious', 'head injury',
    ],
    'fire': [
      'fire', 'burning', 'smoke', 'flame',
      'explosion', 'petrol', 'diesel',
    ],
    'unsafe_threat': [
      'unsafe', 'threat', 'scared', 'followed',
      'danger', 'suspicious', 'alone', 'harassed',
      'stalked', 'night',
    ],
    'medical_emergency': [
      'heart', 'chest pain', 'breathing', 'seizure',
      'diabetic', 'stroke', 'faint', 'collapse',
      'not breathing', 'pulse', 'pregnant',
    ],
  };

  // ── Online AI ────────────────────────────────────────────────────────────────

  /// Fetches AI guidance from Gemini Flash.
  ///
  /// Falls back to [getGuidanceOffline] on API failure, validation failure,
  /// or missing API key.
  Future<AiResponse> getGuidanceOnline({
    required String userMessage,
    required String countryCode,
    List<Map<String, String>> history = const [],
  }) async {
    final apiKey = AppConstants.geminiApiKey;
    if (apiKey.isEmpty) {
      debugPrint('[AiService] No Gemini key — falling back to offline');
      return getGuidanceOffline(userMessage);
    }

    // Explicitly check network status first
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      bool isOffline = false;
      if (connectivityResult is List) {
        isOffline = (connectivityResult as List).contains(ConnectivityResult.none) && (connectivityResult as List).length == 1;
      } else {
        isOffline = connectivityResult == ConnectivityResult.none;
      }

      if (isOffline) {
        debugPrint('[AiService] Explicitly offline — skipping Gemini call');
        return getGuidanceOffline(userMessage);
      }
    } catch (e) {
      debugPrint('[AiService] Connectivity check failed: $e');
    }

    // Use only last 4 messages for context
    final contextMessages = history.length > 4
        ? history.sublist(history.length - 4)
        : history;
    final contents = [
      ...contextMessages.map((m) => {
            'role': m['role'] == 'user' ? 'user' : 'model',
            'parts': [
              {'text': m['content']}
            ],
          }),
      {
        'role': 'user',
        'parts': [
          {'text': userMessage}
        ],
      },
    ];

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': _systemPrompt}
        ],
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.1,
        'topP': 0.8,
        'topK': 20,
        'maxOutputTokens': 300,
        'candidateCount': 1,
      },
      'safetySettings': [
        {
          'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
          'threshold': 'BLOCK_LOW_AND_ABOVE',
        },
        {
          'category': 'HARM_CATEGORY_HARASSMENT',
          'threshold': 'BLOCK_LOW_AND_ABOVE',
        },
      ],
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_geminiEndpoint?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          final text = (candidates.first as Map<String, dynamic>)['content']
                  ?['parts']?[0]?['text'] as String? ??
              '';

          final validated = _validateResponse(text);
          if (validated != null) {
            debugPrint('[AiService] Gemini responded ✓');
            return AiResponse(
              text: validated,
              source: AiSource.gemini,
              isOnline: true,
            );
          }
          debugPrint('[AiService] Gemini response failed validation — offline');
        }
      } else {
        debugPrint('[AiService] Gemini HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[AiService] Gemini error: $e');
    }

    return getGuidanceOffline(userMessage);
  }

  // ── Proactive AI ─────────────────────────────────────────────────────────────

  /// Generates proactive first-aid guidance based on triage selections.
  Future<AiResponse> generateFirstAidGuidance(
    String incidentType,
    List<String> victimDetails,
  ) async {
    final details = victimDetails.isEmpty ? 'Unknown' : victimDetails.join(', ');
    final prompt = '''
Emergency Incident: $incidentType
Victim details: $details

Provide immediate first-aid steps for this specific scenario.
Remember to follow the system prompt formatting strictly.
''';

    return getGuidanceOnline(
      userMessage: prompt,
      countryCode: 'IN',
      history: [],
    );
  }

  // ── Response validator ───────────────────────────────────────────────────────

  /// Returns the response if safe, null if it contains forbidden content.
  String? _validateResponse(String response) {
    if (response.trim().isEmpty) return null;

    final forbidden = [
      RegExp(r'\b\d+\s*mg\b', caseSensitive: false),
      RegExp(r'\b\d+\s*ml\b', caseSensitive: false),
      RegExp(r'diagnos', caseSensitive: false),
      RegExp(r'take \w+ tablet', caseSensitive: false),
      RegExp(r'it is safe to move', caseSensitive: false),
      RegExp(r'no need to call', caseSensitive: false),
      RegExp(r'not serious', caseSensitive: false),
    ];

    for (final pattern in forbidden) {
      if (pattern.hasMatch(response)) {
        debugPrint('[AiService] Forbidden pattern found: ${pattern.pattern}');
        return null;
      }
    }

    // Must mention an emergency number
    final hasNumber =
        RegExp(r'(112|108|100|101|1033|999|911)').hasMatch(response);
    if (!hasNumber) {
      debugPrint('[AiService] No emergency number in response');
      return null;
    }

    // Length guard
    if (response.length > 800) {
      return '${response.substring(0, 797)}...';
    }

    return response;
  }

  // ── Offline decision tree ────────────────────────────────────────────────────

  /// Returns guidance from the bundled decision tree — works with no network.
  Future<AiResponse> getGuidanceOffline(String userInput) async {
    final trees = await ref.read(offlineServiceProvider).getDecisionTrees();

    if (trees.isEmpty) {
      return AiResponse(
        text: _buildFallbackResponse(),
        source: AiSource.offline,
        isOnline: false,
      );
    }

    // Keyword matching to find the best scenario
    final input = userInput.toLowerCase();
    String matchedScenario = 'unknown';
    int maxMatches = 0;

    for (final entry in _keywords.entries) {
      final matches =
          entry.value.where((kw) => input.contains(kw)).length;
      if (matches > maxMatches) {
        maxMatches = matches;
        matchedScenario = entry.key;
      }
    }

    final scenario =
        (trees[matchedScenario] ?? trees['unknown'] ?? {}) as Map;
    final steps =
        ((scenario['steps'] as List?)?.cast<String>()) ?? <String>[];
    final callFirst = scenario['call_first'] as String? ?? '112';

    final buffer = StringBuffer();
    buffer.writeln('IMMEDIATE: Call $callFirst now.');
    buffer.writeln('STEPS:');
    for (var i = 0; i < steps.length; i++) {
      buffer.writeln('${i + 1}. ${steps[i]}');
    }
    buffer.writeln('CALL: $callFirst');

    debugPrint(
        '[AiService] Offline response — scenario: $matchedScenario');

    return AiResponse(
      text: buffer.toString().trim(),
      source: AiSource.offline,
      isOnline: false,
      scenario: matchedScenario,
    );
  }

  String _buildFallbackResponse() {
    return '''IMMEDIATE: Call 112 now.
STEPS:
1. Turn on hazard lights if in a vehicle
2. Move to a safe location away from traffic
3. Call 112 — unified emergency, works everywhere
4. Share your location with someone you trust
CALL: 112 — Unified Emergency''';
  }

  // ── Quick replies ────────────────────────────────────────────────────────────

  /// Returns contextual quick-reply chips based on [lastScenario].
  List<String> getQuickReplies(String? lastScenario) {
    final defaults = [
      'Someone is injured',
      'My vehicle broke down',
      'I feel unsafe here',
      'What should I do first?',
    ];

    switch (lastScenario) {
      case 'accident_injury':
        return [...defaults, 'How do I help until ambulance arrives?'];
      case 'breakdown':
        return [...defaults, 'I need a tow truck'];
      case 'unsafe_threat':
        return [...defaults, 'I am being followed'];
      case 'fire':
        return [...defaults, 'There is smoke from my engine'];
      default:
        return defaults;
    }
  }
}
