// lib/features/non_emergency/non_emergency_screen.dart
// Module 5 — Dedicated non-emergency services screen.
//
// Navigation entry: home screen non-emergency grid cell → /non-emergency
// Navigation exit:  category card tap → /results with nonEmergencyCategory=X
//
// This screen is a selection hub — no live data fetching. The actual service
// lookup happens in ResultsNotifier after the user selects a category.
// Static NHAI/traffic helpline numbers are always shown at the bottom.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../widgets/offline_banner.dart';

class NonEmergencyScreen extends ConsumerWidget {
  const NonEmergencyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF0F172A),
                size: 18,
              ),
              padding: EdgeInsets.zero,
              onPressed: () => context.pop(),
            ),
          ),
        ),
        title: Text(
          'Non-Emergency Services',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background decorative glow blobs for a premium SaaS mesh feel
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.04), // soft blue glow
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.04), // soft green glow
                    blurRadius: 120,
                    spreadRadius: 60,
                  ),
                ],
              ),
            ),
          ),
          const SafeArea(
            child: _NonEmergencyBody(), // manages its own ScrollController + helpline key
          ),
        ],
      ),
    );
  }
}

// ── Body ───────────────────────────────────────────────────────────────────────

class _NonEmergencyBody extends StatefulWidget {
  const _NonEmergencyBody();

  @override
  State<_NonEmergencyBody> createState() => _NonEmergencyBodyState();
}

class _NonEmergencyBodyState extends State<_NonEmergencyBody> {
  final _scrollController = ScrollController();
  // Key on the National Helplines section — used by Road Helpline card to
  // scroll directly to it rather than navigating to the (empty) results screen.
  final _helplineKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHelplines() {
    final ctx = _helplineKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.0, // align top of section to top of viewport
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Animated offline banner — self-manages visibility
          const OfflineBanner(),

          // ── Vehicle services ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Text(
              'VEHICLE SERVICES',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF64748B),
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.25,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                const _CategoryCard(
                  category: 'towing',
                  label: 'Towing',
                  subtitle: 'Find tow trucks',
                  icon: Icons.car_repair_rounded,
                  color: Color(0xFF0891B2),
                  bgColor: Color(0xFFEFF9FF),
                  iconBg: Color(0xFFCCEEFF),
                ),
                const _CategoryCard(
                  category: 'breakdown',
                  label: 'Breakdown Help',
                  subtitle: 'On-road repair',
                  icon: Icons.build_rounded,
                  color: Color(0xFF16A34A),
                  bgColor: Color(0xFFEFFAF3),
                  iconBg: Color(0xFFBBF7D0),
                ),
                const _CategoryCard(
                  category: 'puncture',
                  label: 'Puncture Repair',
                  subtitle: 'Nearby tyre shops',
                  icon: Icons.tire_repair_rounded,
                  color: Color(0xFFF59E0B),
                  bgColor: Color(0xFFFFFBEB),
                  iconBg: Color(0xFFFDE68A),
                ),
                // Road Helpline scrolls to the static helplines section below
                // instead of navigating to the results screen (which has no
                // POI data for helplines — they are always static numbers).
                _CategoryCard(
                  category: 'helpline',
                  label: 'Road Helpline',
                  subtitle: 'NHAI & assistance',
                  icon: Icons.headset_mic_rounded,
                  color: const Color(0xFF7C3AED),
                  bgColor: const Color(0xFFF5F0FF),
                  iconBg: const Color(0xFFE0D5FF),
                  onTap: _scrollToHelplines,
                ),
              ],
            ),
          ),

          // ── National helplines (static, always available) ─────────────────
          // _helplineKey anchors this section so the Road Helpline card can
          // scroll here via Scrollable.ensureVisible.
          Padding(
            key: _helplineKey,
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
            child: Text(
              'NATIONAL HELPLINES',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF64748B),
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: AppTheme.premiumCardDecoration,
              clipBehavior: Clip.antiAlias,
              child: const Column(
                children: [
                  _HelplineRow(
                    label: 'NHAI Road Helpline',
                    number: '1033',
                    subtitle: 'Highways breakdown & accidents',
                    icon: Icons.add_road_rounded,
                    color: Color(0xFF16A34A),
                  ),
                  _Divider(),
                  _HelplineRow(
                    label: 'Traffic Police',
                    number: '103',
                    subtitle: 'Road accidents & traffic control',
                    icon: Icons.local_police_rounded,
                    color: Color(0xFF1D4ED8),
                  ),
                  _Divider(),
                  _HelplineRow(
                    label: 'Women Helpline',
                    number: '1091',
                    subtitle: 'Women in distress',
                    icon: Icons.shield_rounded,
                    color: Color(0xFF7C3AED),
                  ),
                  _Divider(),
                  _HelplineRow(
                    label: 'Disaster Management',
                    number: '108',
                    subtitle: 'Emergency response services',
                    icon: Icons.warning_amber_rounded,
                    color: Color(0xFFEA580C),
                  ),
                  _Divider(),
                  _HelplineRow(
                    label: 'Unified Emergency',
                    number: '112',
                    subtitle: 'All emergencies (police/fire/medical)',
                    icon: Icons.phone_in_talk_rounded,
                    color: Color(0xFFDC2626),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Category card ──────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.iconBg,
    this.onTap, // override: defaults to navigating to /results
  });

  final String category;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final Color iconBg;

  /// Optional tap handler. When null, navigates to /results with the category.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ??
          () => context.push(
                '/results',
                extra: {
                  'sessionId': '',
                  'emergencyType': 'non_emergency',
                  'victimType': 'none',
                  'nonEmergencyCategory': category,
                },
              ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          boxShadow: AppTheme.softShadows,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const Spacer(),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 12, color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpline row ───────────────────────────────────────────────────────────────

class _HelplineRow extends StatelessWidget {
  const _HelplineRow({
    required this.label,
    required this.number,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String label;
  final String number;
  final String subtitle;
  final IconData icon;
  final Color color;

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: number);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _call,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                number,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 68,
      endIndent: 0,
      color: AppTheme.borderColor,
    );
  }
}

