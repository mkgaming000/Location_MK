import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/live_location.dart';
import '../services/background_service.dart';
import '../services/device_identity.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';
import '../utils/error_messages.dart';
import '../utils/permissions.dart';
import '../widgets/status_card.dart';

/// Share screen — the user-facing control for live location sharing.
///
/// Displays:
///  - Device Name
///  - Current GPS Status (enabled / disabled)
///  - Internet Status (online / offline)
///  - Sharing Status (active / stopped)
///  - Large ON/OFF switch
///  - Start Sharing button + Stop Sharing button
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final LocationService _location = LocationService.instance;
  final BackgroundService _background = BackgroundService.instance;
  final DeviceIdentity _identity = DeviceIdentity.instance;
  final FirebaseService _firebase = FirebaseService.instance;

  bool _isSharing = false;
  bool _isBusy = false;
  bool _gpsEnabled = false;
  bool _internetOnline = true;
  LiveLocation? _lastPublished;

  StreamSubscription<LiveLocation?>? _locationSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _statusRefreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _internetOnline = online);
    });
    // Subscribe to the live location published to Firebase — this is the
    // source of truth for "what coordinates are receivers seeing right now".
    final myId = _identity.deviceId;
    if (myId != null) {
      _locationSub = _firebase.watchLocation(myId).listen((loc) {
        if (mounted) setState(() => _lastPublished = loc);
      });
    }
    // Refresh GPS/sharing status less aggressively (every 10s) — these only
    // change when the user toggles system settings or stops sharing via the
    // notification, which we also catch via didChangeAppLifecycleState.
    _statusRefreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _refreshStatuses());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh when the screen becomes visible (e.g. after returning from
    // system Settings where the user may have enabled GPS).
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatuses());
  }

  Future<void> _refreshStatuses() async {
    final gps = await _location.isGpsEnabled();
    final net = await _location.hasInternet();
    final sharing = await _background.isSharing();
    if (!mounted) return;
    setState(() {
      _gpsEnabled = gps;
      _internetOnline = net;
      _isSharing = sharing;
    });
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _connSub?.cancel();
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _onStartSharing() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      // 1. Permissions
      final result = await AppPermissions.requestSharingPermissions();
      if (!result.granted) {
        _showMessage(result.message, openSettings: result.shouldOpenSettings);
        return;
      }

      // 2. GPS check
      final gpsOn = await _location.isGpsEnabled();
      if (!gpsOn) {
        _showMessage(
          'GPS is disabled. Please enable location services in Settings.',
          openSettings: true,
        );
        return;
      }

      // 3. Network check
      final netOn = await _location.hasInternet();
      if (!netOn) {
        _showMessage(
          'No internet connection. Please connect to Wi-Fi or mobile data.',
        );
        return;
      }

      // 4. Start the foreground service
      await _background.startSharing(
        deviceId: _identity.deviceId!,
        deviceName: _identity.deviceName!,
      );

      if (!mounted) return;
      setState(() => _isSharing = true);
      _showMessage('Live location sharing started.');
    } catch (e) {
      _showMessage('Could not start sharing: ${ErrorMessages.forAny(e)}');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _onStopSharing() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      // stopSharing() invokes the 'stop-sharing' event in the background
      // isolate, which calls markOffline() using the isolate's own auth
      // (which is the UID that registered the device_id). We do NOT call
      // markOffline from the main isolate because its UID may no longer
      // match user_devices/{uid}/device_id (the background isolate
      // overwrites that mapping when it starts).
      await _background.stopSharing(deviceId: _identity.deviceId!);
      if (!mounted) return;
      setState(() {
        _isSharing = false;
        _lastPublished = null;
      });
      _showMessage('Live location sharing stopped.');
    } catch (e) {
      _showMessage('Could not stop sharing: ${ErrorMessages.forAny(e)}');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMessage(String message, {bool openSettings = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        action: openSettings
            ? SnackBarAction(
                label: 'Settings',
                onPressed: () => AppPermissions.openAppSettingsPage(),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final deviceName = _identity.deviceName ?? 'Unknown Device';
    final deviceId = _identity.deviceId ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Share My Location')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Device name card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.smartphone_rounded,
                          color: scheme.onPrimaryContainer,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Device Name',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              deviceName,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: ${_shortId(deviceId)}',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Status cards
              StatusCard(
                icon: Icons.satellite_alt_rounded,
                label: 'GPS Status',
                value: _gpsEnabled ? 'Enabled' : 'Disabled',
                statusColor: _gpsEnabled ? Colors.green : scheme.error,
                subtitle: _gpsEnabled
                    ? 'High accuracy mode recommended'
                    : 'Tap to open Settings',
                onTap: _gpsEnabled
                    ? null
                    : () => AppPermissions.openAppSettingsPage(),
              ),
              const SizedBox(height: 10),
              StatusCard(
                icon: Icons.wifi_rounded,
                label: 'Internet Status',
                value: _internetOnline ? 'Online' : 'Offline',
                statusColor:
                    _internetOnline ? Colors.green : scheme.error,
                subtitle: _internetOnline
                    ? 'Connected to a network'
                    : 'Check your Wi-Fi or mobile data',
              ),
              const SizedBox(height: 10),
              StatusCard(
                icon: _isSharing
                    ? Icons.broadcast_on_rounded
                    : Icons.broadcast_on_personal_rounded,
                label: 'Sharing Status',
                value: _isSharing ? 'Active' : 'Stopped',
                statusColor: _isSharing ? scheme.primary : scheme.outline,
                subtitle: _isSharing
                    ? 'Foreground service is running'
                    : 'Tap the switch below to start',
              ),
              const SizedBox(height: 24),

              // Large ON/OFF switch
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: _isSharing
                      ? scheme.primary.withValues(alpha: 0.10)
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isSharing
                        ? scheme.primary.withValues(alpha: 0.4)
                        : scheme.outlineVariant,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Live Sharing',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _isSharing ? 'ON' : 'OFF',
                              style: textTheme.bodyMedium?.copyWith(
                                color: _isSharing
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _isSharing,
                          onChanged: _isBusy
                              ? null
                              : (v) =>
                                  v ? _onStartSharing() : _onStopSharing(),
                        ),
                      ],
                    ),
                    if (_isSharing && _lastPublished != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.my_location_rounded,
                                size: 16, color: scheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_lastPublished!.latitude.toStringAsFixed(6)}, '
                                '${_lastPublished!.longitude.toStringAsFixed(6)}',
                                style: textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action buttons
              if (!_isSharing)
                FilledButton.icon(
                  onPressed: _isBusy ? null : _onStartSharing,
                  icon: _isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Sharing'),
                )
              else
                FilledButton.icon(
                  onPressed: _isBusy ? null : _onStopSharing,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  icon: _isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.stop_rounded),
                  label: const Text('Stop Sharing'),
                ),
              const SizedBox(height: 16),
              Text(
                'When sharing is active, a persistent notification will appear. '
                'You can stop sharing at any time from the notification or this screen. '
                'Sharing continues even when the app is minimized or the screen is off.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 4)}';
  }
}
