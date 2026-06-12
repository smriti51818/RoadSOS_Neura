// lib/widgets/service_card.dart
// Module 5 — Reusable service card.
//
// Displays a ServiceModel with:
//   • Category icon (color-coded)
//   • Name + distance + 24hr badge + trust indicator
//   • Optional address line
//   • Tap-to-call button when phonePrimary is available

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../data/models/service_model.dart';
import 'trust_indicator.dart';

class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.service,
    this.showTrust = true,
    this.showAddress = true,
  });

  final ServiceModel service;

  /// Whether to show the 5-dot trust indicator.
  final bool showTrust;

  /// Whether to show the address line when available.
  final bool showAddress;

  // ── Category helpers ───────────────────────────────────────────────────────

  static IconData _iconFor(String category) {
    switch (category) {
      case 'hospital':
        return Icons.local_hospital;
      case 'police':
        return Icons.local_police;
      case 'ambulance':
        return Icons.emergency;
      case 'fire':
        return Icons.local_fire_department;
      case 'towing':
      case 'breakdown':
        return Icons.car_repair;
      case 'puncture':
        return Icons.tire_repair;
      case 'helpline':
        return Icons.headset_mic;
      default:
        return Icons.place;
    }
  }

  static Color _colorFor(String category) {
    switch (category) {
      case 'hospital':
        return const Color(0xFF7C3AED);
      case 'police':
        return AppTheme.policeBlue;
      case 'ambulance':
        return AppTheme.emergencyRed;
      case 'fire':
        return const Color(0xFFEA580C);
      case 'towing':
      case 'breakdown':
        return const Color(0xFF0891B2);
      case 'puncture':
        return AppTheme.warningAmber;
      case 'helpline':
        return const Color(0xFF7C3AED);
      default:
        return AppTheme.primaryGreen;
    }
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(service.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Category icon ──────────────────────────────────────────────────
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child:
                Icon(_iconFor(service.category), size: 20, color: color),
          ),
          const SizedBox(width: 12),

          // ── Name + meta ────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name.isEmpty ? 'Unnamed' : service.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    // Distance
                    if (service.distanceKm != null) ...[
                      const Icon(Icons.near_me,
                          size: 10, color: AppTheme.textSecondary),
                      const SizedBox(width: 2),
                      Text(
                        service.formattedDistance,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: AppTheme.primaryGreen,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    // 24hr badge
                    if (service.is24hr)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '24hr',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: AppTheme.primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    // Trust indicator
                    if (showTrust && service.trustScore > 0) ...[
                      const SizedBox(width: 6),
                      TrustIndicator(score: service.trustScore, size: 5),
                    ],
                  ],
                ),
                // Address
                if (showAddress &&
                    service.address != null &&
                    service.address!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    service.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Call button ────────────────────────────────────────────────────
          if (service.phonePrimary != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _call(service.phonePrimary!),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.phone,
                  size: 16,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
