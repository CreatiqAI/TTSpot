import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_icons.dart';
import '../domain/floorplan.dart';

/// Camera that waits for a printed zone QR (`ttspot:zone:<pin_id>`) and pops
/// with its raw payload.
class ZoneScannerScreen extends StatefulWidget {
  const ZoneScannerScreen({super.key});

  @override
  State<ZoneScannerScreen> createState() => _ZoneScannerScreenState();
}

class _ZoneScannerScreenState extends State<ZoneScannerScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;
  String? _lastBad;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final raw in capture.barcodes.map((b) => b.rawValue).whereType<String>()) {
      if (parseZoneQr(raw) != null) {
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
      if (raw != _lastBad) {
        _lastBad = raw;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('That is not a zone code. Look for the TT Spot zone QR on a pillar.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Scan a zone QR', style: TextStyle(color: Colors.white)),
        actions: [IconButton(tooltip: 'Torch', icon: const Icon(AppIcons.lightning), onPressed: () => _controller.toggleTorch())],
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
                      ? 'Camera access is off. Allow it in Settings to scan zone codes.'
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
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Zone codes are taped to pillars, entrances and parking bays. Scan one to set your spot and level.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
            ),
          ),
        ],
      ),
    );
  }
}
