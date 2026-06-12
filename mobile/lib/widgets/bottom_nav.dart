import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

enum BottomTab { home, journey, ai, history, profile }

class FloatingBottomNav extends StatelessWidget {
  final BottomTab activeTab;

  const FloatingBottomNav({
    super.key,
    required this.activeTab,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 14),
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24), // High glassmorphic blur
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15), // sheer frosted glass effect
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  isActive: activeTab == BottomTab.home,
                  onTap: () {
                    if (activeTab != BottomTab.home) {
                      context.go('/home');
                    }
                  },
                ),
                _NavItem(
                  icon: Icons.route_outlined,
                  label: 'Journey',
                  isActive: activeTab == BottomTab.journey,
                  onTap: () {
                    if (activeTab != BottomTab.journey) {
                      context.go('/journey');
                    }
                  },
                ),
                _NavItem(
                  icon: Icons.psychology_outlined,
                  label: 'AI Helper',
                  isActive: activeTab == BottomTab.ai,
                  onTap: () {
                    if (activeTab != BottomTab.ai) {
                      context.go('/ai');
                    }
                  },
                ),
                _NavItem(
                  icon: Icons.history_outlined,
                  label: 'History',
                  isActive: activeTab == BottomTab.history,
                  onTap: () {
                    if (activeTab != BottomTab.history) {
                      context.go('/history');
                    }
                  },
                ),
                _NavItem(
                  icon: Icons.person_outlined,
                  label: 'Profile',
                  isActive: activeTab == BottomTab.profile,
                  onTap: () {
                    if (activeTab != BottomTab.profile) {
                      context.go('/profile');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF0F172A); // Clean dark active color
    const unactiveColor = Color(0xFF64748B); // Slate-500

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isActive ? 14 : 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withValues(alpha: 0.5) : Colors.transparent, // Liquid glass active pill
          borderRadius: BorderRadius.circular(16),
          border: isActive
              ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.0)
              : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? activeColor : unactiveColor,
            ),
            if (isActive) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: activeColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
