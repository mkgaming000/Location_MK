import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/device_identity.dart';
import '../services/firebase_service.dart';
import '../services/theme_controller.dart';
import '../utils/constants.dart';
import '../utils/error_messages.dart';
import 'pair_device_screen.dart';
import 'receiver_screen.dart';
import 'share_screen.dart';

/// Home screen — the entry point of the app.
///
/// Displays:
///  - The app title and the user's own Device ID (so they can share it)
///  - Two large cards: "Share My Location" and "Receive Location"
///  - A small "Pair a Device" entry point at the bottom
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final deviceId = DeviceIdentity.instance.deviceId;
    final deviceName = DeviceIdentity.instance.deviceName;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            tooltip: 'Toggle Theme',
            icon: Icon(_themeIcon(context)),
            onPressed: () => context.read<ThemeController>().cycle(),
          ),
          IconButton(
            tooltip: 'Pair a Device',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => _navigateToPair(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MyDeviceCard(
                deviceId: deviceId,
                deviceName: deviceName,
                onRename: _editDeviceName,
              ),
              const SizedBox(height: 24),
              Text(
                'What would you like to do?',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _BigActionCard(
                icon: Icons.location_on_rounded,
                title: 'Share My Location',
                subtitle:
                    'Broadcast your live GPS to your paired devices in real time.',
                color: scheme.primary,
                onTap: () => _push(const ShareScreen()),
              ),
              const SizedBox(height: 12),
              _BigActionCard(
                icon: Icons.visibility_rounded,
                title: 'Receive Location',
                subtitle:
                    'See the live location of devices that are sharing with you.',
                color: scheme.tertiary,
                onTap: () => _push(const ReceiverScreen()),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _navigateToPair,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Pair a New Device'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _PrivacyCard(),
            ],
          ),
        ),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _navigateToPair() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PairDeviceScreen()),
    );
  }

  IconData _themeIcon(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
    }
  }

  Future<void> _editDeviceName() async {
    final controller =
        TextEditingController(text: DeviceIdentity.instance.deviceName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Device Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Device Name',
            hintText: 'e.g. Manoj Phone',
            prefixIcon: Icon(Icons.label_outline_rounded),
          ),
          maxLength: 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      try {
        await DeviceIdentity.instance.setDeviceName(result);
        // Re-register the device with the new name in Firebase.
        if (DeviceIdentity.instance.deviceId != null) {
          await FirebaseService.instance.registerSelfDevice(
            deviceId: DeviceIdentity.instance.deviceId!,
            deviceName: result,
          );
        }
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device name updated.')),
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

class _MyDeviceCard extends StatelessWidget {
  const _MyDeviceCard({
    required this.deviceId,
    required this.deviceName,
    required this.onRename,
  });

  final String? deviceId;
  final String? deviceName;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.smartphone_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This Device',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        deviceName ?? 'Unknown',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit Device Name',
                  icon: Icon(Icons.edit_rounded,
                      size: 20, color: scheme.onSurfaceVariant),
                  onPressed: onRename,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Device ID',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                deviceId ?? 'Generating...',
                style: textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_rounded, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Privacy First',
                  style: textTheme.titleSmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'This app is NOT a mobile number tracker. Both phones must install the app and explicitly pair via Device ID or QR code. Only paired devices can see your live location. No location history is ever stored — only the latest point. You can stop sharing at any time.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigActionCard extends StatelessWidget {
  const _BigActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0.04),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
