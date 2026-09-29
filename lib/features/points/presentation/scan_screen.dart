import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../events/application/event_providers.dart';
import '../../events/presentation/event_car_widgets.dart';
import '../../share/share_card_renderer.dart';
import '../../organizer/domain/organizer_models.dart' show parseDrawClaimCode;
import '../../organizer/presentation/widgets/prize_claim_dialog.dart';
import '../application/points_providers.dart';
import '../domain/points.dart';

/// One scanner for every TT Spot code: friend QR, meet check-in, spot sticker,
/// lucky-draw prize claim. [prizeClaims] = the crew's "Scan prize claim" mode:
/// only claim QRs, and it keeps scanning after each one.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.prizeClaims = false});
  final bool prizeClaims;

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
    final claim = parseDrawClaimCode(raw);
    if (claim != null) return _claimPrize(claim);
    if (widget.prizeClaims) {
      _toast('That is not a prize claim QR.');
      return;
    }
    final code = ScannedCode.parse(raw);
    if (code == null) {
      _toast('Not a TT Spot code.');
      return;
    }
    setState(() => _busy = true);
    await _controller.stop();
    try {
      // Meet check-in: which car did you bring? (Only asks with 2+ cars.)
      String? carId;
      if (code is MeetCheckinCode) {
        if (!mounted) return;
        final choice = await chooseCheckinCar(context, ref, code.eventId);
        if (!mounted) return;
        if (choice.cancelled) {
          setState(() => _busy = false);
          _lastRaw = null;
          await _controller.start();
          return;
        }
        carId = choice.car?.id;
      }
      final outcome = await ref.read(pointsActionsProvider).handle(code, carId: carId);
      if (!mounted) return;
      if (!outcome.silent) {
        final share = await _showResult(outcome);
        if (share == true && outcome.checkinEventId != null && mounted) await _shareCheckin(outcome.checkinEventId!);
      }
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

  Future<void> _claimPrize(String code) async {
    setState(() => _busy = true);
    await _controller.stop();
    if (mounted) await showPrizeClaim(context, ref, code);
    if (!mounted) return;
    setState(() => _busy = false);
    _lastRaw = null;
    await _controller.start();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// The "CHECKED IN" story card for the meet just scanned, with the car
  /// brought (else my default car).
  Future<void> _shareCheckin(String eventId) async {
    final me = ref.read(currentUserIdProvider);
    String placeName = 'a TT Spot meet';
    String? cover, bodyStyle, carTitle;
    try {
      final detail = await ref.read(eventDetailProvider(eventId).future);
      if (detail != null) placeName = detail.event.title;
      final brought = me == null ? null : (await ref.read(eventCarsProvider(eventId).future))[me];
      if (brought != null) {
        cover = brought.cover;
        bodyStyle = brought.bodyStyle;
        carTitle = brought.title;
      } else {
        final car = myShareCar(ref);
        cover = car?.cover;
        bodyStyle = car?.bodyStyle;
        carTitle = car?.title;
      }
    } catch (_) {/* share with what we have */}
    if (!mounted) return;
    await showShareCardSheet(context, CheckinShareSpec(placeName: placeName, at: DateTime.now(), carCover: cover, carBodyStyle: bodyStyle, carTitle: carTitle));
  }

  /// True when they tapped Share (fresh meet check-ins only).
  Future<bool?> _showResult(ScanOutcome o) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtIcon(o.points > 0 ? kCoinAsset : AppArt.check, size: 64),
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
        actions: [
          if (o.checkinEventId != null)
            TextButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(AppIcons.shareFat, size: 18), label: const Text('Share')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nice')),
        ],
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
        title: Text(widget.prizeClaims ? 'Scan prize claim' : 'Scan', style: const TextStyle(color: Colors.white)),
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
              _busy
                  ? 'Checking…'
                  : widget.prizeClaims
                      ? 'Point at the winner\'s claim QR on their phone.'
                      : 'Point at a friend\'s QR, the organiser\'s check-in code, or a spot sticker.',
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
