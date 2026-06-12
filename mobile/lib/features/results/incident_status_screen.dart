import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../data/models/service_model.dart';
import '../../data/providers/incidents_provider.dart';
import '../../data/services/db_service.dart';

// ─── Model ──────────────────────────────────────────────────────────────────
class IncidentUpdate {
  final String id;
  final String message;
  final String? responderName;
  final String? responderPhone;
  final double? responderLat;
  final double? responderLng;
  final DateTime createdAt;

  const IncidentUpdate({
    required this.id,
    required this.message,
    this.responderName,
    this.responderPhone,
    this.responderLat,
    this.responderLng,
    required this.createdAt,
  });

  factory IncidentUpdate.fromJson(Map<String, dynamic> json) {
    return IncidentUpdate(
      id: json['id'] as String,
      message: json['message'] as String,
      responderName: json['responder_name'] as String?,
      responderPhone: json['responder_phone'] as String?,
      responderLat: json['responder_lat'] != null
          ? (json['responder_lat'] as num).toDouble()
          : null,
      responderLng: json['responder_lng'] != null
          ? (json['responder_lng'] as num).toDouble()
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

// ─── Screen ─────────────────────────────────────────────────────────────────
class IncidentStatusScreen extends ConsumerStatefulWidget {
  const IncidentStatusScreen({
    super.key,
    required this.service,
    required this.photos,
    this.existingIncident,
  });

  final ServiceModel service;
  final List<String> photos;
  final IncidentRecord? existingIncident;

  @override
  ConsumerState<IncidentStatusScreen> createState() =>
      _IncidentStatusScreenState();
}

class _IncidentStatusScreenState extends ConsumerState<IncidentStatusScreen> {
  bool _isTransmitting = true;
  String? _incidentId;
  String _incidentStatus = 'Received';
  List<IncidentUpdate> _updates = [];
  IncidentUpdate? _latestUpdate;
  Timer? _pollTimer;
  Timer? _escalationTimer;
  int _escalationSecondsLeft = 15 * 60; // 15 minutes
  bool _escalationTriggered = false;
  bool _showEscalationBanner = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingIncident != null) {
      _incidentId = widget.existingIncident!.id;
      _incidentStatus = widget.existingIncident!.status;
      _isTransmitting = false;
      _startPolling(_incidentId!);
      if (_incidentStatus != 'Resolved' && _incidentStatus != 'Closed') {
        _startEscalationTimer();
      }
    } else {
      _transmit();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _escalationTimer?.cancel();
    super.dispose();
  }

  Future<void> _transmit() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final incidentId = const Uuid().v4();
    final record = IncidentRecord(
      id: incidentId,
      timestamp: DateTime.now(),
      service: widget.service,
      photos: widget.photos,
      status: 'Received',
    );

    ref.read(incidentsProvider.notifier).addIncidentRecord(record);
    setState(() {
      _isTransmitting = false;
      _incidentId = incidentId;
    });

    _startPolling(incidentId);
    _startEscalationTimer();
  }

  void _startPolling(String incidentId) {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _fetchUpdates(incidentId);
    });
  }

  Future<void> _fetchUpdates(String incidentId) async {
    try {
      final url = '${DbService.baseUrl}/incidents/$incidentId/updates';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (!mounted || res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final updates = (data['updates'] as List)
          .map((e) => IncidentUpdate.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _updates = updates;
        _incidentStatus = data['incident_status'] as String? ?? _incidentStatus;
        if (updates.isNotEmpty) _latestUpdate = updates.last;
      });
    } catch (_) {}
  }

  void _startEscalationTimer() {
    _escalationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_escalationSecondsLeft > 0) {
          _escalationSecondsLeft--;
        } else {
          _showEscalationBanner = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _escalateRequest() async {
    setState(() => _escalationTriggered = true);
    if (_incidentId != null) {
      try {
        final url = '${DbService.baseUrl}/incidents/$_incidentId/updates';
        await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message':
                '⚠️ ESCALATION: User has NOT received help after 15 minutes. Immediate action required!',
            'responder_name': null,
            'responder_phone': null,
          }),
        );
      } catch (_) {}
    }
  }

  String _formatEscalationTime() {
    final m = _escalationSecondsLeft ~/ 60;
    final s = _escalationSecondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _markAsResolved() async {
    if (_incidentId == null) return;
    try {
      final url = '${DbService.baseUrl}/incidents/$_incidentId';
      await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': 'Resolved'}),
      );
      setState(() {
        _incidentStatus = 'Resolved';
      });
      if (mounted) context.go('/home');
    } catch (e) {
      debugPrint('Failed to resolve: $e');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Received':     return const Color(0xFFEF4444);
      case 'Acknowledged': return const Color(0xFFF59E0B);
      case 'Dispatched':   return const Color(0xFF3B82F6);
      case 'En Route':     return const Color(0xFF6366F1);
      case 'Resolved':     return const Color(0xFF10B981);
      case 'Closed':       return const Color(0xFF6B7280);
      default:             return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isTransmitting) return _buildTransmitting();

    final statusSteps = ['Received', 'Acknowledged', 'Dispatched', 'En Route', 'Resolved'];
    final stepIdx = statusSteps.indexOf(_incidentStatus).clamp(0, statusSteps.length - 1);
    final responderLat = _latestUpdate?.responderLat;
    final responderLng = _latestUpdate?.responderLng;
    final hasResponder = responderLat != null && responderLng != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          context.go('/home');
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
        body: Stack(
          children: [
            Column(
              children: [
                // ── MAP ───────────────────────────────────────────
                Expanded(
                  flex: 5,
                  child: Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(widget.service.lat, widget.service.lng),
                          initialZoom: 15,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'com.roadsos.app',
                          ),
                          if (hasResponder)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: [
                                    LatLng(responderLat!, responderLng!),
                                    LatLng(widget.service.lat, widget.service.lng),
                                  ],
                                  strokeWidth: 3.5,
                                  color: const Color(0xFF10B981),
                                  pattern: const StrokePattern.dashed(
                                    segments: [8, 6],
                                  ),
                                ),
                              ],
                            ),
                          MarkerLayer(markers: [
                            Marker(
                              point: LatLng(widget.service.lat, widget.service.lng),
                              width: 48,
                              height: 64,
                              alignment: const Alignment(0, -1),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE11D48),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2.5),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x44E11D48),
                                          blurRadius: 12,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.person_pin_circle_rounded,
                                        color: Colors.white, size: 20),
                                  ),
                                  Container(width: 2.5, height: 14, color: const Color(0xFFE11D48)),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0x44E11D48),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (hasResponder)
                              Marker(
                                point: LatLng(responderLat!, responderLng!),
                                width: 48,
                                height: 64,
                                alignment: const Alignment(0, -1),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2.5),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x4410B981),
                                            blurRadius: 12,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(Icons.local_hospital_rounded,
                                          color: Colors.white, size: 20),
                                    ),
                                    Container(width: 2.5, height: 14, color: const Color(0xFF10B981)),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0x4410B981),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ]),
                        ],
                      ),

                      // Map top bar
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, size: 20, color: Color(0xFF0F172A)),
                                onPressed: () => context.go('/home'),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8, height: 8,
                                    decoration: BoxDecoration(
                                      color: _statusColor(_incidentStatus),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _incidentStatus.toUpperCase(),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── BOTTOM PANEL ─────────────────────────────────
                Expanded(
                  flex: 6,
                  child: Container(
                    color: const Color(0xFFF8FAFC),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Status Progress Steps (Zomato-style)
                          Container(
                            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            padding: const EdgeInsets.all(20),
                            decoration: AppTheme.premiumCardDecoration,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SOS Tracking',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.service.name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: List.generate(statusSteps.length, (i) {
                                    final done = i <= stepIdx;
                                    final isLast = i == statusSteps.length - 1;
                                    final stepColor = done ? _statusColor(_incidentStatus) : const Color(0xFFE2E8F0);
                                    return Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              children: [
                                                Container(
                                                  width: 32, height: 32,
                                                  decoration: BoxDecoration(
                                                    color: done ? stepColor.withValues(alpha: 0.1) : const Color(0xFFF8FAFC),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: done ? stepColor : const Color(0xFFE2E8F0),
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    done ? Icons.check_rounded : Icons.circle_outlined,
                                                    size: 14, color: done ? stepColor : const Color(0xFF94A3B8),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  statusSteps[i],
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 10,
                                                    fontWeight: done ? FontWeight.w800 : FontWeight.w600,
                                                    color: done ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!isLast)
                                            Expanded(
                                              child: Container(
                                                height: 2,
                                                margin: const EdgeInsets.only(bottom: 24),
                                                color: i < stepIdx ? _statusColor(_incidentStatus) : const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                          ),

                          // Responder Card (Zomato delivery person card)
                          if (_latestUpdate?.responderName != null || _latestUpdate?.responderPhone != null) ...[
                            _ResponderCard(update: _latestUpdate!),
                          ],

                          // Latest Dispatcher Message
                          if (_latestUpdate != null) ...[
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFDCFCE7),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.notifications_active_outlined, size: 18, color: Color(0xFF16A34A)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Update from Dispatch',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF16A34A),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _latestUpdate!.message,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatTime(_latestUpdate!.createdAt),
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Update History
                          if (_updates.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: AppTheme.premiumCardDecoration,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'DISPATCH UPDATES',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF64748B),
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ..._updates.reversed.map((u) => _UpdateTile(update: u)),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          // Escalation timer / button
                          _EscalationSection(
                            secondsLeft: _escalationSecondsLeft,
                            triggered: _escalationTriggered,
                            showBanner: _showEscalationBanner,
                            timeStr: _formatEscalationTime(),
                            onEscalate: _escalateRequest,
                          ),

                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: SizedBox(
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed: _incidentStatus == 'Resolved' || _incidentStatus == 'Closed' ? null : _markAsResolved,
                                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                label: Text(
                                  'Mark as Resolved',
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildTransmitting() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
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
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Transmitting to\n${widget.service.name}…',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Connecting you with emergency services',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    const SizedBox(
                      width: 140,
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                        child: LinearProgressIndicator(
                          color: AppTheme.primaryGreen,
                          backgroundColor: Color(0xFFE2E8F0),
                          minHeight: 4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Responder Card ─────────────────────────────────────────────────────────
class _ResponderCard extends StatelessWidget {
  const _ResponderCard({required this.update});
  final IncidentUpdate update;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.premiumCardDecoration,
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF2563EB), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  update.responderName ?? 'Emergency Responder',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'On the way to your location',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (update.responderPhone != null)
            GestureDetector(
              onTap: () async {
                final uri = Uri(scheme: 'tel', path: update.responderPhone);
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: const Icon(Icons.call_rounded, color: Color(0xFF10B981), size: 20),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Update Tile ────────────────────────────────────────────────────────────
class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.update});
  final IncidentUpdate update;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10, height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
              ),
              Container(width: 1.5, height: 36, color: const Color(0xFFE2E8F0)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  update.message,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${update.createdAt.hour.toString().padLeft(2, '0')}:${update.createdAt.minute.toString().padLeft(2, '0')}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF94A3B8),
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

// ─── Escalation Section ──────────────────────────────────────────────────────
class _EscalationSection extends StatelessWidget {
  const _EscalationSection({
    required this.secondsLeft,
    required this.triggered,
    required this.showBanner,
    required this.timeStr,
    required this.onEscalate,
  });

  final int secondsLeft;
  final bool triggered;
  final bool showBanner;
  final String timeStr;
  final VoidCallback onEscalate;

  @override
  Widget build(BuildContext context) {
    if (triggered) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFECDD3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFE11D48), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Escalation sent to dispatch center. Help is being urgently re-dispatched.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFE11D48),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (showBanner) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Help hasn\'t arrived yet?',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'It\'s been 15 minutes. Tap below to escalate — dispatch will be immediately alerted about the delay.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFB45309),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onEscalate,
                icon: const Icon(Icons.priority_high_rounded, size: 16, color: Colors.white),
                label: Text(
                  'Send Escalation Alert',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Countdown timer (subtle)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          Text(
            'No help in $timeStr? An escalation option will appear.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF94A3B8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
