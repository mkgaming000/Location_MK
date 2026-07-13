import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/device.dart';
import '../models/live_location.dart';
import '../services/device_identity.dart';
import '../services/firebase_service.dart';
import '../utils/error_messages.dart';
import '../widgets/copy_button.dart';
import '../widgets/device_card.dart';
import '../widgets/states.dart';
import 'pair_device_screen.dart';

/// Receiver screen — shows the list of paired devices and the live location
/// of the selected one.
class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> {
  final FirebaseService _firebase = FirebaseService.instance;
  final DeviceIdentity _identity = DeviceIdentity.instance;

  List<Device> _devices = [];
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<List<Device>>? _devicesSub;

  @override
  void initState() {
    super.initState();
    _subscribeToDevices();
  }

  void _subscribeToDevices() {
    final myId = _identity.deviceId;
    if (myId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Device not initialized. Please restart the app.';
      });
      return;
    }
    _devicesSub?.cancel();
    _devicesSub = _firebase.watchPairedDevices(myId).listen(
      (devices) {
        if (mounted) {
          setState(() {
            _devices = devices;
            _isLoading = false;
            _errorMessage = null;
          });
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = ErrorMessages.forAny(error);
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Location'),
        actions: [
          IconButton(
            tooltip: 'Pair a Device',
            icon: const Icon(Icons.person_add_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PairDeviceScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(scheme, textTheme),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme, TextTheme textTheme) {
    if (_isLoading) {
      return const LoadingState(message: 'Loading paired devices...');
    }
    if (_errorMessage != null) {
      return ErrorState(
        message: _errorMessage!,
        onRetry: () {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
          _subscribeToDevices();
        },
      );
    }
    if (_devices.isEmpty) {
      return EmptyState(
        icon: Icons.devices_other_rounded,
        title: 'No Paired Devices',
        message: 'Pair a device using its Device ID or QR code to see its '
            'live location here.',
        actionLabel: 'Pair a Device',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PairDeviceScreen()),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (_identity.deviceId != null) {
          try {
            final devices =
                await _firebase.getPairedDevices(_identity.deviceId!);
            if (mounted) setState(() => _devices = devices);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ErrorMessages.forAny(e))),
              );
            }
          }
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DeviceEntry(device: device),
          );
        },
      ),
    );
  }
}

/// A single paired-device entry. Shows the device card and, when tapped,
/// expands into a detail view with the live location and action buttons.
class _DeviceEntry extends StatefulWidget {
  const _DeviceEntry({required this.device});
  final Device device;

  @override
  State<_DeviceEntry> createState() => _DeviceEntryState();
}

class _DeviceEntryState extends State<_DeviceEntry>
    with SingleTickerProviderStateMixin {
  LiveLocation? _location;
  StreamSubscription<LiveLocation?>? _sub;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseService.instance
        .watchLocation(widget.device.id)
        .listen((loc) {
      if (mounted) setState(() => _location = loc);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DeviceCard(
          device: widget.device,
          location: _location,
          onTap: () => setState(() => _expanded = !_expanded),
          onLongPress: () => _showRemoveDialog(context),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? _DetailPanel(
                  location: _location,
                  device: widget.device,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Future<void> _showRemoveDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device?'),
        content: Text(
          'Remove "${widget.device.name}" from your paired devices? '
          'You will no longer be able to see its location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await FirebaseService.instance.removePairedDevice(
          myDeviceId: DeviceIdentity.instance.deviceId!,
          theirDeviceId: widget.device.id,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.device.name} removed.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorMessages.forAny(e))),
          );
        }
      }
    }
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.location, required this.device});

  final LiveLocation? location;
  final Device device;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (location == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.location_off_rounded,
                    size: 48, color: scheme.outline),
                const SizedBox(height: 12),
                Text(
                  'No location shared',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This device has not started sharing its location yet, or '
                  'has not paired with you.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final loc = location!;
    final isOnline = loc.online && !loc.isStale;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status banner
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: (isOnline ? Colors.green : scheme.outline)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: isOnline ? Colors.green : scheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: textTheme.labelLarge?.copyWith(
                        color: isOnline ? Colors.green : scheme.outline,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatTime(loc.timestamp),
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: 'Latitude',
                value: loc.latitude.toStringAsFixed(6),
                icon: Icons.explore_rounded,
              ),
              const Divider(height: 24),
              _DetailRow(
                label: 'Longitude',
                value: loc.longitude.toStringAsFixed(6),
                icon: Icons.explore_rounded,
              ),
              const Divider(height: 24),
              _DetailRow(
                label: 'Accuracy',
                value: '± ${loc.accuracy.toStringAsFixed(1)} m',
                icon: Icons.gps_fixed_rounded,
              ),
              const Divider(height: 24),
              _DetailRow(
                label: 'Last Updated',
                value: _formatTime(loc.timestamp),
                icon: Icons.update_rounded,
              ),
              const SizedBox(height: 20),
              CopyButton(text: loc.coordinatesText),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openInMaps(loc),
                      icon: const Icon(Icons.map_rounded),
                      label: const Text('Open Maps'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareCoordinates(loc),
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
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

  String _formatTime(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _openInMaps(LiveLocation loc) async {
    // Launch Google Maps in navigation mode using the latest coordinates.
    // Fall back to the web URL if the Google Maps app is not installed.
    final navUri = Uri.parse(
      'google.navigation:q=${loc.latitude},${loc.longitude}&mode=d',
    );
    final geoUri = Uri.parse('geo:${loc.latitude},${loc.longitude}');
    final webUri = Uri.parse(
      'https://www.google.com/maps?q=${loc.latitude},${loc.longitude}',
    );
    try {
      if (await canLaunchUrl(navUri)) {
        await launchUrl(navUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // fall through to geo URI
    }
    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // fall through to web URL
    }
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch maps: $e');
    }
  }

  Future<void> _shareCoordinates(LiveLocation loc) async {
    await Share.share(
      'Live location of ${device.name}: '
      '${loc.latitude},${loc.longitude}\n'
      'https://www.google.com/maps?q=${loc.latitude},${loc.longitude}',
      subject: 'Live Location',
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 12),
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        SelectableText(
          value,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
