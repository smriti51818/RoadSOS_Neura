import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

void showHelplineSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const HelplineSheet(),
  );
}

class HelplineSheet extends StatelessWidget {
  const HelplineSheet({super.key});

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Emergency Helplines',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap any number to call directly',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          _HelplineItem(
            label: 'Unified Emergency',
            subtitle: 'Police · Fire · Ambulance',
            number: '112',
            icon: Icons.emergency_outlined,
            color: const Color(0xFFE11D48),
            onTap: () => _call('112'),
          ),
          _HelplineItem(
            label: 'Ambulance / Medical',
            subtitle: 'Emergency medical services',
            number: '108',
            icon: Icons.monitor_heart_outlined,
            color: const Color(0xFF2563EB),
            onTap: () => _call('108'),
          ),
          _HelplineItem(
            label: 'Police',
            subtitle: 'Law enforcement & public safety',
            number: '100',
            icon: Icons.local_police_outlined,
            color: const Color(0xFF1D4ED8),
            onTap: () => _call('100'),
          ),
          _HelplineItem(
            label: 'NHAI Road Helpline',
            subtitle: 'Highway breakdowns & accidents',
            number: '1033',
            icon: Icons.add_road_outlined,
            color: const Color(0xFF16A34A),
            onTap: () => _call('1033'),
          ),
          _HelplineItem(
            label: 'Women Helpline',
            subtitle: 'Women in distress',
            number: '1091',
            icon: Icons.shield_outlined,
            color: const Color(0xFF7C3AED),
            onTap: () => _call('1091'),
          ),
        ],
      ),
    );
  }
}

class _HelplineItem extends StatelessWidget {
  const _HelplineItem({
    required this.label,
    required this.subtitle,
    required this.number,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final String number;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 14),
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
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              number,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.call_outlined, size: 16, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
