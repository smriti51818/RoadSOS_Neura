import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Screen stubs — replaced by actual screens in later modules.
// Each stub ensures the router compiles from Module 1 onwards.
import '../features/ai_assist/ai_screen.dart';
import '../features/home/home_screen.dart';
import '../features/journey/journey_screen.dart';
import '../features/loading/loading_screen.dart';
import '../features/non_emergency/non_emergency_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/results/results_screen.dart';
import '../features/results/incident_status_screen.dart';
import '../features/results/incidents_history_screen.dart';
import '../features/results/incident_details_screen.dart';
import '../features/safety/safety_screen.dart';
import '../features/triage/triage_screen.dart';
import '../features/victims/victims_screen.dart';
import '../features/results/service_details_screen.dart';
import '../data/models/service_model.dart';
import '../data/providers/incidents_provider.dart';

/// Global navigator key for imperative navigation outside widget tree.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// GoRouter provider — Ref is injected for future auth state watching.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: false,
    errorBuilder: (context, state) => _ErrorScreen(error: state.error),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LoadingScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/triage',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return TriageScreen(
            emergencyType: extra?['emergencyType'] as String? ?? 'accident',
          );
        },
      ),
      GoRoute(
        path: '/results',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ResultsScreen(params: extra ?? {});
        },
      ),
      GoRoute(
        path: '/journey',
        builder: (context, state) => const JourneyScreen(),
      ),
      GoRoute(
        path: '/ai',
        builder: (context, state) => const AIScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/victims',
        builder: (context, state) => const VictimsScreen(),
      ),
      GoRoute(
        path: '/safety',
        builder: (context, state) => const SafetyScreen(),
      ),
      GoRoute(
        path: '/non-emergency',
        builder: (context, state) => const NonEmergencyScreen(),
      ),
      GoRoute(
        path: '/service-details',
        builder: (context, state) {
          final service = state.extra as ServiceModel;
          return ServiceDetailsScreen(service: service);
        },
      ),
      GoRoute(
        path: '/incident-status',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>;
          final service = data['service'] as ServiceModel;
          final photos = data['photos'] as List<String>;
          final existingIncident = data['existingIncident'] as IncidentRecord?;
          return IncidentStatusScreen(
            service: service, 
            photos: photos,
            existingIncident: existingIncident,
          );
        },
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const IncidentsHistoryScreen(),
      ),
      GoRoute(
        path: '/incident-details',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          final incident = extra['incident'] as IncidentRecord;
          return IncidentDetailsScreen(incident: incident);
        },
      ),
    ],
  );
});

/// Friendly error screen — never shows a raw exception to the user.
class _ErrorScreen extends StatelessWidget {
  final Exception? error;

  const _ErrorScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 64,
                color: Color(0xFFF59E0B),
              ),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'In an emergency, call 112 immediately.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.go('/'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                ),
                child: const Text('Go to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

