// lib/features/profile/profile_screen.dart
// Module 6 — User profile screen.
// Redesigned to Premium Light Theme with floating elements.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/services/db_service.dart';
import '../../widgets/bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '';
  String _phone = '';
  String _bloodGroup = '';
  List<String> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('user_name') ?? '';
      _phone = prefs.getString('user_phone') ?? '';
      _bloodGroup = prefs.getString('blood_group') ?? '';
      _contacts = prefs.getStringList('emergency_contacts') ?? [];
      _isLoading = false;
    });
  }

  Future<void> _saveName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', value);
    setState(() => _name = value);
    _syncToNeon();
  }

  Future<void> _savePhone(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_phone', value);
    setState(() => _phone = value);
    _syncToNeon();
  }

  Future<void> _saveBloodGroup(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('blood_group', value);
    setState(() => _bloodGroup = value);
    _syncToNeon();
  }

  Future<void> _syncToNeon() async {
    if (_phone.isNotEmpty) {
      try {
        await DbService.upsertUser(_phone, _name, _bloodGroup);
      } catch (e) {
        debugPrint('Failed to sync user to Neon: $e');
      }
    }
  }

  String get _initials {
    if (_name.isEmpty) return '?';
    final parts = _name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return _name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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

          // Main Profile Content
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header Title Row ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    MediaQuery.of(context).padding.top + 16,
                    20,
                    8,
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
                        ),
                      Text(
                        'Profile',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Profile Information Card ───────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.premiumCardDecoration,
                    child: Row(
                      children: [
                        // Left: Initials Avatar
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9), // Slate-100 background
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              _initials,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Right: User Details Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _name.isEmpty ? 'Set your name' : _name,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              if (_phone.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _phone,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.verified_user_rounded, size: 12, color: Color(0xFF10B981)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'VERIFIED',
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
                ),
              ),

              // ── Personal info ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Text(
                    'PERSONAL INFO',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    decoration: AppTheme.premiumCardDecoration,
                    child: Column(
                      children: [
                        _EditableRow(
                          label: 'Full name',
                          value: _name,
                          icon: Icons.person_outline_rounded,
                          hint: 'Enter your name',
                          onSave: _saveName,
                        ),
                        const Divider(
                          height: 1,
                          indent: 56,
                          color: Color(0xFFF1F5F9),
                        ),
                        _EditableRow(
                          label: 'Phone',
                          value: _phone,
                          icon: Icons.phone_outlined,
                          hint: 'Enter your phone',
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onSave: _savePhone,
                        ),
                        const Divider(
                          height: 1,
                          indent: 56,
                          color: Color(0xFFF1F5F9),
                        ),
                        _BloodGroupRow(
                          value: _bloodGroup,
                          onSave: _saveBloodGroup,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Emergency contacts ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Text(
                    'EMERGENCY CONTACTS',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _contacts.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: AppTheme.premiumCardDecoration,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'No emergency contacts. Add them during onboarding.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () => context.push('/onboarding'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    'Add',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primaryGreen,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          decoration: AppTheme.premiumCardDecoration,
                          child: Column(
                            children: _contacts.asMap().entries.map((e) {
                              final isLast = e.key == _contacts.length - 1;
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryGreen
                                                .withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.person_outline_rounded,
                                            size: 18,
                                            color: AppTheme.primaryGreen,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          e.value,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF1E293B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isLast)
                                    const Divider(
                                      height: 1,
                                      indent: 64,
                                      color: Color(0xFFF1F5F9),
                                    ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                ),
              ),

              // ── App section ────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Text(
                    'APP',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    decoration: AppTheme.premiumCardDecoration,
                    child: Column(
                      children: [
                        _AppRow(
                          icon: Icons.refresh_rounded,
                          label: 'Redo Onboarding',
                          onTap: () => context.push('/onboarding'),
                          color: AppTheme.primaryGreen,
                        ),
                        const Divider(
                          height: 1,
                          indent: 56,
                          color: Color(0xFFF1F5F9),
                        ),
                        _AppRow(
                          icon: Icons.info_outline_rounded,
                          label: 'RoadSoS v1.0.0 — IIT Madras CoERS 2026',
                          onTap: () {},
                          color: const Color(0xFF64748B),
                          isInfo: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)), // Space for bottom navigation
            ],
          ),

          // Shared Bottom Navigation Bar
          const Align(
            alignment: Alignment.bottomCenter,
            child: FloatingBottomNav(activeTab: BottomTab.profile),
          ),
        ],
      ),
    );
  }
}

// ── Editable row ───────────────────────────────────────────────────────────────

class _EditableRow extends StatefulWidget {
  const _EditableRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.hint,
    required this.onSave,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final String value;
  final IconData icon;
  final String hint;
  final Future<void> Function(String) onSave;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_EditableRow> createState() => _EditableRowState();
}

class _EditableRowState extends State<_EditableRow> {
  bool _editing = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, size: 16, color: const Color(0xFF64748B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _editing
                ? TextField(
                    controller: _ctrl,
                    autofocus: true,
                    keyboardType: widget.keyboardType,
                    inputFormatters: widget.inputFormatters,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF94A3B8),
                      ),
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                    onSubmitted: (v) async {
                      await widget.onSave(v.trim());
                      setState(() => _editing = false);
                    },
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.value.isEmpty ? widget.hint : widget.value,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14.5,
                          color: widget.value.isEmpty
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF1E293B),
                          fontWeight: widget.value.isEmpty
                              ? FontWeight.w600
                              : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
          GestureDetector(
            onTap: () async {
              if (_editing) {
                await widget.onSave(_ctrl.text.trim());
              }
              setState(() => _editing = !_editing);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _editing
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _editing ? Icons.check : Icons.edit_outlined,
                size: 14,
                color: _editing
                    ? const Color(0xFF10B981)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Blood group row ────────────────────────────────────────────────────────────

class _BloodGroupRow extends StatefulWidget {
  const _BloodGroupRow({required this.value, required this.onSave});

  final String value;
  final Future<void> Function(String) onSave;

  @override
  State<_BloodGroupRow> createState() => _BloodGroupRowState();
}

class _BloodGroupRowState extends State<_BloodGroupRow> {
  static const _groups = [
    'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-', 'Unknown',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bloodtype_outlined,
              size: 16,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Blood group',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.value.isEmpty ? 'Not set' : widget.value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    color: widget.value.isEmpty
                        ? const Color(0xFF94A3B8)
                        : AppTheme.emergencyRed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  title: Text(
                    'Select Blood Group',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  content: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _groups.map((g) {
                      final isSelected = widget.value == g || (widget.value.isEmpty && g == 'Unknown');
                      return GestureDetector(
                        onTap: () => Navigator.pop(ctx, g),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.emergencyRed.withValues(alpha: 0.08)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.emergencyRed
                                  : const Color(0xFFE2E8F0),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            g,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? AppTheme.emergencyRed
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
              if (result != null) {
                await widget.onSave(result == 'Unknown' ? '' : result);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_outlined,
                size: 14,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── App info row ───────────────────────────────────────────────────────────────

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.isInfo = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool isInfo;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  color: isInfo ? const Color(0xFF64748B) : const Color(0xFF1E293B),
                  fontWeight: isInfo ? FontWeight.w600 : FontWeight.w700,
                ),
              ),
            ),
            if (!isInfo)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: Color(0xFF94A3B8),
              ),
          ],
        ),
      ),
    );
  }
}
