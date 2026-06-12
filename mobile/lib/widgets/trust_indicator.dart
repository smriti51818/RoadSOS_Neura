// lib/widgets/trust_indicator.dart
// Module 5 — 5-dot trust score widget.
//
// Filled dots represent the trust level; hollow dots represent remaining.
// Color encoding:
//   1–2 dots → emergencyRed  (unverified)
//   3 dots   → warningAmber  (community verified)
//   4–5 dots → primaryGreen  (verified / govt-verified)

import 'package:flutter/material.dart';

import '../core/theme.dart';

class TrustIndicator extends StatelessWidget {
  const TrustIndicator({
    super.key,
    required this.score,
    this.size = 6.0,
    this.gap = 2.5,
  });

  /// Trust score 1–5.
  final int score;

  /// Dot diameter in logical pixels (default 6).
  final double size;

  /// Gap between dots in logical pixels (default 2.5).
  final double gap;

  Color get _color {
    final s = score.clamp(1, 5);
    if (s <= 2) return AppTheme.emergencyRed;
    if (s == 3) return AppTheme.warningAmber;
    return AppTheme.primaryGreen;
  }

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(1, 5);
    final color = _color;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < clamped;
        return Padding(
          padding: EdgeInsets.only(right: i < 4 ? gap : 0),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? color : color.withValues(alpha: 0.18),
            ),
          ),
        );
      }),
    );
  }
}
