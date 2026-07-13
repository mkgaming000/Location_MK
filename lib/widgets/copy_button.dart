import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A reusable button that copies [text] to the clipboard and shows a SnackBar
/// confirmation. Used by the Receiver screen to copy GPS coordinates.
class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.label,
    this.icon,
    this.successMessage,
  });

  /// The text that will be copied to the clipboard.
  final String text;

  /// Optional button label. Defaults to "Copy".
  final String? label;

  /// Optional icon. Defaults to `Icons.copy`.
  final IconData? icon;

  /// Optional success message shown in the SnackBar. Defaults to
  /// "Copied to clipboard".
  final String? successMessage;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _justCopied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _justCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.successMessage ?? 'Copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      onPressed: _copy,
      icon: Icon(
        _justCopied ? Icons.check : widget.icon ?? Icons.copy,
        color: _justCopied ? scheme.primary : scheme.onSurfaceVariant,
      ),
      label: Text(widget.label ?? 'Copy'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
