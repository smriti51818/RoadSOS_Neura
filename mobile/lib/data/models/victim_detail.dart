import 'package:flutter/foundation.dart';

/// Details of a single victim in a multi-victim emergency scenario.
@immutable
class VictimDetail {
  /// Age group: 'child_0_12' | 'teen_13_17' | 'adult_18_60' | 'senior_60_plus'
  final String ageGroup;

  /// Condition: 'conscious' | 'unconscious' | 'bleeding' | 'trapped'
  final String condition;

  /// Help needed: 'ambulance' | 'fire_rescue' | 'both'
  final String helpType;

  const VictimDetail({
    required this.ageGroup,
    required this.condition,
    required this.helpType,
  });

  /// Returns an empty/unset VictimDetail placeholder.
  factory VictimDetail.empty() => const VictimDetail(
        ageGroup: '',
        condition: '',
        helpType: '',
      );

  /// True when all three required fields have been filled in.
  bool get isComplete =>
      ageGroup.isNotEmpty && condition.isNotEmpty && helpType.isNotEmpty;

  factory VictimDetail.fromJson(Map<String, dynamic> json) {
    return VictimDetail(
      ageGroup: json['age_group'] as String? ?? 'adult_18_60',
      condition: json['condition'] as String? ?? 'conscious',
      helpType: json['help_type'] as String? ?? 'ambulance',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'age_group': ageGroup,
      'condition': condition,
      'help_type': helpType,
    };
  }

  /// Child under 13 → route to paediatric trauma unit.
  bool get needsPediatricUnit => ageGroup == 'child_0_12';

  /// Victim is trapped or needs fire rescue → alert fire brigade automatically.
  bool get needsFireRescue =>
      helpType == 'fire_rescue' ||
      helpType == 'both' ||
      condition == 'trapped';

  /// Senior citizen flag → send to dispatcher for priority handling.
  bool get isSenior => ageGroup == 'senior_60_plus';

  /// High-priority victim — requires immediate response.
  bool get isHighPriority =>
      condition == 'unconscious' || condition == 'trapped';

  String get ageGroupLabel {
    switch (ageGroup) {
      case 'child_0_12':
        return 'Child (0–12)';
      case 'teen_13_17':
        return 'Teen (13–17)';
      case 'adult_18_60':
        return 'Adult (18–60)';
      case 'senior_60_plus':
        return 'Senior (60+)';
      default:
        return ageGroup;
    }
  }

  String get conditionLabel {
    switch (condition) {
      case 'conscious':
        return 'Conscious';
      case 'unconscious':
        return 'Unconscious';
      case 'bleeding':
        return 'Bleeding';
      case 'trapped':
        return 'Trapped';
      default:
        return condition;
    }
  }

  String get helpTypeLabel {
    switch (helpType) {
      case 'ambulance':
        return 'Ambulance';
      case 'fire_rescue':
        return 'Fire Rescue';
      case 'both':
        return 'Ambulance + Fire Rescue';
      default:
        return helpType;
    }
  }
}
