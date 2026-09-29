import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../events/application/event_providers.dart';
import '../domain/floorplan.dart';

/// Organizer: one big printable QR per zone, entrance and parking pin.
/// Screenshot it, or share each card as an image and print it at a copy shop.
class ZoneQrSheetScreen extends ConsumerWidget {
  const ZoneQrSheetScreen({super.key, required this.eventId, required this.levels});
  final String eventId;
  final List<FloorLevel> levels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(eventDetailProvider(eventId)).value?.event.title ?? '';
    final items = [
      for (final l in levels)
        for (final p in l.pins)
          if (p.kind.hasZoneQr) (level: l, pin: p),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Zone QRs'),
      ),
      backgroundColor: AppColors.surfaceGray,
      body: items.isEmpty
          ? const EmptyState(
              titi: TitiPose.clipboard,
              icon: AppIcons.qrCode,
              title: 'No zone pins yet',
              subtitle: 'Add Zone, Entrance or Parking pins to the plan. Each one gets a QR to tape on a pillar so members can set their spot in a basement with no GPS.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Print each card and tape it where the pin is. Members scan it (Me → Scan, or Floorplan → Scan a zone QR) to set their level and spot.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 14),
                for (final it in items) ...[
                  _ZoneCard(eventTitle: title, level: it.level, pin: it.pin),
                  const SizedBox(height: 18),
                ],
              ],
            ),
    );
  }
}

class _ZoneCard extends StatefulWidget {
  const _ZoneCard({required this.eventTitle, required this.level, required this.pin});
  final String eventTitle;
  final FloorLevel level;
  final FloorPin pin;

  @override
  State<_ZoneCard> createState() => _ZoneCardState();
}

class _ZoneCardState extends State<_ZoneCard> {
  final _key = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw const AppException('Couldn\'t draw the card. Try again.');
      final img = await boundary.toImage(pixelRatio: 3);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (data == null) throw const AppException('Couldn\'t draw the card. Try again.');
      final dir = await getTemporaryDirectory();
      final safe = '${widget.level.name}-${widget.pin.title}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final file = File('${dir.path}/ttspot-zone-$safe.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: '${widget.pin.title} (${widget.level.name}) zone QR for ${widget.eventTitle}',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: _key,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE3E3E3))),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF101010), borderRadius: BorderRadius.circular(8)),
                      child: Text(widget.level.name, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Icon(pin.kind.icon, color: pin.kind.color, size: 22),
                    const SizedBox(width: 6),
                    Text(pin.kind.label.toUpperCase(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: pin.kind.color)),
                    const Spacer(),
                    const Text('TT SPOT', style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFE00008))),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  pin.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: AppFonts.display, fontSize: 40, fontWeight: FontWeight.w800, height: 1.05, color: Color(0xFF101010)),
                ),
                const SizedBox(height: 12),
                QrImageView(
                  data: zoneQrPayload(pin.id),
                  size: 240,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.Q,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Scan with the TT Spot app to set your spot',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF101010)),
                ),
                if (widget.eventTitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(widget.eventTitle, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _sharing ? null : _share,
            icon: _sharing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.shareFat, size: 18),
            label: const Text('Share image'),
          ),
        ),
      ],
    );
  }
}
