import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/providers/incidents_provider.dart';
import '../../data/services/db_service.dart';

class IncidentDetailsScreen extends StatefulWidget {
  final IncidentRecord incident;

  const IncidentDetailsScreen({super.key, required this.incident});

  @override
  State<IncidentDetailsScreen> createState() => _IncidentDetailsScreenState();
}

class _IncidentDetailsScreenState extends State<IncidentDetailsScreen> {
  String _currentStatus = 'Received';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.incident.status;
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final url = '${DbService.baseUrl}/incidents/${widget.incident.id}/updates';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));

      if (!mounted || res.statusCode != 200) {
        setState(() => _isLoading = false);
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _currentStatus = data['incident_status'] as String? ?? _currentStatus;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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
    final i = widget.incident;
    final dateStr = DateFormat('MMMM d, yyyy • h:mm a').format(i.timestamp);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
        title: Text(
          'Incident Details',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
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
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Current Status Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: AppTheme.premiumCardDecoration,
                  child: Column(
                    children: [
                      Text(
                        'CURRENT STATUS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF64748B),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isLoading)
                        const CircularProgressIndicator(color: AppTheme.primaryGreen)
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: _statusColor(_currentStatus).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: _statusColor(_currentStatus).withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _currentStatus.toUpperCase(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _statusColor(_currentStatus),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Details Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: AppTheme.premiumCardDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(Icons.confirmation_number_outlined, 'Incident ID', i.id.split('-').first.toUpperCase()),
                      const Divider(color: Color(0xFFE2E8F0), height: 32),
                      _buildDetailRow(Icons.calendar_today_outlined, 'Date & Time', dateStr),
                      const Divider(color: Color(0xFFE2E8F0), height: 32),
                      _buildDetailRow(Icons.business_outlined, 'Service Requested', i.service.name),
                      const Divider(color: Color(0xFFE2E8F0), height: 32),
                      _buildDetailRow(Icons.camera_alt_outlined, 'Evidence Attached', '${i.photos.length} Photo(s)'),
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryGreen),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
