import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/models/service_model.dart';
import '../../widgets/battery_warning_banner.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/helpline_sheet.dart';
import '../../widgets/offline_banner.dart';
import '../safety/safety_provider.dart';
import 'home_provider.dart';
import 'voice_sos_controller.dart';

// ── Root Home Screen ──────────────────────────────────────────────────────────

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeNotifierProvider);

    // Watch Voice SOS trigger to navigate in real-time
    ref.listen<VoiceSosState>(voiceSosProvider, (previous, next) {
      if (next.triggered && !(previous?.triggered ?? false)) {
        context.push('/triage', extra: {'emergencyType': 'accident'});
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Pure executive light slate background
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
          // Actual body content
          async.when(
            loading: () => _HomeBody(state: HomeState.initial(), ref: ref),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (state) => _HomeBody(state: state, ref: ref),
          ),
          // Floating Bottom Navigation Bar aligned to the bottom (floats over body)
          const Align(
            alignment: Alignment.bottomCenter,
            child: FloatingBottomNav(activeTab: BottomTab.home),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.state, required this.ref});

  final HomeState state;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: Opacity(
              opacity: value,
              child: child,
            ),
          );
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _Header(state: state, ref: ref),
            ),
            if (state.showBatteryWarning)
              SliverToBoxAdapter(
                child: BatteryWarningBanner(level: state.batteryLevel),
              ),
            const SliverToBoxAdapter(child: OfflineBanner()),
            SliverToBoxAdapter(
              child: _SlidingModeToggle(state: state, ref: ref),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: state.mode == HomeMode.emergency
                    ? _EmergencyGrid(state: state)
                    : _NonEmergencyGrid(state: state),
              ),
            ),
            SliverToBoxAdapter(
              child: _DispatchRadar(state: state),
            ),
            const SliverToBoxAdapter(
              child: _QuickDial(),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)), // Space for floating glass navbar
          ],
        ),
      ),
    );
  }
}

// ── Header Components ────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.ref});

  final HomeState state;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final safetyState = ref.watch(safetyNotifierProvider);
    final isSafetyOn = safetyState.isSafetyActive;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Section 1: Logo & Security Controls
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RoadSoS',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Row(
                    children: [
                      const _VoiceSosMicrophone(),
                      const SizedBox(width: 8),
                      // Simplified safety button / switch
                      GestureDetector(
                        onTap: () {
                          if (isSafetyOn) {
                            ref.read(safetyNotifierProvider.notifier).deactivateSafetyMode();
                          } else {
                            ref.read(safetyNotifierProvider.notifier).activateSafetyMode();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSafetyOn
                                ? const Color(0xFFECFDF5) // soft green tint
                                : const Color(0xFFF1F5F9), // slate-100
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSafetyOn
                                  ? const Color(0xFFA7F3D0)
                                  : const Color(0xFFE2E8F0),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PulsingStatusDot(
                                color: isSafetyOn
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF94A3B8),
                                size: 6,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isSafetyOn ? 'Shield Active' : 'Shield Off',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isSafetyOn
                                      ? const Color(0xFF065F46)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            // Section 2: Live Location & Battery Status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _LocationChip(state: state),
                  _BatteryIndicator(level: state.batteryLevel),
                ],
              ),
            ),
            // Section 3: Telemetry Status bar
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC), // Slate 50
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.satellite_alt_outlined, size: 12, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        'GPS Lock: 4m accuracy  •  Delay: ~2.4s',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const _PulsingStatusDot(color: Color(0xFF10B981), size: 5),
                      const SizedBox(width: 6),
                      Text(
                        'ONLINE',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF10B981),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationChip extends ConsumerStatefulWidget {
  final HomeState state;
  const _LocationChip({required this.state});

  @override
  ConsumerState<_LocationChip> createState() => _LocationChipState();
}

class _LocationChipState extends ConsumerState<_LocationChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _animController.repeat();
    try {
      await ref.read(homeNotifierProvider.notifier).refreshLocation();
    } finally {
      if (mounted) {
        _animController.stop();
        _animController.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRefreshing = widget.state.isLoadingServices;
    if (isRefreshing && !_animController.isAnimating) {
      _animController.repeat();
    } else if (!isRefreshing && _animController.isAnimating) {
      _animController.stop();
      _animController.reset();
    }

    return GestureDetector(
      onTap: _refresh,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF), // soft blue background
              shape: BoxShape.circle,
            ),
            child: RotationTransition(
              turns: _animController,
              child: const Icon(
                Icons.my_location_rounded,
                size: 16,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MONITORED ZONE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.state.locationLabel,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BatteryIndicator extends StatelessWidget {
  final double? level;
  const _BatteryIndicator({this.level});

  @override
  Widget build(BuildContext context) {
    if (level == null) return const SizedBox.shrink();
    final pct = (level! * 100).round();
    final isLow = level! < 0.2;

    Color color = const Color(0xFF10B981); // Active Green
    Color bgColor = const Color(0xFFF0FDF4); // soft green background
    IconData icon = Icons.battery_std_outlined;
    if (isLow) {
      color = AppTheme.emergencyRed;
      bgColor = const Color(0xFFFEF2F2); // Red-50
      icon = Icons.battery_alert_outlined;
    } else if (level! < 0.5) {
      color = AppTheme.warningAmber;
      bgColor = const Color(0xFFFFFBEB); // Amber-50
      icon = Icons.battery_3_bar_outlined;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'POWER SYSTEM',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF94A3B8),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$pct%',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Voice SOS Indicator Widget ───────────────────────────────────────────────

class _VoiceSosMicrophone extends ConsumerWidget {
  const _VoiceSosMicrophone();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceSos = ref.watch(voiceSosProvider);
    final isListening = voiceSos.isListening;

    return GestureDetector(
      onTap: () => ref.read(voiceSosProvider.notifier).toggleListening(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isListening
              ? const Color(0xFFFEF2F2) // very light red
              : const Color(0xFFF1F5F9), // slate-100
          shape: BoxShape.circle,
          border: Border.all(
            color: isListening
                ? const Color(0xFFFEE2E2)
                : const Color(0xFFE2E8F0),
            width: 1.0,
          ),
          boxShadow: isListening
              ? [
                  BoxShadow(
                    color: AppTheme.emergencyRed.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                isListening ? Icons.mic_outlined : Icons.mic_none_outlined,
                size: 18,
                color: isListening ? AppTheme.emergencyRed : const Color(0xFF475569),
              ),
              if (isListening)
                const Positioned(
                  top: 2,
                  right: 2,
                  child: _PulsingStatusDot(color: AppTheme.emergencyRed, size: 4),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mode Toggle ───────────────────────────────────────────────────────────────

class _SlidingModeToggle extends StatelessWidget {
  final HomeState state;
  final WidgetRef ref;
  const _SlidingModeToggle({required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isEmergency = state.mode == HomeMode.emergency;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9), // Sleek Slate-100 background
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        ),
        child: Stack(
          children: [
            // Sliding active background pill: a clean white card with a tactile gradient & subtle shadow
            AnimatedAlign(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              alignment: isEmergency ? Alignment.centerLeft : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        Color(0xFFF8FAFC),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                        blurRadius: 5,
                        offset: const Offset(0, 2.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Text/Icon buttons overlay centered vertically
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => ref
                          .read(homeNotifierProvider.notifier)
                          .toggleMode(HomeMode.emergency),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bolt_outlined,
                              size: 16,
                              color: isEmergency ? const Color(0xFFE11D48) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Emergency Help',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isEmergency ? const Color(0xFFE11D48) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => ref
                          .read(homeNotifierProvider.notifier)
                          .toggleMode(HomeMode.nonEmergency),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.construction_outlined,
                              size: 16,
                              color: !isEmergency ? const Color(0xFF0F766E) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Roadside Services',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: !isEmergency ? const Color(0xFF0F766E) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grids ─────────────────────────────────────────────────────────────────────

class _EmergencyGrid extends StatelessWidget {
  const _EmergencyGrid({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SELECT CRISIS SERVICE',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF64748B),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.08,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: const [
            _GridCell(
              typeKey: 'accident',
              label: 'Accident & Injury',
              description: 'Vehicle collision, trauma',
              icon: Icons.car_crash_outlined,
              iconColor: AppTheme.emergencyRed,
            ),
            _GridCell(
              typeKey: 'fire',
              label: 'Fire on Road',
              description: 'Vehicle fires, spills, hazards',
              icon: Icons.local_fire_department_outlined,
              iconColor: Color(0xFFEA580C),
            ),
            _GridCell(
              typeKey: 'medical',
              label: 'Medical Emergency',
              description: 'Cardiac, breathing distress',
              icon: Icons.monitor_heart_outlined,
              iconColor: Color(0xFF2563EB),
            ),
            _GridCell(
              typeKey: 'unsafe',
              label: 'Unsafe / Threat',
              description: 'Assault, transit monitoring',
              icon: Icons.personal_injury_outlined,
              iconColor: Color(0xFF0F172A),
            ),
          ],
        ),
      ],
    );
  }
}

class _NonEmergencyGrid extends StatelessWidget {
  const _NonEmergencyGrid({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROADSIDE UTILITY DISPATCH',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF64748B),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.08,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: const [
            _GridCell(
              typeKey: 'towing',
              label: 'Towing Service',
              description: 'Flatbeds, recovery transit',
              icon: Icons.car_repair_outlined,
              iconColor: Color(0xFF0D9488),
            ),
            _GridCell(
              typeKey: 'breakdown',
              label: 'Breakdown Help',
              description: 'Jump starts, locks, fuel',
              icon: Icons.handyman_outlined,
              iconColor: Color(0xFF059669),
            ),
            _GridCell(
              typeKey: 'puncture',
              label: 'Puncture Repair',
              description: 'Tire swaps, patch fixes',
              icon: Icons.tire_repair_outlined,
              iconColor: Color(0xFFD97706),
            ),
            _GridCell(
              typeKey: 'helpline',
              label: 'Helpline & Numbers',
              description: '112 · 108 · 100 · 1033',
              icon: Icons.phone_in_talk_outlined,
              iconColor: Color(0xFF7C3AED),
            ),
          ],
        ),
      ],
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.typeKey,
    required this.label,
    required this.description,
    required this.icon,
    required this.iconColor,
  });

  final String typeKey;
  final String label;
  final String description;
  final IconData icon;
  final Color iconColor;

  static const _nonEmergencyKeys = {'towing', 'breakdown', 'puncture'};

  @override
  Widget build(BuildContext context) {
    return _BouncingWidget(
      onTap: () {
        if (typeKey == 'unsafe') {
          context.push('/safety');
        } else if (typeKey == 'helpline') {
          showHelplineSheet(context);
        } else if (_nonEmergencyKeys.contains(typeKey)) {
          context.push('/results', extra: {
            'sessionId': '',
            'emergencyType': typeKey,
            'victimType': 'none',
            'isNonEmergency': true,
            'nonEmergencyCategory': typeKey,
          });
        } else {
          context.push('/triage', extra: {'emergencyType': typeKey});
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: iconColor,
                  ),
                ),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 16,
                  color: iconColor.withValues(alpha: 0.6),
                ),
              ],
            ),
            const Spacer(),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A), // Deep Slate
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B), // Slate-500
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dispatch Radar ────────────────────────────────────────────────────────────

class _DispatchRadar extends StatelessWidget {
  final HomeState state;
  const _DispatchRadar({required this.state});

  @override
  Widget build(BuildContext context) {
    final isLoading = state.isLoadingServices;
    final services = state.nearestServices;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NEARBY RESPONDERS',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF64748B),
                  letterSpacing: 1.0,
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0xFF64748B),
                  ),
                )
              else
                Row(
                  children: [
                    const _PulsingStatusDot(color: Color(0xFF10B981), size: 6),
                    const SizedBox(width: 4),
                    Text(
                      'GPS SYNCED',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (isLoading && services.isEmpty)
            _buildRadarLoading()
          else if (services.isEmpty)
            _buildRadarEmpty()
          else
            _buildRadarList(services),
        ],
      ),
    );
  }

  Widget _buildRadarLoading() {
    return Container(
      height: 84,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDF2F7), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Locating active responders...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarEmpty() {
    return Container(
      height: 84,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDF2F7), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const _RadarSweep(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS Tracker Active',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Monitoring nearby rescue services in real-time.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarList(List<ServiceModel> services) {
    return Column(
      children: services.map((svc) {
        final categoryColor = _getRadarCategoryColor(svc.category);
        final categoryIcon = _getRadarCategoryIcon(svc.category);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Stack containing the icon container and online dot
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      categoryIcon,
                      size: 22,
                      color: categoryColor,
                    ),
                  ),
                  const Positioned(
                    top: -2,
                    right: -2,
                    child: _PulsingStatusDot(
                      color: Color(0xFF10B981), // Online green dot
                      size: 7,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      svc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (svc.distanceKm != null) ...[
                          Text(
                            svc.formattedDistance,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F766E), // Deep Emerald
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          svc.trustLabel,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (svc.phonePrimary != null) ...[
                const SizedBox(width: 8),
                _BouncingWidget(
                  onTap: () async {
                    final uri = Uri(scheme: 'tel', path: svc.phonePrimary!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5), // Soft green background
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFA7F3D0), width: 1.0),
                    ),
                    child: const Icon(
                      Icons.call_outlined,
                      size: 16,
                      color: Color(0xFF059669),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getRadarCategoryColor(String category) {
    switch (category) {
      case 'hospital':
        return const Color(0xFF7C3AED);
      case 'police':
        return AppTheme.policeBlue;
      case 'ambulance':
        return AppTheme.emergencyRed;
      case 'fire':
        return const Color(0xFFEA580C);
      default:
        return AppTheme.primaryGreen;
    }
  }

  IconData _getRadarCategoryIcon(String category) {
    switch (category) {
      case 'hospital':
        return Icons.local_hospital_outlined;
      case 'police':
        return Icons.local_police_outlined;
      case 'ambulance':
        return Icons.airport_shuttle_outlined;
      case 'fire':
        return Icons.local_fire_department_outlined;
      default:
        return Icons.place_outlined;
    }
  }
}

// ── Quick Dial Hotlines ────────────────────────────────────────────────────────

class _QuickDial extends StatelessWidget {
  const _QuickDial();

  Future<void> _makeCall(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text(
                'EMERGENCY DIRECT LINES',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF64748B),
                  letterSpacing: 1.0,
                ),
              ),
            ),
            _QuickDialRow(
              icon: Icons.emergency_outlined,
              title: 'Police',
              description: 'Law enforcement & public safety dispatch',
              number: '100',
              iconColor: const Color(0xFF2563EB),
              onTap: () => _makeCall('100'),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16),
            _QuickDialRow(
              icon: Icons.medical_services_outlined,
              title: 'Ambulance',
              description: 'Emergency medical services & trauma rescue',
              number: '108',
              iconColor: const Color(0xFFE11D48),
              onTap: () => _makeCall('108'),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16),
            _QuickDialRow(
              icon: Icons.local_fire_department_outlined,
              title: 'Fire Brigade',
              description: 'Fire control & hazardous material dispatch',
              number: '101',
              iconColor: const Color(0xFFEA580C),
              onTap: () => _makeCall('101'),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16),
            _QuickDialRow(
              icon: Icons.phone_in_talk_outlined,
              title: 'Unified Emergency',
              description: 'National emergency desk & consolidated rescue',
              number: '112',
              iconColor: const Color(0xFF059669),
              isGreenNumber: true,
              onTap: () => _makeCall('112'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _QuickDialRow extends StatelessWidget {
  const _QuickDialRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.number,
    required this.iconColor,
    required this.onTap,
    this.isGreenNumber = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String number;
  final Color iconColor;
  final VoidCallback onTap;
  final bool isGreenNumber;

  @override
  Widget build(BuildContext context) {
    return _BouncingWidget(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  number,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isGreenNumber ? const Color(0xFF059669) : const Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Toll-Free',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5), // Soft green tint
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_outlined,
                size: 16,
                color: Color(0xFF059669),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



// ── Premium Custom Micro-Interaction & Animation Widgets ─────────────────────

/// Bouncing tactile gesture wrapper that scales down the child slightly on tap.
class _BouncingWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _BouncingWidget({required this.child, required this.onTap});

  @override
  _BouncingWidgetState createState() => _BouncingWidgetState();
}

class _BouncingWidgetState extends State<_BouncingWidget>
    with SingleTickerProviderStateMixin {
  late double _scale;
  late AnimationController _controller;

  @override
  void initState() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.0,
      upperBound: 0.03,
    )..addListener(() {
        setState(() {});
      });
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scale = 1 - _controller.value;
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      child: Transform.scale(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

/// Static pulsing dot representing active connectivity status.
class _PulsingStatusDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingStatusDot({required this.color, this.size = 8});

  @override
  _PulsingStatusDotState createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<_PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 2.0).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          ),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.5, end: 0.0).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOut),
            ),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        Container(
          width: widget.size - 1.5,
          height: widget.size - 1.5,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

// ── Live Radar Scanner Sweep Widget ──────────────────────────────────────────

class _RadarSweep extends StatefulWidget {
  const _RadarSweep();

  @override
  _RadarSweepState createState() => _RadarSweepState();
}

class _RadarSweepState extends State<_RadarSweep>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(54, 54),
      painter: _RadarPainter(_controller),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Animation<double> animation;
  _RadarPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    final Paint circlePaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw concentric radar lines
    canvas.drawCircle(center, radius, circlePaint);
    canvas.drawCircle(center, radius * 0.65, circlePaint);
    canvas.drawCircle(center, radius * 0.3, circlePaint);

    // Draw grid crosshairs
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), circlePaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), circlePaint);

    // Draw rotating sweep segment
    final Shader sweepShader = SweepGradient(
      colors: [
        const Color(0xFF10B981).withValues(alpha: 0.0),
        const Color(0xFF10B981).withValues(alpha: 0.3),
      ],
      stops: const [0.75, 1.0],
      transform: GradientRotation(animation.value * 2 * math.pi),
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    final Paint sweepFillPaint = Paint()
      ..shader = sweepShader
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, sweepFillPaint);

    // Draw two tiny blinking satellite responder dots
    const double dot1Angle = 0.65;
    const double dot2Angle = 2.45;
    final double dot1Dist = radius * 0.72;
    final double dot2Dist = radius * 0.42;

    final Offset dot1 = Offset(
      center.dx + dot1Dist * math.cos(dot1Angle),
      center.dy + dot1Dist * math.sin(dot1Angle),
    );
    final Offset dot2 = Offset(
      center.dx + dot2Dist * math.cos(dot2Angle),
      center.dy + dot2Dist * math.sin(dot2Angle),
    );

    final Paint dotPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(dot1, 2.5, dotPaint);
    canvas.drawCircle(dot2, 2.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
