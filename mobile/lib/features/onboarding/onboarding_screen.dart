// lib/features/onboarding/onboarding_screen.dart
// Module 3 — Onboarding screen.
// Redesigned to Premium Light Theme with SaaS mesh blobs.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Page 2 — profile
  final _nameController = TextEditingController();
  String _bloodGroup = '';

  // Page 3 — contacts
  final List<TextEditingController> _contactControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  // Page 4 — location
  bool _locationGranted = false;

  bool _saving = false;
  static const int _totalPages = 5;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    for (final c in _contactControllers) c.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_currentPage == 1 && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }
    if (_currentPage == 2) {
      final hasContact = _contactControllers.any((c) => c.text.trim().isNotEmpty);
      if (!hasContact) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one emergency contact')),
        );
        return;
      }
    }
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _pickContact(int index) async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    if (status == PermissionStatus.granted) {
      final contact = await FlutterContacts.native.showPicker(properties: {ContactProperty.phone});
      if (contact != null && contact.phones.isNotEmpty) {
        final phone = contact.phones.first.number.replaceAll(RegExp(r'[^\d+]'), '');
        setState(() {
          _contactControllers[index].text = phone;
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contacts permission denied')),
        );
      }
    }
  }

  void _goBack() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _requestLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      setState(() {
        _locationGranted = permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;
      });
    } catch (e) {
      debugPrint('[Onboarding] Location permission error: $e');
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();

      final name = _nameController.text.trim();
      if (name.isNotEmpty) await prefs.setString('user_name', name);

      if (_bloodGroup.isNotEmpty) {
        await prefs.setString('blood_group', _bloodGroup);
      }

      final contacts = _contactControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await prefs.setStringList('emergency_contacts', contacts);
      await prefs.setBool('onboarding_complete', true);

      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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

          // Main Layout Content
          SafeArea(
            child: Column(
              children: [
                // Top Progress Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      if (_currentPage > 0)
                        GestureDetector(
                          onTap: _goBack,
                          child: Container(
                            width: 36,
                            height: 36,
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
                        const SizedBox(width: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (_currentPage + 1) / _totalPages,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGreen,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${_currentPage + 1}/$_totalPages',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),

                // Pages content
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (p) => setState(() => _currentPage = p),
                    children: [
                      _WelcomePage(onNext: _goNext),
                      _ProfilePage(
                        nameController: _nameController,
                        bloodGroup: _bloodGroup,
                        onBloodGroupChanged: (v) => setState(() => _bloodGroup = v),
                        onNext: _goNext,
                      ),
                      _ContactsPage(
                        controllers: _contactControllers,
                        onNext: _goNext,
                        onPickContact: _pickContact,
                      ),
                      _LocationPage(
                        granted: _locationGranted,
                        onRequest: _requestLocation,
                        onNext: _goNext,
                      ),
                      _ReadyPage(
                        name: _nameController.text,
                        contacts: _contactControllers
                            .map((c) => c.text.trim())
                            .where((s) => s.isNotEmpty)
                            .toList(),
                        locationGranted: _locationGranted,
                        saving: _saving,
                        onStart: _saving ? null : _finish,
                      ),
                    ],
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

// ── Private Reusable Components ──────────────────────────────────────────────

class _TopCircleIcon extends StatelessWidget {
  final IconData icon;
  const _TopCircleIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 28, color: AppTheme.primaryGreen),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PrimaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SkipTextButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SkipTextButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF64748B),
        ),
        child: Text(
          'Skip for now',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SoftTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final Widget? prefixIcon;
  final List<TextInputFormatter>? inputFormatters;

  const _SoftTextField({
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 14.5, fontWeight: FontWeight.w600),
        prefixIcon: prefixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 2),
        ),
      ),
      style: GoogleFonts.plusJakartaSans(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
    );
  }
}

// ── Page 1: Welcome ────────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          const _TopCircleIcon(icon: Icons.shield_outlined),
          const SizedBox(height: 24),
          Text(
            'Welcome to RoadSoS',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your emergency road safety companion for every journey.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          
          // Unified Feature Card
          Container(
            decoration: AppTheme.premiumCardDecoration,
            child: Column(
              children: [
                _FeatureRow(
                  icon: Icons.location_on_outlined,
                  iconBg: const Color(0xFFEFF6FF),
                  iconColor: const Color(0xFF2563EB),
                  title: 'Live Location Sharing',
                  subtitle: 'Share GPS with responders instantly',
                  showDivider: true,
                ),
                _FeatureRow(
                  icon: Icons.wifi_off_outlined,
                  iconBg: const Color(0xFFECFDF5),
                  iconColor: const Color(0xFF10B981),
                  title: 'Works 100% Offline',
                  subtitle: 'Emergency numbers always accessible',
                  showDivider: true,
                ),
                _FeatureRow(
                  icon: Icons.psychology_outlined,
                  iconBg: const Color(0xFFF5F3FF),
                  iconColor: const Color(0xFF7C3AED),
                  title: 'AI First Aid Guidance',
                  subtitle: 'Step-by-step help until services arrive',
                  showDivider: true,
                ),
                _FeatureRow(
                  icon: Icons.route_outlined,
                  iconBg: const Color(0xFFFFFBEB),
                  iconColor: const Color(0xFFD97706),
                  title: 'Journey Safety Mode',
                  subtitle: 'Auto-alerts if you go off route',
                  showDivider: false,
                ),
              ],
            ),
          ),
          
          const Spacer(),
          _PrimaryButton(label: 'Get started →', onTap: onNext),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool showDivider;

  const _FeatureRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 18),
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
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9), indent: 70, endIndent: 16),
      ],
    );
  }
}

// ── Page 2: Profile ────────────────────────────────────────────────────────────

class _ProfilePage extends StatelessWidget {
  final TextEditingController nameController;
  final String bloodGroup;
  final void Function(String) onBloodGroupChanged;
  final VoidCallback onNext;

  const _ProfilePage({
    required this.nameController,
    required this.bloodGroup,
    required this.onBloodGroupChanged,
    required this.onNext,
  });

  static const _groups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          const _TopCircleIcon(icon: Icons.person_outline_rounded),
          const SizedBox(height: 24),
          Text(
            'Tell us about you',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your name and blood group help responders prepare.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          _SoftTextField(
            controller: nameController,
            hint: 'Your full name',
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'BLOOD GROUP (OPTIONAL)',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF94A3B8),
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.start,
            children: _groups.map((g) {
              final selected = bloodGroup == g;
              return GestureDetector(
                onTap: () => onBloodGroupChanged(selected ? '' : g),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFFEF2F2) : Colors.white, // Soft red active pill
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? AppTheme.emergencyRed : const Color(0xFFE2E8F0),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    g,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppTheme.emergencyRed : const Color(0xFF475569),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 48),
          _PrimaryButton(label: 'Continue →', onTap: onNext),
          const SizedBox(height: 12),
          _SkipTextButton(onTap: onNext),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Page 3: Contacts ───────────────────────────────────────────────────────────

class _ContactsPage extends StatelessWidget {
  final List<TextEditingController> controllers;
  final VoidCallback onNext;
  final void Function(int) onPickContact;

  const _ContactsPage({
    required this.controllers,
    required this.onNext,
    required this.onPickContact,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          const _TopCircleIcon(icon: Icons.people_outline_rounded),
          const SizedBox(height: 24),
          Text(
            'Emergency contacts',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We\'ll SMS them your location during emergencies.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          for (int i = 0; i < 3; i++) ...[
            _SoftTextField(
              controller: controllers[i],
              hint: i == 0 ? 'Contact 1 phone number *' : 'Contact ${i + 1} phone number',
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
              prefixIcon: GestureDetector(
                onTap: () => onPickContact(i),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: const Icon(Icons.phone_outlined, size: 20, color: Color(0xFF94A3B8)),
                ),
              ),
            ),
            if (i < 2) const SizedBox(height: 16),
          ],
          const SizedBox(height: 48),
          _PrimaryButton(label: 'Continue →', onTap: onNext),
          const SizedBox(height: 12),
          _SkipTextButton(onTap: onNext),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Page 4: Location ───────────────────────────────────────────────────────────

class _LocationPage extends StatelessWidget {
  final bool granted;
  final VoidCallback onRequest;
  final VoidCallback onNext;

  const _LocationPage({
    required this.granted,
    required this.onRequest,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          const _TopCircleIcon(icon: Icons.location_on_outlined),
          const SizedBox(height: 24),
          Text(
            'Allow location access',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Precise GPS helps dispatch reach you faster.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(20),
            decoration: AppTheme.premiumCardDecoration,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: granted ? AppTheme.primaryGreen.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    granted ? Icons.check_circle_outline_rounded : Icons.location_off_outlined,
                    color: granted ? AppTheme.primaryGreen : const Color(0xFF64748B),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        granted ? 'Location access granted' : 'Location permission',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: granted ? AppTheme.primaryGreen : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        granted ? 'Ready for emergencies' : 'Not granted yet',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          if (!granted)
            _PrimaryButton(label: 'Allow location access', onTap: onRequest),
          
          const Spacer(),
          _PrimaryButton(
            label: granted ? 'Continue →' : 'Continue without GPS',
            onTap: onNext,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Page 5: Ready ──────────────────────────────────────────────────────────────

class _ReadyPage extends StatelessWidget {
  final String name;
  final List<String> contacts;
  final bool locationGranted;
  final bool saving;
  final VoidCallback? onStart;

  const _ReadyPage({
    required this.name,
    required this.contacts,
    required this.locationGranted,
    required this.saving,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          const _TopCircleIcon(icon: Icons.check_circle_outline_rounded),
          const SizedBox(height: 24),
          Text(
            'You\'re all set!',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Here\'s your setup summary. You can change everything later in Profile.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          
          Container(
            decoration: AppTheme.premiumCardDecoration,
            child: Column(
              children: [
                _SummaryRow(
                  icon: Icons.person_outline_rounded,
                  iconColor: const Color(0xFF2563EB),
                  iconBg: const Color(0xFFEFF6FF),
                  title: 'Name',
                  value: name.isEmpty ? 'Not set' : name,
                  showDivider: true,
                ),
                _SummaryRow(
                  icon: Icons.people_outline_rounded,
                  iconColor: const Color(0xFF7C3AED),
                  iconBg: const Color(0xFFF5F3FF),
                  title: 'Emergency contacts',
                  value: contacts.isEmpty ? 'None added' : '${contacts.length} contact(s)',
                  showDivider: true,
                ),
                _SummaryRow(
                  icon: Icons.location_on_outlined,
                  iconColor: const Color(0xFF10B981),
                  iconBg: const Color(0xFFECFDF5),
                  title: 'Location',
                  value: locationGranted ? 'Granted ✓' : 'Not granted',
                  showDivider: false,
                ),
              ],
            ),
          ),
          
          const Spacer(),
          _PrimaryButton(
            label: saving ? 'Starting...' : 'Start using RoadSoS →',
            onTap: onStart,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String value;
  final bool showDivider;

  const _SummaryRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.value,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9), indent: 70, endIndent: 16),
      ],
    );
  }
}
