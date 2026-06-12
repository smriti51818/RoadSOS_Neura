// lib/features/loading/loading_screen.dart
// Module 3 — Loading screen.
// Redesigned to Premium Light Theme with SaaS mesh blobs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import 'loading_provider.dart';

/// Premium light-background splash / loading screen shown on launch.
class LoadingScreen extends ConsumerWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Navigate once loading completes
    ref.listen<AsyncValue<LoadingState>>(
      loadingNotifierProvider,
      (_, next) {
        next.whenData((s) {
          if (!s.isComplete) return;
          LoadingNotifier.shouldShowOnboarding().then((showOnboarding) {
            if (!context.mounted) return;
            if (showOnboarding) {
              context.go('/onboarding');
            } else {
              context.go('/home');
            }
          });
        });
      },
    );

    final async = ref.watch(loadingNotifierProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Pure executive light slate background
      body: async.when(
        loading: () => _buildLoadingBody(context, LoadingState.initial()),
        error: (err, _) => _buildErrorBody(context, ref, err),
        data: (s) => _buildLoadingBody(context, s),
      ),
    );
  }

  // ── Main loading layout ────────────────────────────────────────────────────

  Widget _buildLoadingBody(BuildContext context, LoadingState s) {
    return Stack(
      fit: StackFit.expand,
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

        // Content
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 56),

                // ── Logo ─────────────────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF006B2C),
                              Color(0xFF10B981),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF006B2C).withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          size: 32,
                          color: Colors.white,
                          semanticLabel: 'RoadSoS shield',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'RoadSoS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Help in under 5 seconds · Works offline',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ── Emergency numbers card ───────────────────────────────────
                _EmergencyNumbersCard(numbers: s.emergencyNumbers),

                const SizedBox(height: 12),

                // ── Safety tip card ──────────────────────────────────────────
                _SafetyTipCard(tip: s.currentTip),

                const Spacer(),

                // ── Progress section ─────────────────────────────────────────
                Text(
                  s.statusMessage,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: s.progress,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Error layout ───────────────────────────────────────────────────────────

  Widget _buildErrorBody(BuildContext context, WidgetRef ref, Object err) {
    return Stack(
      fit: StackFit.expand,
      children: [
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
                  color: const Color(0xFFE11D48).withValues(alpha: 0.04), // soft red glow on error
                  blurRadius: 100,
                  spreadRadius: 50,
                ),
              ],
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.premiumCardDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFEE2E2), width: 1),
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      size: 28,
                      color: AppTheme.emergencyRed,
                      semanticLabel: 'Error',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Something went wrong',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    err.toString(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => ref.invalidate(loadingNotifierProvider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Retry',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Emergency numbers card ────────────────────────────────────────────────────

class _EmergencyNumbersCard extends StatelessWidget {
  const _EmergencyNumbersCard({required this.numbers});

  final Map<String, String> numbers;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.premiumCardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EMERGENCY NUMBERS',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF94A3B8),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _NumberTile(
                icon: Icons.local_police_outlined,
                label: 'Police',
                number: numbers['police'] ?? '100',
                color: AppTheme.policeBlue,
                bgColor: const Color(0xFFEFF6FF),
              ),
              _NumberTile(
                icon: Icons.emergency_outlined,
                label: 'Ambulance',
                number: numbers['ambulance'] ?? '108',
                color: AppTheme.emergencyRed,
                bgColor: const Color(0xFFFEF2F2),
              ),
              _NumberTile(
                icon: Icons.local_fire_department_outlined,
                label: 'Fire',
                number: numbers['fire'] ?? '101',
                color: const Color(0xFFEA580C),
                bgColor: const Color(0xFFFFF7ED),
              ),
              _NumberTile(
                icon: Icons.phone_outlined,
                label: 'Unified',
                number: numbers['unified'] ?? '112',
                color: AppTheme.primaryGreen,
                bgColor: const Color(0xFFF0FDF4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({
    required this.icon,
    required this.label,
    required this.number,
    required this.color,
    required this.bgColor,
  });

  final IconData icon;
  final String label;
  final String number;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                number,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Safety tip card ───────────────────────────────────────────────────────────

class _SafetyTipCard extends StatelessWidget {
  const _SafetyTipCard({required this.tip});

  final String tip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.premiumCardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7), // soft amber background
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              size: 18,
              color: Color(0xFFD97706),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SAFETY TIP',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFD97706),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    tip,
                    key: ValueKey<String>(tip),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF334155),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
