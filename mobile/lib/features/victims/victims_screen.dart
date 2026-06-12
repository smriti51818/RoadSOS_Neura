import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import 'victims_provider.dart';

class VictimsScreen extends ConsumerStatefulWidget {
  const VictimsScreen({super.key});

  @override
  ConsumerState<VictimsScreen> createState() => _VictimsScreenState();
}

class _VictimsScreenState extends ConsumerState<VictimsScreen> {
  bool _countConfirmed = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(victimsNotifierProvider);

    ref.listen<AsyncValue<VictimsState>>(victimsNotifierProvider, (_, next) {
      next.whenData((s) {
        if (s.isComplete && context.mounted) {
          context.pop<Map<String, dynamic>>({
            'victimCount': s.totalVictims,
            'victimDetails': s.victims,
          });
        }
      });
    });

    final state = async.valueOrNull ?? VictimsState.initial();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Victim Details',
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
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
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, state),
                _buildProgressBar(state),
                Expanded(
                  child: _countConfirmed
                      ? _buildVictimForm(state)
                      : _buildCountSelector(state),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, VictimsState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _countConfirmed ? _victimFormTitle(state) : 'How many people?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _countConfirmed
                ? 'Fill in the details to help responders prepare.'
                : 'Include all injured or at-risk people',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  String _victimFormTitle(VictimsState state) {
    if (state.totalVictims == 1) return 'Victim Details';
    return 'Victim ${state.currentVictimIndex + 1} of ${state.totalVictims}';
  }

  Widget _buildProgressBar(VictimsState state) {
    if (!_countConfirmed || state.totalVictims <= 1) return const SizedBox(height: 16);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: List.generate(state.totalVictims, (i) {
          final isActive = i == state.currentVictimIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isActive ? AppTheme.primaryGreen : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? AppTheme.primaryGreen : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isActive ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCountSelector(VictimsState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: AppTheme.softShadows,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StepperButton(
                      icon: Icons.remove_rounded,
                      onTap: state.totalVictims > 1
                          ? () => ref.read(victimsNotifierProvider.notifier).setTotalVictims(state.totalVictims - 1)
                          : null,
                    ),
                    const SizedBox(width: 32),
                    Text(
                      '${state.totalVictims}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 64,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 32),
                    _StepperButton(
                      icon: Icons.add_rounded,
                      onTap: state.totalVictims < 6
                          ? () => ref.read(victimsNotifierProvider.notifier).setTotalVictims(state.totalVictims + 1)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 12,
                  children: [1, 2, 3, 4, 5, 6].map((n) {
                    final selected = state.totalVictims == n;
                    return GestureDetector(
                      onTap: () => ref.read(victimsNotifierProvider.notifier).setTotalVictims(n),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primaryGreen : Colors.white,
                          border: Border.all(color: selected ? AppTheme.primaryGreen : const Color(0xFFE2E8F0)),
                          shape: BoxShape.circle,
                          boxShadow: selected ? [
                            BoxShadow(
                              color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ] : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '$n',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'Continue',
            onTap: () => setState(() => _countConfirmed = true),
          ),
        ],
      ),
    );
  }

  Widget _buildVictimForm(VictimsState state) {
    if (state.victims.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final victimIndex = state.currentVictimIndex;
    final victim = state.victims[victimIndex];
    final notifier = ref.read(victimsNotifierProvider.notifier);

    final canProceed = victim.ageGroup.isNotEmpty &&
        victim.condition.isNotEmpty &&
        victim.helpType.isNotEmpty;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Age group
          _FormCard(
            label: 'AGE GROUP',
            child: Wrap(
              spacing: 8,
              runSpacing: 12,
              children: [
                ('child_0_12', 'Child 0–12'),
                ('teen_13_17', 'Teen 13–17'),
                ('adult_18_60', 'Adult 18–60'),
                ('senior_60_plus', 'Senior 60+'),
              ].map((data) {
                final (value, label) = data;
                return _PillChip(
                  label: label,
                  selected: victim.ageGroup == value,
                  onTap: () => notifier.updateVictim(index: victimIndex, ageGroup: value),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Condition
          _FormCard(
            label: 'CONDITION',
            child: Wrap(
              spacing: 8,
              runSpacing: 12,
              children: [
                ('conscious', 'Conscious'),
                ('unconscious', 'Unconscious'),
                ('bleeding', 'Bleeding'),
                ('trapped', 'Trapped'),
              ].map((data) {
                final (value, label) = data;
                return _PillChip(
                  label: label,
                  selected: victim.condition == value,
                  onTap: () => notifier.updateVictim(index: victimIndex, condition: value),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Help type
          _FormCard(
            label: 'HELP NEEDED',
            child: Column(
              children: [
                ('ambulance', 'Ambulance', Icons.medical_services_outlined, const Color(0xFFEF4444), const Color(0xFFFEF2F2)),
                ('fire_rescue', 'Fire Rescue', Icons.local_fire_department_outlined, const Color(0xFFD97706), const Color(0xFFFFFBEB)),
                ('both', 'Ambulance + Fire', Icons.emergency_outlined, const Color(0xFFEF4444), const Color(0xFFFEF2F2)),
              ].map((data) {
                final (value, label, icon, color, bg) = data;
                final selected = victim.helpType == value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => notifier.updateVictim(index: victimIndex, helpType: value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: selected ? bg : Colors.white,
                        border: Border.all(
                          color: selected ? color : const Color(0xFFE2E8F0),
                          width: selected ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: selected ? color : color.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              icon,
                              size: 18,
                              color: selected ? Colors.white : color,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              label,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_circle_rounded, size: 20, color: color),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),

          _PrimaryButton(
            label: victimIndex < state.totalVictims - 1
                ? 'Next Victim →'
                : 'Done — Send Alert →',
            enabled: canProceed,
            onTap: canProceed ? () => notifier.nextVictim() : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF1F5F9),
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? const Color(0xFFE2E8F0) : const Color(0xFFE2E8F0).withValues(alpha: 0.5),
          ),
          boxShadow: enabled ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Icon(
          icon,
          size: 24,
          color: enabled ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: AppTheme.softShadows,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.primaryGreen,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFECFDF5) : Colors.white,
          border: Border.all(
            color: selected ? AppTheme.primaryGreen : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? AppTheme.primaryGreen : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppTheme.primaryGreen : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled ? [
            BoxShadow(
              color: AppTheme.primaryGreen.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ] : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: enabled ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}
