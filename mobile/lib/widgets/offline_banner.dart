// lib/widgets/offline_banner.dart
// Module 5 — Animated offline/online status banner.
//
// Watches ConnectivityService and animates in when offline, out when online.
// Uses AnimatedSize for a smooth height-collapse effect.
// ConsumerStatefulWidget to subscribe to the connectivity stream directly
// without adding a separate StreamProvider.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../services/connectivity_service.dart';

class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key});

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  late bool _isOnline;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(connectivityServiceProvider);
    _isOnline = svc.isOnline;
    _sub = svc.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _isOnline
          ? const SizedBox.shrink()
          : _BannerContent(),
    );
  }
}

class _BannerContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.warningAmber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppTheme.warningAmber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off,
            size: 16,
            color: AppTheme.warningAmber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — using local data. Emergency numbers still work.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.warningAmber,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
