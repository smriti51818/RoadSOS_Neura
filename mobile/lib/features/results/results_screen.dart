import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/models/service_model.dart';
import '../../services/ai_service.dart';
import 'results_provider.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key, required this.params});

  final Map<String, dynamic> params;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Future<AiResponse>? _aiGuidanceFuture;
  bool _isNonEmergency = false;
  String _nonEmergencyCat = '';

  ResultsNotifierProvider get _provider =>
      resultsNotifierProvider(
      sessionId: widget.params['sessionId'] as String? ?? '',
      emergencyType: widget.params['emergencyType'] as String? ?? 'accident',
      victimType: widget.params['victimType'] as String? ?? 'self',
      nonEmergencyCategory: widget.params['nonEmergencyCategory'] as String? ?? '',
    );

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    final p = widget.params;
    if (p['isNonEmergency'] == true) {
      _isNonEmergency = true;
      _nonEmergencyCat = p['emergencyType'] as String? ?? 'towing';
    } else {
      final victimType = p['victimType'] as String? ?? '';
      if (victimType != 'bystander' && victimType != 'vehicle_only') {
        _aiGuidanceFuture = ref.read(aiServiceProvider.notifier).generateFirstAidGuidance(
              p['emergencyType'] as String? ?? 'medical',
              (p['victimDetails'] as List<dynamic>?)?.map((v) => v.toString()).toList() ?? [],
            );
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }


  String _nonEmergencyCategoryLabel(String cat) {
    switch (cat) {
      case 'towing': return 'Towing Services';
      case 'breakdown': return 'Breakdown Help';
      case 'puncture': return 'Puncture Repair';
      case 'helpline': return 'Assistance Helplines';
      default: return _capitalize(cat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_provider);

    ref.listen<AsyncValue<ResultsState>>(_provider, (_, next) {
      next.whenData((s) {
        if (s.emergencyResolved && context.mounted) {
          context.go('/home');
        }
      });
    });

    final state = async.valueOrNull ?? ResultsState.empty();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _isNonEmergency ? _nonEmergencyCategoryLabel(_nonEmergencyCat) : 'Help is on the way',
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF0F172A),
            fontSize: 16,
            fontWeight: FontWeight.w700,
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
              icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 18),
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
                Expanded(
                  child: async.when(
                    loading: () => _buildLoadingBody(),
                    error: (err, _) => Center(
                      child: Text(
                        'Error: $err',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTheme.emergencyRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    data: (_) => _buildBody(context, state),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ResultsState state) {
    if (_isNonEmergency) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: const Color(0xFFFECDD3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (_, __) => Opacity(
                    opacity: _pulseAnimation.value,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE11D48),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Emergency active · Services loading',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE11D48),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ResultsState state) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isNonEmergency) ...[
            Text(
              'ONE-TAP EMERGENCY CALL',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF64748B),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('tel:112')),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB91C1C), Color(0xFFE11D48)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Emergency 112',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 2x2 Number grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.9,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _QuickCallCard(title: 'Ambulance', number: '108', color: const Color(0xFFE11D48)),
                _QuickCallCard(title: 'Police', number: '100', color: const Color(0xFF2563EB)),
                _QuickCallCard(title: 'Fire Brigade', number: '101', color: const Color(0xFFD97706)),
                _QuickCallCard(title: 'NHAI Helpline', number: '1033', color: const Color(0xFF10B981)),
              ],
            ),
            const SizedBox(height: 32),

            if (_aiGuidanceFuture != null) ...[
              _buildAIGuidanceCard(),
              const SizedBox(height: 32),
            ],
          ],

          Text(
            'NEARBY SERVICES',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          
          if (state.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (state.dataSource == ServicesSource.unavailable || state.allServices.isEmpty)
            const Text('No nearby services found.')
          else
            ..._buildServiceSections(state),

          const SizedBox(height: 32),

          if (!_isNonEmergency) ...[
            GestureDetector(
              onTap: () => ref.read(_provider.notifier).shareLocationViaSMS(),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(27),
                  border: Border.all(color: AppTheme.primaryGreen, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.share_rounded, size: 18, color: AppTheme.primaryGreen),
                    const SizedBox(width: 10),
                    Text(
                      'Share location via SMS',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          
          GestureDetector(
            onTap: () => ref.read(_provider.notifier).resolveEmergency(),
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(27),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    _isNonEmergency ? 'Done' : 'Emergency resolved — I\'m safe',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIGuidanceCard() {
    return FutureBuilder<AiResponse>(
      future: _aiGuidanceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final guidance = snapshot.data!;
        
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'AI FIRST AID GUIDANCE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF64748B),
                      letterSpacing: 1.0,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.psychology_rounded, size: 12, color: Color(0xFF2563EB)),
                        const SizedBox(width: 4),
                        Text(
                          'Gemini AI',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                guidance.text,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF334155),
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  List<Widget> _buildServiceSections(ResultsState state) {
    const categoryOrder = [
      'ambulance',
      'hospital',
      'police',
      'fire',
      'towing',
      'breakdown',
      'puncture',
    ];

    final widgets = <Widget>[];
    final ordered = [
      ...categoryOrder.where((c) => state.servicesByCategory.containsKey(c)),
      ...state.servicesByCategory.keys.where((c) => !categoryOrder.contains(c)),
    ];

    for (final cat in ordered) {
      final services = state.servicesByCategory[cat];
      if (services == null || services.isEmpty) continue;

      final displayed = services.take(3).toList();
      for (final s in displayed) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ServiceCard(service: s),
        ));
      }
    }
    return widgets;
  }

  Widget _buildLoadingBody() {
    return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
  }
}

class _QuickCallCard extends StatelessWidget {
  const _QuickCallCard({
    required this.title,
    required this.number,
    required this.color,
  });

  final String title;
  final String number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse('tel:$number')),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  number,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.call_rounded, size: 14, color: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});

  final ServiceModel service;

  @override
  Widget build(BuildContext context) {
    final distanceText = service.distanceKm != null
        ? '${service.distanceKm!.toStringAsFixed(1)} km'
        : 'Nearby';

    return GestureDetector(
      onTap: () => context.push('/service-details', extra: service),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFEE2E2)),
              ),
              child: Text(
                distanceText,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFEF4444),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    service.address ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (service.is24hr) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD1FAE5)),
                ),
                child: Text(
                  '24h',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.successGreen,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}
