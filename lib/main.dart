import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/background_service.dart';
import 'services/device_identity.dart';
import 'services/firebase_service.dart';
import 'services/theme_controller.dart';
import 'utils/constants.dart';
import 'utils/logger.dart';
import 'utils/theme.dart';

/// Entry point.
///
/// IMPORTANT: We call runApp() IMMEDIATELY with a splash screen, then
/// initialize services in the background. This prevents the white screen
/// that happens when Firebase/Auth initialization hangs (e.g. on slow
/// network or no network).
void main() {
  // Run the app immediately — no awaits before runApp().
  runApp(const LiveLocationShareApp());
}

/// Splash widget shown while services initialize.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.primary,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on, size: 72, color: Colors.white),
              SizedBox(height: 24),
              Text(
                'Live Location Share',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class LiveLocationShareApp extends StatefulWidget {
  const LiveLocationShareApp({super.key});

  @override
  State<LiveLocationShareApp> createState() => _LiveLocationShareAppState();
}

class _LiveLocationShareAppState extends State<LiveLocationShareApp>
    with WidgetsBindingObserver {
  bool _wasOffline = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  /// Initializes all services with timeouts so the app never hangs.
  Future<void> _initializeServices() async {
    try {
      // 1. Lock orientation (fast, no network).
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);

      // 2. Initialize Firebase with 10s timeout.
      AppLogger.info('Initializing Firebase...');
      await Firebase.initializeApp().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AppLogger.error('Firebase initialization timed out after 10s');
          throw TimeoutException('Firebase initialization timed out');
        },
      );
      AppLogger.info('Firebase initialized.');

      // 3. Device Identity (local, fast).
      await DeviceIdentity.instance.initialize();
      AppLogger.info('DeviceIdentity initialized: ${DeviceIdentity.instance.deviceId}');

      // 4. Auth with 15s timeout (needs network for anonymous sign-in).
      AppLogger.info('Initializing Auth...');
      await AuthService.instance.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          AppLogger.error('Auth initialization timed out after 15s');
          return null;
        },
      );
      AppLogger.info('Auth initialized: ${AuthService.instance.uid}');

      // 5. Background service (local, fast).
      try {
        await BackgroundService.instance.initialize();
        AppLogger.info('BackgroundService initialized.');
      } catch (e) {
        AppLogger.error('BackgroundService init failed (non-fatal)', e);
      }

      // 6. Register self device with 10s timeout (needs network).
      if (DeviceIdentity.instance.deviceId != null &&
          AuthService.instance.uid != null) {
        try {
          await FirebaseService.instance.registerSelfDevice(
            deviceId: DeviceIdentity.instance.deviceId!,
            deviceName: DeviceIdentity.instance.deviceName!,
          ).timeout(const Duration(seconds: 10));
          AppLogger.info('Self device registered.');
        } catch (e) {
          AppLogger.error('Could not register self device (non-fatal)', e);
        }
      }

      // 7. Theme controller (local, fast).
      final themeController = ThemeController();
      await themeController.initialize();
      AppLogger.info('ThemeController initialized.');

      // 8. Mark as initialized — triggers UI rebuild.
      if (mounted) {
        setState(() {
          _initialized = true;
          // Provide the theme controller to the Provider tree.
          _themeController = themeController;
        });
      }

      // 9. Start connectivity monitoring.
      Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    } catch (e, st) {
      AppLogger.error('Service initialization failed', e, st);
      // Even on failure, show the app so the user sees something.
      if (mounted) {
        setState(() {
          _initialized = true;
          _themeController = ThemeController();
        });
      }
    }
  }

  late ThemeController _themeController;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FirebaseService.instance.reconnect();
      AuthService.instance.ensureAuthenticated();
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!online) {
      _wasOffline = true;
    } else if (_wasOffline) {
      _wasOffline = false;
      FirebaseService.instance.reconnect();
      AuthService.instance.ensureAuthenticated();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show splash screen while services initialize.
    if (!_initialized) {
      return const _SplashScreen();
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AuthService.instance),
        ChangeNotifierProvider.value(value: _themeController),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeController.mode,
        home: const HomeScreen(),
      ),
    );
  }
}
