// lib/widgets/battery_warning_banner.dart
// Module 5 — Standalone battery warning banner.
//
// Extracted from home_screen.dart for reuse across screens.
// Shown when batteryLevel < AppConfig.lowBatteryThreshold (20%).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

class BatteryWarningBanner extends StatelessWidget {
  const BatteryWarningBanner({super.key, this.level});

  /// Battery level 0.0–1.0. Shows percentage when non-null.
  final double? level;

  @override
  Widget build(BuildContext context) {
    final pct = level != null ? ' (${(level! * 100).round()}%)' : '';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.emergencyRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppTheme.emergencyRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.battery_alert,
            size: 16,
            color: AppTheme.emergencyRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Battery low$pct — Save emergency numbers offline.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.emergencyRed,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
