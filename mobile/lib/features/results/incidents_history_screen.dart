// lib/features/results/incidents_history_screen.dart
// Module 6 — Incidents history screen.
// Redesigned to Premium Light Theme with floating elements.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/providers/incidents_provider.dart';
import '../../widgets/bottom_nav.dart';

class IncidentsHistoryScreen extends ConsumerWidget {
  const IncidentsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidents = ref.watch(incidentsProvider);
    final canPop = GoRouter.of(context).canPop();

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

          // Main Screen Content
          Column(
            children: [
              // Custom top bar card
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 16,
                  20,
                  8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  child: Row(
                    children: [
                      if (canPop)
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: Container(
                            width: 36,
                            height: 36,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.history_outlined,
                            size: 18,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      Text(
                        'My Incidents',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Incidents body
              Expanded(
                child: incidents.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120), // Spaced bottom for Bottom Nav
                        itemCount: incidents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _IncidentCard(incident: incidents[index]);
                        },
                      ),
              ),
            ],
          ),

          // Shared Bottom Navigation Bar
          const Align(
            alignment: Alignment.bottomCenter,
            child: FloatingBottomNav(activeTab: BottomTab.history),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.history_toggle_off_rounded,
              size: 48,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Incidents Tracked',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Any emergency requests you send\nwill appear here.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident});

  final IncidentRecord incident;

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'hospital':
      case 'medical':
      case 'ambulance':
        return Icons.medical_services_outlined;
      case 'police':
        return Icons.gpp_maybe_outlined;
      case 'fire':
        return Icons.local_fire_department_outlined;
      case 'towing':
        return Icons.rv_hookup_outlined;
      case 'breakdown':
      case 'puncture':
      case 'repair':
        return Icons.construction_outlined;
      default:
        return Icons.business_center_outlined;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'hospital':
      case 'medical':
      case 'ambulance':
        return const Color(0xFF2563EB); // blue
      case 'police':
        return const Color(0xFF0F172A); // dark/slate
      case 'fire':
        return const Color(0xFFEA580C); // orange
      case 'towing':
        return const Color(0xFF0D9488); // teal
      case 'breakdown':
      case 'puncture':
      case 'repair':
        return const Color(0xFF059669); // emerald/green
      default:
        return AppTheme.primaryGreen;
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'active':
      case 'resolved':
        return const Color(0xFFECFDF5);
      case 'pending':
      case 'dispatched':
      case 'arriving':
        return const Color(0xFFEFF6FF);
      case 'cancelled':
      case 'failed':
        return const Color(0xFFFEF2F2);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  Color _getStatusTextColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'active':
      case 'resolved':
        return const Color(0xFF047857);
      case 'pending':
      case 'dispatched':
      case 'arriving':
        return const Color(0xFF1D4ED8);
      case 'cancelled':
      case 'failed':
        return const Color(0xFFE11D48);
      default:
        return const Color(0xFF475569);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(i.timestamp);
    final iconColor = _getCategoryColor(i.service.category);
    final categoryIcon = _getCategoryIcon(i.service.category);

    final statusBg = _getStatusBgColor(i.status);
    final statusText = _getStatusTextColor(i.status);

    return GestureDetector(
      onTap: () {
        context.push('/incident-details', extra: {
          'incident': i,
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.premiumCardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(categoryIcon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.service.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dateStr,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusText.withValues(alpha: 0.2), width: 1.0),
                  ),
                  child: Text(
                    i.status.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: statusText,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
