import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../services/location_service.dart';
import 'journey_provider.dart';

class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key});

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  final _destinationController = TextEditingController();
  final _contactController = TextEditingController();
  final _mapController = MapController();

  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  bool _isLoading = false;
  bool _isReverseGeocoding = false;
  bool _isLocating = true;
  Timer? _debounce;

  // GPS state
  double _userLat = 28.6139;
  double _userLng = 77.2090;
  double _bearing = 0.0; // direction of travel in degrees
  StreamSubscription<Position>? _positionStream;

  // Pin-drop state (planning mode)
  LatLng? _pickedPin;
  String? _pickedAddress;

  // Navigation mode: whether camera is locked to user position
  bool _cameraLocked = true;

  // Journey summary snapshot (captured just before stop)
  _JourneySummaryData? _summarySnapshot;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final state = ref.read(journeyNotifierProvider);
      if (state.isActive && state.startedAt != null && mounted) {
        setState(() => _elapsed = DateTime.now().difference(state.startedAt!));
      }
    });
  }

  Future<void> _initLocation() async {
    final svc = ref.read(locationServiceProvider);
    final pos = await svc.getCurrentLocation();
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
        _bearing = pos.heading;
        _isLocating = false;
      });
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
    } else {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Start a high-frequency position stream for navigation mode
  void _startNavStream() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // update every 5 metres
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
        if (pos.speed > 0.5) _bearing = pos.heading; // only update when moving
      });
      // Auto-follow camera in navigation mode
      if (_cameraLocked) {
        _mapController.moveAndRotate(
          LatLng(pos.latitude, pos.longitude),
          17.0, // zoom in for nav
          0,    // keep map north-up (set to -_bearing for heading-up)
        );
      }
      // Update journey provider
      ref
          .read(journeyNotifierProvider.notifier)
          .updateLocation(pos.latitude, pos.longitude);
    });
  }

  void _stopNavStream() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _contactController.dispose();
    _elapsedTimer?.cancel();
    _debounce?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  // ── Reverse geocode tapped point ────────────────────────────────────────────
  // Uses Nominatim (free, no API key) as primary geocoder.
  // Falls back to Geoapify if a key is configured, then to raw coordinates.
  Future<void> _reverseGeocode(LatLng point) async {
    setState(() {
      _pickedPin = point;
      _isReverseGeocoding = true;
      _pickedAddress = null;
    });

    // ── 1. Try Nominatim (OpenStreetMap — free, no key needed) ──────────────
    try {
      final nominatimUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${point.latitude}&lon=${point.longitude}'
        '&format=json&addressdetails=1',
      );
      final res = await http.get(nominatimUrl, headers: {
        'User-Agent': 'RoadSOS/1.0 (roadsos.app)',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        final displayName = data?['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          if (mounted) {
            setState(() {
              _pickedAddress = displayName;
              _isReverseGeocoding = false;
            });
            _destinationController.text = displayName;
          }
          return;
        }
      }
    } catch (_) {}

    // ── 2. Try Geoapify if a real API key is configured ──────────────────────
    final geoKey = AppConstants.geoapifyApiKey;
    if (geoKey.isNotEmpty &&
        !geoKey.startsWith('YOUR_') &&
        geoKey != 'your-geoapify-api-key') {
      try {
        final url = Uri.parse(
          'https://api.geoapify.com/v1/geocode/reverse'
          '?lat=${point.latitude}&lon=${point.longitude}'
          '&apiKey=$geoKey',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final features = data['features'] as List?;
          if (features != null && features.isNotEmpty) {
            final address =
                features[0]['properties']['formatted'] as String? ?? '';
            if (address.isNotEmpty && mounted) {
              setState(() {
                _pickedAddress = address;
                _isReverseGeocoding = false;
              });
              _destinationController.text = address;
              return;
            }
          }
        }
      } catch (_) {}
    }

    // ── 3. Final fallback: raw coordinates ───────────────────────────────────
    if (mounted) {
      final coords =
          '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
      setState(() {
        _pickedAddress = coords;
        _isReverseGeocoding = false;
      });
      _destinationController.text = coords;
    }
  }

  Future<Iterable<String>> _fetchSuggestions(String query) async {
    if (query.length < 3) return const Iterable<String>.empty();
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    final completer = Completer<Iterable<String>>();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await ref
          .read(journeyNotifierProvider.notifier)
          .fetchLocationSuggestions(query);
      if (!completer.isCompleted) completer.complete(results);
    });
    return completer.future;
  }

  Future<void> _startJourney() async {
    final dest = _destinationController.text.trim();
    if (dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter or pick a destination',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    setState(() => _isLoading = true);
    await ref.read(journeyNotifierProvider.notifier).startJourney(
          destination: dest,
          shareEtaWith: _contactController.text.trim().isEmpty
              ? null
              : _contactController.text.trim(),
        );
    if (mounted) {
      setState(() {
        _isLoading = false;
        _cameraLocked = true;
      });
      // Switch to high-frequency nav stream
      _startNavStream();
      // Zoom to show full route
      final state = ref.read(journeyNotifierProvider);
      if (state.routeGeometry != null && state.routeGeometry!.length >= 2) {
        await Future.delayed(const Duration(milliseconds: 300));
        _fitRoute(state.routeGeometry!);
        await Future.delayed(const Duration(seconds: 2));
        // Then zoom to nav view on user
        _mapController.move(LatLng(_userLat, _userLng), 17.0);
      }
    }
  }

  void _fitRoute(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    // Approximate zoom to fit the bounding box
    final latDelta = maxLat - minLat;
    final lngDelta = maxLng - minLng;
    final delta = math.max(latDelta, lngDelta);
    final zoom = delta < 0.01
        ? 15.0
        : delta < 0.05
            ? 13.0
            : delta < 0.2
                ? 11.0
                : delta < 1.0
                    ? 9.0
                    : 7.0;
    _mapController.move(center, zoom);
  }

  Future<void> _stopJourney() async {
    // Capture summary BEFORE stopping (state resets after stop)
    final state = ref.read(journeyNotifierProvider);
    _summarySnapshot = _JourneySummaryData(
      destination: state.destination,
      elapsed: _elapsed,
      totalDistanceKm: state.totalDistanceKm,
      etaMinutes: state.etaMinutes,
      waypointsReached: state.reachedWaypoints,
      waypointsTotal: state.waypoints.length,
      hazardsDetected: state.blackspots.length,
      startedAt: state.startedAt,
    );

    _stopNavStream();
    await ref.read(journeyNotifierProvider.notifier).stopJourney();

    if (mounted) {
      setState(() {
        _elapsed = Duration.zero;
        _cameraLocked = true;
      });
      _mapController.move(LatLng(_userLat, _userLng), 14.0);
      // Show summary sheet
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _showSummarySheet();
    }
  }

  void _showSummarySheet() {
    final snapshot = _summarySnapshot;
    if (snapshot == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false, // prevent accidental swipe-down without feedback
      builder: (_) => _JourneySummarySheet(summary: snapshot),
    ).then((_) {
      // After sheet closes (Skip or Submit) — go to Home
      if (mounted) context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(journeyNotifierProvider);
    final lat = state.currentLat ?? _userLat;
    final lng = state.currentLng ?? _userLng;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    final routePoints = state.isActive
        ? (state.routeGeometry ??
            [
              LatLng(lat, lng),
              ...state.waypoints.map((w) => LatLng(w.lat, w.lng)),
            ])
        : <LatLng>[];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Full-screen map ───────────────────────────────────────────────
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(lat, lng),
                initialZoom: state.isActive ? 17.0 : 15.0,
                onTap: state.isActive
                    ? (_, __) {
                        // Unlock camera so user can pan freely
                        setState(() => _cameraLocked = false);
                      }
                    : (_, point) => _reverseGeocode(point),
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture && state.isActive && _cameraLocked) {
                    setState(() => _cameraLocked = false);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.roadsos.app',
                ),

                // Route polyline
                if (routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      // Route shadow
                      Polyline(
                        points: routePoints,
                        strokeWidth: 8,
                        color: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
                      ),
                      // Main route line
                      Polyline(
                        points: routePoints,
                        strokeWidth: 5,
                        color: const Color(0xFF2563EB),
                      ),
                    ],
                  ),

                MarkerLayer(
                  markers: [
                    // ── User location marker ──────────────────────────────
                    Marker(
                      point: LatLng(lat, lng),
                      width: state.isActive ? 48 : 28,
                      height: state.isActive ? 48 : 28,
                      child: state.isActive
                          ? _CarMarker(bearing: _bearing)
                          : _BlueDot(),
                    ),

                    // ── Destination pin ───────────────────────────────────
                    if (_pickedPin != null && !state.isActive)
                      Marker(
                        point: _pickedPin!,
                        width: 40,
                        height: 52,
                        alignment: const Alignment(0, -1),
                        child: const _DestinationPin(color: Color(0xFFE11D48)),
                      ),

                    if (state.isActive && state.waypoints.length >= 2)
                      Marker(
                        point: LatLng(
                          state.waypoints.last.lat,
                          state.waypoints.last.lng,
                        ),
                        width: 40,
                        height: 52,
                        alignment: const Alignment(0, -1),
                        child: const _DestinationPin(color: Color(0xFFE11D48)),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Top bar (safe area) ───────────────────────────────────────────
          Positioned(
            top: topPad + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _FloatingIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () async {
                    if (state.isActive) {
                      // Stop journey → shows summary → .then() goes to home
                      await _stopJourney();
                    } else {
                      context.go('/home');
                    }
                  },
                ),
                const Spacer(),
                if (state.isActive) ...[
                  // Re-centre lock button
                  _FloatingIconButton(
                    icon: _cameraLocked
                        ? Icons.navigation_rounded
                        : Icons.gps_fixed_rounded,
                    color: _cameraLocked
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF64748B),
                    onTap: () {
                      setState(() => _cameraLocked = true);
                      _mapController.move(LatLng(lat, lng), 17.0);
                    },
                  ),
                ],
              ],
            ),
          ),

          // ── Planning mode overlays ────────────────────────────────────────
          if (!state.isActive) ...[
            // Hint pill
            Positioned(
              top: topPad + 68,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: _isLocating
                      ? _HintPill(
                          key: const ValueKey('loc'),
                          icon: Icons.gps_not_fixed_rounded,
                          label: 'Locating you…',
                          iconColor: const Color(0xFFF59E0B),
                          showSpinner: true,
                        )
                      : _HintPill(
                          key: const ValueKey('tap'),
                          icon: Icons.touch_app_rounded,
                          label: 'Tap map to pick destination',
                          iconColor: const Color(0xFF2563EB),
                        ),
                ),
              ),
            ),

            // Reverse geocoding pill
            if (_isReverseGeocoding)
              Positioned(
                bottom: botPad + 330,
                left: 0,
                right: 0,
                child: const Center(child: _LoadingPill()),
              ),
          ],

          // ── GPS re-centre button (planning mode) ──────────────────────────
          if (!state.isActive)
            Positioned(
              right: 14,
              bottom: botPad + 310,
              child: _FloatingIconButton(
                icon: Icons.my_location_rounded,
                color: const Color(0xFF2563EB),
                onTap: () =>
                    _mapController.move(LatLng(_userLat, _userLng), 15.0),
              ),
            ),

          // ── Bottom sheet ──────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
              child: state.isActive
                  ? _NavSheet(
                      key: const ValueKey('nav'),
                      state: state,
                      elapsed: _elapsed,
                      botPad: botPad,
                      onStop: _stopJourney,
                    )
                  : _PlanSheet(
                      key: const ValueKey('plan'),
                      destinationController: _destinationController,
                      contactController: _contactController,
                      isLoading: _isLoading,
                      pickedAddress: _pickedPin != null ? _pickedAddress : null,
                      botPad: botPad,
                      onSuggest: _fetchSuggestions,
                      onStart: _startJourney,
                      onClearPin: () => setState(() {
                        _pickedPin = null;
                        _pickedAddress = null;
                        _destinationController.clear();
                      }),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MARKERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Rotating car/arrow marker for navigation mode
class _CarMarker extends StatelessWidget {
  const _CarMarker({required this.bearing});
  final double bearing;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: bearing * math.pi / 180,
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 12, spreadRadius: 2),
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: const Icon(
          Icons.navigation_rounded,
          color: Color(0xFF2563EB),
          size: 28,
        ),
      ),
    );
  }
}

/// Simple blue dot for planning mode
class _BlueDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2563EB).withValues(alpha: 0.18),
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF2563EB),
          ),
        ),
      ),
    );
  }
}

class _DestinationPin extends StatelessWidget {
  const _DestinationPin({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))
            ],
          ),
          child: const Icon(Icons.flag_rounded, color: Colors.white, size: 14),
        ),
        Container(
          width: 2.5,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  FLOATING UI ELEMENTS
// ═══════════════════════════════════════════════════════════════════════════════

class _FloatingIconButton extends StatelessWidget {
  const _FloatingIconButton({
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFF0F172A),
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
                color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3))
          ],
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({
    super.key,
    required this.icon,
    required this.label,
    required this.iconColor,
    this.showSpinner = false,
  });
  final IconData icon;
  final String label;
  final Color iconColor;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(color: iconColor, strokeWidth: 2),
            )
          else
            Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 7),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              )),
        ],
      ),
    );
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Getting address…',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PLAN SHEET (before journey starts)
// ═══════════════════════════════════════════════════════════════════════════════

class _PlanSheet extends StatelessWidget {
  const _PlanSheet({
    super.key,
    required this.destinationController,
    required this.contactController,
    required this.isLoading,
    required this.pickedAddress,
    required this.botPad,
    required this.onSuggest,
    required this.onStart,
    required this.onClearPin,
  });

  final TextEditingController destinationController;
  final TextEditingController contactController;
  final bool isLoading;
  final String? pickedAddress;
  final double botPad;
  final Future<Iterable<String>> Function(String) onSuggest;
  final VoidCallback onStart;
  final VoidCallback onClearPin;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, botPad + 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('Where to?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.4,
                )),
            const SizedBox(height: 4),
            Text('Type or tap the map to pick a destination',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B),
                )),
            const SizedBox(height: 14),

            // Picked-from-map chip
            if (pickedAddress != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_pin,
                        color: Color(0xFF2563EB), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(pickedAddress!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E40AF),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    GestureDetector(
                      onTap: onClearPin,
                      child: const Icon(Icons.close_rounded,
                          color: Color(0xFF94A3B8), size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Route input card
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  // Origin
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                              color: Color(0xFF10B981), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 12),
                        Text('My Location',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF334155),
                            )),
                        const Spacer(),
                        Text('GPS Locked',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981),
                            )),
                        const SizedBox(width: 4),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                              color: Color(0xFF10B981), shape: BoxShape.circle),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  // Destination autocomplete
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE11D48),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Autocomplete<String>(
                            optionsBuilder: (tv) => onSuggest(tv.text),
                            onSelected: (s) =>
                                destinationController.text = s,
                            fieldViewBuilder:
                                (ctx, ctrl, focusNode, onSubmit) {
                              if (destinationController.text.isNotEmpty &&
                                  ctrl.text.isEmpty) {
                                ctrl.text = destinationController.text;
                              }
                              return TextField(
                                controller: ctrl,
                                focusNode: focusNode,
                                onChanged: (v) =>
                                    destinationController.text = v,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Where to?',
                                  hintStyle: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFF94A3B8),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                ),
                              );
                            },
                            optionsViewBuilder: (ctx, onSelected, options) =>
                                Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 8,
                                borderRadius: BorderRadius.circular(14),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                      maxWidth: 320, maxHeight: 200),
                                  child: ListView.separated(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (ctx, i) {
                                      final o = options.elementAt(i);
                                      return ListTile(
                                        dense: true,
                                        leading: const Icon(
                                            Icons.location_on_outlined,
                                            size: 18,
                                            color: Color(0xFF64748B)),
                                        title: Text(o,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF0F172A),
                                            )),
                                        onTap: () => onSelected(o),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ETA sharing (collapsible)
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                leading: const Icon(Icons.security_outlined,
                    size: 16, color: Color(0xFF64748B)),
                title: Text('Safety — ETA Sharing (optional)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    )),
                children: [
                  TextField(
                    controller: contactController,
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: 'Phone number',
                      hintStyle: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF94A3B8), fontSize: 13),
                      prefixIcon: const Icon(Icons.phone_outlined,
                          size: 16, color: Color(0xFF64748B)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF2563EB), width: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Start button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF93C5FD),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.navigation_rounded, size: 20),
                label: Text(
                  isLoading ? 'Starting navigation…' : 'Start Navigation',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  NAV SHEET (active navigation — compact Google Maps style)
// ═══════════════════════════════════════════════════════════════════════════════

class _NavSheet extends StatelessWidget {
  const _NavSheet({
    super.key,
    required this.state,
    required this.elapsed,
    required this.botPad,
    required this.onStop,
  });

  final JourneyState state;
  final Duration elapsed;
  final double botPad;
  final VoidCallback onStop;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, botPad + 84),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),

            // Hazard warning
            if (state.hasBlackspots)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFD97706), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${state.blackspots.length} hazard(s) ahead — ${state.blackspots.first.reason}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Destination row
            Row(
              children: [
                const _DestinationPin(color: Color(0xFFE11D48)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Navigating to',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF94A3B8),
                            letterSpacing: 0.4,
                          )),
                      Text(
                        state.destination,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Stats row
            Row(
              children: [
                _NavStat(
                  label: 'Elapsed',
                  value: _fmt(elapsed),
                  icon: Icons.timer_outlined,
                ),
                const SizedBox(width: 10),
                if (state.etaMinutes != null)
                  _NavStat(
                    label: 'ETA',
                    value: '~${state.etaMinutes} min',
                    icon: Icons.access_time_rounded,
                    highlight: true,
                  ),
                if (state.etaMinutes != null) const SizedBox(width: 10),
                if (state.totalDistanceKm != null)
                  _NavStat(
                    label: 'Distance',
                    value: '${state.totalDistanceKm!.toStringAsFixed(1)} km',
                    icon: Icons.route_outlined,
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // End journey
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFE4E6),
                  foregroundColor: const Color(0xFFE11D48),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.stop_circle_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text('End Journey',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavStat extends StatelessWidget {
  const _NavStat({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFFEFF6FF)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlight
                ? const Color(0xFFBFDBFE)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 11,
                    color: highlight
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text(label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: highlight
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF94A3B8),
                      letterSpacing: 0.3,
                    )),
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: highlight
                      ? const Color(0xFF1D4ED8)
                      : const Color(0xFF0F172A),
                )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  JOURNEY SUMMARY DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _JourneySummaryData {
  _JourneySummaryData({
    required this.destination,
    required this.elapsed,
    required this.totalDistanceKm,
    required this.etaMinutes,
    required this.waypointsReached,
    required this.waypointsTotal,
    required this.hazardsDetected,
    required this.startedAt,
  });

  final String destination;
  final Duration elapsed;
  final double? totalDistanceKm;
  final int? etaMinutes;
  final int waypointsReached;
  final int waypointsTotal;
  final int hazardsDetected;
  final DateTime? startedAt;

  String get formattedDuration {
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h}h ${m}m' : '${elapsed.inMinutes}m ${s}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  JOURNEY SUMMARY SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _JourneySummarySheet extends StatefulWidget {
  const _JourneySummarySheet({required this.summary});
  final _JourneySummaryData summary;

  @override
  State<_JourneySummarySheet> createState() => _JourneySummarySheetState();
}

class _JourneySummarySheetState extends State<_JourneySummarySheet> {
  int _rating = 0;
  final Set<String> _selectedIssues = {};
  final _commentController = TextEditingController();
  bool _submitted = false;

  static const _issues = [
    ('🚦', 'Heavy Traffic'),
    ('🕳️', 'Bad Roads'),
    ('⚠️', 'Road Hazard'),
    ('🌧️', 'Poor Weather'),
    ('🏗️', 'Construction'),
    ('✅', 'No Issues'),
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _submitted = true);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: _submitted ? _ThankYouView(botPad: botPad) : _FeedbackView(
        summary: widget.summary,
        rating: _rating,
        selectedIssues: _selectedIssues,
        commentController: _commentController,
        botPad: botPad,
        onRatingChanged: (r) => setState(() => _rating = r),
        onIssueToggled: (issue) => setState(() {
          if (issue == '✅ No Issues') {
            _selectedIssues
              ..clear()
              ..add(issue);
          } else {
            _selectedIssues.remove('✅ No Issues');
            if (_selectedIssues.contains(issue)) {
              _selectedIssues.remove(issue);
            } else {
              _selectedIssues.add(issue);
            }
          }
        }),
        onSubmit: _submit,
        issues: _issues,
      ),
    );
  }
}

// ── Thank-you view ────────────────────────────────────────────────────────────

class _ThankYouView extends StatelessWidget {
  const _ThankYouView({required this.botPad});
  final double botPad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 40, 24, botPad + 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: Color(0xFF10B981), size: 38),
          ),
          const SizedBox(height: 16),
          Text('Thanks for the feedback!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              )),
          const SizedBox(height: 8),
          Text('Your report helps improve safety for everyone on the road.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              )),
        ],
      ),
    );
  }
}

// ── Feedback view ─────────────────────────────────────────────────────────────

class _FeedbackView extends StatelessWidget {
  const _FeedbackView({
    required this.summary,
    required this.rating,
    required this.selectedIssues,
    required this.commentController,
    required this.botPad,
    required this.onRatingChanged,
    required this.onIssueToggled,
    required this.onSubmit,
    required this.issues,
  });

  final _JourneySummaryData summary;
  final int rating;
  final Set<String> selectedIssues;
  final TextEditingController commentController;
  final double botPad;
  final void Function(int) onRatingChanged;
  final void Function(String) onIssueToggled;
  final VoidCallback onSubmit;
  final List<(String, String)> issues;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 14, 20, botPad + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.directions_car_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Journey Complete!',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.4,
                        )),
                    Text(summary.destination,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Stats grid ───────────────────────────────────────────────────
          Row(
            children: [
              _SummaryStatCard(
                icon: Icons.timer_rounded,
                label: 'Duration',
                value: summary.formattedDuration,
                color: const Color(0xFF2563EB),
              ),
              const SizedBox(width: 10),
              _SummaryStatCard(
                icon: Icons.route_rounded,
                label: 'Distance',
                value: summary.totalDistanceKm != null
                    ? '${summary.totalDistanceKm!.toStringAsFixed(1)} km'
                    : '—',
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SummaryStatCard(
                icon: Icons.access_time_rounded,
                label: 'ETA was',
                value: summary.etaMinutes != null
                    ? '~${summary.etaMinutes} min'
                    : '—',
                color: const Color(0xFF0891B2),
              ),
              const SizedBox(width: 10),
              _SummaryStatCard(
                icon: Icons.warning_amber_rounded,
                label: 'Hazards',
                value: summary.hazardsDetected == 0
                    ? 'None detected'
                    : '${summary.hazardsDetected} detected',
                color: summary.hazardsDetected == 0
                    ? const Color(0xFF10B981)
                    : const Color(0xFFD97706),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Divider ──────────────────────────────────────────────────────
          const Divider(color: Color(0xFFF1F5F9), thickness: 1.5),
          const SizedBox(height: 16),

          // ── Star rating ──────────────────────────────────────────────────
          Text('How was your journey?',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              )),
          const SizedBox(height: 4),
          Text('Rate your overall experience',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF94A3B8))),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < rating;
              return GestureDetector(
                onTap: () => onRatingChanged(i + 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: filled
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFCBD5E1),
                    size: filled ? 40 : 36,
                  ),
                ),
              );
            }),
          ),
          if (rating > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                ['', 'Terrible 😞', 'Poor 😕', 'OK 😐', 'Good 😊',
                    'Excellent 🌟'][rating],
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // ── Issue chips ──────────────────────────────────────────────────
          Text('Any issues on the way?',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              )),
          const SizedBox(height: 4),
          Text('Select all that apply',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF94A3B8))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: issues.map((issue) {
              final label = '${issue.$1} ${issue.$2}';
              final selected = selectedIssues.contains(label);
              return GestureDetector(
                onTap: () => onIssueToggled(label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFE2E8F0),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? Colors.white
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // ── Comment box ──────────────────────────────────────────────────
          Text('Tell us more (optional)',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              )),
          const SizedBox(height: 10),
          TextField(
            controller: commentController,
            maxLines: 3,
            minLines: 3,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText:
                  'e.g. Road near NH8 was waterlogged, avoid after 9pm…',
              hintStyle: GoogleFonts.plusJakartaSans(
                color: const Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: Color(0xFF2563EB), width: 1.5)),
            ),
          ),
          const SizedBox(height: 20),

          // ── Submit button ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text('Submit Feedback',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Skip',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF94A3B8),
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary stat card ─────────────────────────────────────────────────────────

class _SummaryStatCard extends StatelessWidget {
  const _SummaryStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Text(label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.8),
                    )),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                )),
          ],
        ),
      ),
    );
  }
}
