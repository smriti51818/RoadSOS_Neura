import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

final voiceSosProvider = StateNotifierProvider<VoiceSosController, VoiceSosState>((ref) {
  return VoiceSosController();
});

class VoiceSosState {
  final bool isListening;
  final bool hasPermission;
  final String lastWords;
  final bool triggered;

  VoiceSosState({
    this.isListening = false,
    this.hasPermission = false,
    this.lastWords = '',
    this.triggered = false,
  });

  VoiceSosState copyWith({
    bool? isListening,
    bool? hasPermission,
    String? lastWords,
    bool? triggered,
  }) {
    return VoiceSosState(
      isListening: isListening ?? this.isListening,
      hasPermission: hasPermission ?? this.hasPermission,
      lastWords: lastWords ?? this.lastWords,
      triggered: triggered ?? this.triggered,
    );
  }
}

class VoiceSosController extends StateNotifier<VoiceSosState> {
  VoiceSosController() : super(VoiceSosState()) {
    _initSpeech();
  }

  final stt.SpeechToText _speechToText = stt.SpeechToText();
  
  static const List<String> triggerWords = ['help', 'emergency', 'accident', 'call ambulance', 'sos'];

  Future<void> _initSpeech() async {
    try {
      final hasPermission = await _speechToText.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            state = state.copyWith(isListening: false);
          }
        },
        onError: (errorNotification) {
          debugPrint('Speech error: ${errorNotification.errorMsg}');
          state = state.copyWith(isListening: false);
        },
      );
      state = state.copyWith(hasPermission: hasPermission);
    } catch (e) {
      debugPrint('Speech init error: $e');
    }
  }

  Future<void> toggleListening() async {
    if (!_speechToText.isAvailable) {
      await _initSpeech();
    }

    if (state.isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!state.hasPermission) return;
    
    state = state.copyWith(isListening: true, lastWords: '', triggered: false);
    await _speechToText.listen(
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        state = state.copyWith(lastWords: words);
        
        // Check for triggers
        for (final trigger in triggerWords) {
          if (words.contains(trigger)) {
            _triggerSos();
            break;
          }
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      listenMode: stt.ListenMode.dictation,
    );
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    state = state.copyWith(isListening: false);
  }

  void _triggerSos() async {
    if (state.triggered) return;
    
    await _stopListening();
    state = state.copyWith(triggered: true);
    // Let the UI handle the navigation when triggered becomes true
  }
}
