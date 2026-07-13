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
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait orientation for a clean mobile UX.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  // Initialize Firebase first — all services depend on it.
  await Firebase.initializeApp();

  // Initialize core services in the correct order.
  await DeviceIdentity.instance.initialize();
  await AuthService.instance.initialize();
  await BackgroundService.instance.initialize();

  // Register the current device in the database so DB rules can identify it.
  if (DeviceIdentity.instance.deviceId != null &&
      AuthService.instance.uid != null) {
    try {
      await FirebaseService.instance.registerSelfDevice(
        deviceId: DeviceIdentity.instance.deviceId!,
        deviceName: DeviceIdentity.instance.deviceName!,
      );
    } catch (e) {
      debugPrint('Could not register self device: $e');
    }
  }

  // Load the persisted theme mode before launching.
  final themeController = ThemeController();
  await themeController.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AuthService.instance),
        ChangeNotifierProvider.value(value: themeController),
      ],
      child: const LiveLocationShareApp(),
    ),
  );
}

class LiveLocationShareApp extends StatefulWidget {
  const LiveLocationShareApp({super.key});

  @override
  State<LiveLocationShareApp> createState() => _LiveLocationShareAppState();
}

class _LiveLocationShareAppState extends State<LiveLocationShareApp>
    with WidgetsBindingObserver {
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app returns to the foreground, force a Firebase reconnect
    // and refresh the auth token. This handles the case where the OS put
    // the network stack to sleep while the app was backgrounded.
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
      // Network restored — reconnect Firebase.
      FirebaseService.instance.reconnect();
      AuthService.instance.ensureAuthenticated();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeController>().mode;
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
