// File 7 of 12 — Module 4
// mobile/lib/features/victims/victims_provider.dart
//
// Drives the per-victim data collection screen.
// Auto-disposes when the screen is popped — fresh state on every push.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/models/victim_detail.dart';

part 'victims_provider.g.dart';

// ── State ──────────────────────────────────────────────────────────────────────

class VictimsState {
  const VictimsState({
    required this.totalVictims,
    required this.victims,
    required this.currentVictimIndex,
    required this.isComplete,
  });

  /// Total number of people needing help — 1 to 6.
  final int totalVictims;

  /// One [VictimDetail] per victim, length == [totalVictims].
  final List<VictimDetail> victims;

  /// Which victim the user is currently editing (0-based).
  final int currentVictimIndex;

  /// True once all victims have ageGroup, condition, and helpType filled.
  final bool isComplete;

  factory VictimsState.initial() => VictimsState(
        totalVictims: 1,
        victims: [VictimDetail.empty()],
        currentVictimIndex: 0,
        isComplete: false,
      );

  VictimsState copyWith({
    int? totalVictims,
    List<VictimDetail>? victims,
    int? currentVictimIndex,
    bool? isComplete,
  }) =>
      VictimsState(
        totalVictims: totalVictims ?? this.totalVictims,
        victims: victims ?? this.victims,
        currentVictimIndex: currentVictimIndex ?? this.currentVictimIndex,
        isComplete: isComplete ?? this.isComplete,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

@riverpod
class VictimsNotifier extends _$VictimsNotifier {
  @override
  Future<VictimsState> build() async {
    return VictimsState.initial();
  }

  // ── Public actions ─────────────────────────────────────────────────────────

  /// Sets the total victim count and adjusts the victims list accordingly.
  void setTotalVictims(int count) {
    final cur = state.valueOrNull ?? VictimsState.initial();
    final clamped = count.clamp(1, 6);
    final existing = cur.victims;

    final updated = List<VictimDetail>.generate(
      clamped,
      (i) => i < existing.length ? existing[i] : VictimDetail.empty(),
    );

    state = AsyncData(cur.copyWith(
      totalVictims: clamped,
      victims: updated,
      // Reset to first victim if count shrank past current index
      currentVictimIndex:
          cur.currentVictimIndex >= clamped ? 0 : cur.currentVictimIndex,
    ));
  }

  /// Updates a specific field on the victim at [index].
  void updateVictim({
    required int index,
    String? ageGroup,
    String? condition,
    String? helpType,
  }) {
    final cur = state.valueOrNull ?? VictimsState.initial();
    if (index < 0 || index >= cur.victims.length) return;

    final existing = cur.victims[index];
    final updated = VictimDetail(
      ageGroup: ageGroup ?? existing.ageGroup,
      condition: condition ?? existing.condition,
      helpType: helpType ?? existing.helpType,
    );

    final newList = List<VictimDetail>.from(cur.victims)..[index] = updated;
    state = AsyncData(cur.copyWith(victims: newList));
  }

  /// Advances to the next victim, or marks complete if on the last one.
  void nextVictim() {
    final cur = state.valueOrNull ?? VictimsState.initial();
    if (cur.currentVictimIndex < cur.totalVictims - 1) {
      state = AsyncData(cur.copyWith(
        currentVictimIndex: cur.currentVictimIndex + 1,
      ));
    } else {
      if (_allVictimsComplete(cur)) {
        state = AsyncData(cur.copyWith(isComplete: true));
      }
    }
  }

  // ── Computed helpers ───────────────────────────────────────────────────────

  bool get allVictimsComplete {
    final cur = state.valueOrNull;
    if (cur == null) return false;
    return _allVictimsComplete(cur);
  }

  /// Priority service categories computed from all victim details.
  List<String> get requiredCategories {
    final cur = state.valueOrNull;
    if (cur == null) return ['ambulance', 'police'];

    final cats = <String>{'ambulance', 'police'};

    for (final v in cur.victims) {
      if (v.needsFireRescue) cats.add('fire');
      if (v.needsPediatricUnit || v.isSenior) cats.add('hospital');
    }

    return cats.toList();
  }

  static bool _allVictimsComplete(VictimsState s) {
    return s.victims.isNotEmpty && s.victims.every((v) => v.isComplete);
  }
}
