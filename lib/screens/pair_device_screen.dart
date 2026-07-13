import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/device_identity.dart';
import '../services/firebase_service.dart';
import '../utils/error_messages.dart';

/// Pair Device screen — lets the user pair another phone either by:
///   - Showing their QR code / Device ID for the other phone to scan
///   - Entering / scanning the other phone's Device ID
class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _deviceIdCtrl = TextEditingController();
  final TextEditingController _deviceNameCtrl = TextEditingController();
  bool _isPairing = false;
  bool _scannerActive = false;
  bool _scanProcessed = false;
  final MobileScannerController _scannerCtrl = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _deviceIdCtrl.dispose();
    _deviceNameCtrl.dispose();
    _scannerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final identity = DeviceIdentity.instance;
    final myPairPayload = identity.pairPayload;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair a Device'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Code', icon: Icon(Icons.qr_code_rounded)),
            Tab(text: 'Add Device', icon: Icon(Icons.person_add_rounded)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ---------- Tab 1: My Code ----------
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Share this code with the person you want to pair with.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: 0.1),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: myPairPayload,
                      version: QrVersions.auto,
                      size: 240,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.roundedOuter,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.roundedOuter,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _DeviceIdBox(
                  label: 'My Device Name',
                  value: identity.deviceName ?? '',
                ),
                const SizedBox(height: 12),
                _DeviceIdBox(
                  label: 'My Device ID',
                  value: identity.deviceId ?? '',
                  copyable: true,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: identity.deviceId ?? ''),
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Device ID copied to clipboard.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy Device ID'),
                ),
              ],
            ),
          ),

          // ---------- Tab 2: Add Device ----------
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter the Device ID of the phone you want to pair with, or scan its QR code.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _deviceNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Device Name (optional)',
                    hintText: 'e.g. Manoj Phone',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deviceIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Device ID',
                    hintText: 'Paste the Device ID here',
                    prefixIcon: Icon(Icons.fingerprint_rounded),
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isPairing ? null : _pairByManualEntry,
                  icon: _isPairing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.link_rounded),
                  label: const Text('Pair Device'),
                ),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('OR'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _toggleScanner,
                  icon: Icon(_scannerActive
                      ? Icons.stop_circle_rounded
                      : Icons.qr_code_scanner_rounded),
                  label: Text(
                    _scannerActive ? 'Stop Scanner' : 'Scan QR Code',
                  ),
                ),
                if (_scannerActive) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: MobileScanner(
                        controller: _scannerCtrl,
                        onDetect: _onScanDetect,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Point the camera at the other phone\'s QR code.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleScanner() {
    setState(() {
      _scannerActive = !_scannerActive;
      _scanProcessed = false;
    });
    if (!_scannerActive) {
      _scannerCtrl.stop();
    } else {
      _scannerCtrl.start();
    }
  }

  Future<void> _onScanDetect(BarcodeCapture capture) async {
    // Debounce — multiple frames can fire onDetect before we stop the scanner.
    if (_scanProcessed) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null) return;
    _scanProcessed = true;
    await _scannerCtrl.stop();
    if (!mounted) return;
    setState(() => _scannerActive = false);
    final parsed = DeviceIdentity.parsePairPayload(raw);
    if (parsed == null) {
      _showMessage('Invalid QR code. Please scan a Live Location Share code.');
      _scanProcessed = false;
      return;
    }
    _deviceIdCtrl.text = parsed.deviceId;
    if (_deviceNameCtrl.text.isEmpty) {
      _deviceNameCtrl.text = parsed.deviceName;
    }
    await _pairByManualEntry();
    _scanProcessed = false;
  }

  Future<void> _pairByManualEntry() async {
    final id = _deviceIdCtrl.text.trim();
    if (id.isEmpty) {
      _showMessage('Please enter a Device ID.');
      return;
    }
    final myId = DeviceIdentity.instance.deviceId;
    if (myId == null) {
      _showMessage('Your device is not yet initialized. Please restart the app.');
      return;
    }
    if (id == myId) {
      _showMessage('You cannot pair your own device.');
      return;
    }
    setState(() => _isPairing = true);
    try {
      final name = _deviceNameCtrl.text.trim().isEmpty
          ? 'Paired Device'
          : _deviceNameCtrl.text.trim();
      await FirebaseService.instance.addPairedDevice(
        myDeviceId: myId,
        theirDeviceId: id,
        theirDeviceName: name,
      );
      if (!mounted) return;
      _showMessage('Device "$name" paired successfully.');
      _deviceIdCtrl.clear();
      _deviceNameCtrl.clear();
    } catch (e) {
      _showMessage('Could not pair device: ${ErrorMessages.forAny(e)}');
    } finally {
      if (mounted) setState(() => _isPairing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _DeviceIdBox extends StatelessWidget {
  const _DeviceIdBox({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard.')),
                );
              },
            ),
        ],
      ),
    );
  }
}
