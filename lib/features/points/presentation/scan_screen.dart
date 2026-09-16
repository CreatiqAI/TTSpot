import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/points_providers.dart';
import '../domain/points.dart';

/// One scanner for every TT Spot code: friend QR, meet check-in, spot sticker.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  bool _busy = false;
  String? _lastRaw;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null || raw == _lastRaw) return;
    await _handleRaw(raw);
  }

  /// A QR someone sent you (WhatsApp screenshot, saved image).
  Future<void> _fromPhoto() async {
    if (_busy) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);
    if (file == null) return;
    final capture = await _controller.analyzeImage(file.path, formats: const [BarcodeFormat.qrCode]);
    final raw = capture?.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null) {
      _toast('No QR code found in that photo.');
      return;
    }
    await _handleRaw(raw);
  }

  Future<void> _handleRaw(String raw) async {
    _lastRaw = raw;
    final code = ScannedCode.parse(raw);
    if (code == null) {
      _toast('Not a TT Spot code.');
      return;
    }
    setState(() => _busy = true);
    await _controller.stop();
    try {
      final outcome = await ref.read(pointsActionsProvider).handle(code);
      if (!mounted) return;
      if (!outcome.silent) await _showResult(outcome);
      if (mounted) {
        if (outcome.route != null) {
          context.pushReplacement(outcome.route!);
        } else {
          context.pop();
        }
      }
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
      setState(() => _busy = false);
      _lastRaw = null;
      await _controller.start();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showResult(ScanOutcome o) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtIcon(o.points > 0 ? AppArt.star : AppArt.check, size: 64),
            const SizedBox(height: 12),
            Text(o.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (o.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(o.subtitle!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
            ],
            if (o.points > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(999)),
                child: Text('+${o.points} points', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nice'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: () => context.pop()),
        title: const Text('Scan', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(tooltip: 'From photo', icon: const Icon(AppIcons.images), onPressed: _fromPhoto),
          IconButton(tooltip: 'Torch', icon: const Icon(AppIcons.lightning), onPressed: () => _controller.toggleTorch()),
          IconButton(tooltip: 'My QR', icon: const Icon(AppIcons.qrCode), onPressed: () => context.pushReplacement(Routes.myQr)),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (_, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera access is off. Allow it in Settings to scan codes.'
                      : 'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              _busy ? 'Checking…' : 'Point at a friend\'s QR, the organiser\'s check-in code, or a spot sticker.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
            ),
          ),
          if (_busy) const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      ),
    );
  }
}
