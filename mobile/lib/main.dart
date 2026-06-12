import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';

Future<void> main() async {
  // Catch all uncaught Flutter errors — emergency app cannot crash
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[RoadSoS] Flutter error: ${details.exceptionAsString()}');
  };

  // Catch errors on the root isolate
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[RoadSoS] Platform error: $error\n$stack');
    return true; // handled
  };

  runApp(
    ProviderScope(
      child: _AppInitializer(),
    ),
  );
}

/// Handles async initialization before showing [RoadSosApp].
class _AppInitializer extends StatefulWidget {
  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<_AppInitializer> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();

      // Portrait-only — cleaner UX in emergency
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // Warm up SharedPreferences
      await SharedPreferences.getInstance();

      // Request critical permissions early — user sees dialog on first launch
      await _requestPermissions();
    } catch (e) {
      // Log but never crash — fall through to show app anyway
      debugPrint('[RoadSoS] Init error (non-fatal): $e');
    }

    if (mounted) {
      setState(() => _ready = true);
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.location,
        Permission.phone,
        Permission.sms,
      ].request();
    } catch (e) {
      debugPrint('[RoadSoS] Permission request error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFFFAFAFA),
          body: Center(
            child: CircularProgressIndicator(
              color: Color(0xFF16A34A),
            ),
          ),
        ),
      );
    }
    return const RoadSosApp();
  }
}
