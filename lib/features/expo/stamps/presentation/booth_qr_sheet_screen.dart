import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/open_external.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../events/application/event_providers.dart';
import '../application/stamps_providers.dart';
import '../domain/stamps_models.dart';

/// Host: one big printable stamp QR per stamp-stop booth. Share one card or
/// all of them as images and print them at a copy shop.
class BoothQrSheetScreen extends ConsumerStatefulWidget {
  const BoothQrSheetScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<BoothQrSheetScreen> createState() => _BoothQrSheetScreenState();
}

class _BoothQrSheetScreenState extends ConsumerState<BoothQrSheetScreen> {
  final _keys = <String, GlobalKey>{};
  bool _sharingAll = false;

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  Future<void> _shareAll(List<BoothSetupRow> rows, String title) async {
    setState(() => _sharingAll = true);
    try {
      final files = <XFile>[];
      for (final r in rows) {
        files.add(await _renderCard(_keyFor(r.id), r));
      }
      await SharePlus.instance.share(ShareParams(files: files, text: 'Booth stamp QRs for $title'));
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _sharingAll = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final title = ref.watch(eventDetailProvider(widget.eventId)).value?.event.title ?? '';
    final async = ref.watch(boothSetupProvider(widget.eventId));
    final rows = (async.value ?? const <BoothSetupRow>[]).where((r) => r.stampStop && r.qrPayload != null).toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Booth QRs'),
        actions: [
          if (rows.length > 1)
            _sharingAll
                ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton.icon(onPressed: () => _shareAll(rows, title), icon: const Icon(AppIcons.shareFat, size: 18), label: const Text('Share all')),
        ],
      ),
      backgroundColor: AppColors.surfaceGray,
      body: async.isLoading && async.value == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : rows.isEmpty
              ? const EmptyState(
                  titi: TitiPose.clipboard,
                  icon: AppIcons.qrCode,
                  title: 'No stamp stops yet',
                  subtitle: 'Switch on "Stamp stop" for a booth to get its QR.',
                )
              // A Column (not a lazy list) so every card is painted and "Share all" can draw it.
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Print each card and stick it at the booth. Members scan it in TT Spot to collect a stamp.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      for (final r in rows) ...[
                        _BoothQrCard(boundaryKey: _keyFor(r.id), eventId: widget.eventId, eventTitle: title, row: r, onToast: _toast),
                        const SizedBox(height: 18),
                      ],
                    ],
                  ),
                ),
    );
  }
}

/// Draws a card's RepaintBoundary to a PNG in the temp folder.
Future<XFile> _renderCard(GlobalKey key, BoothSetupRow row) async {
  final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw const AppException("Couldn't draw the card. Try again.");
  final img = await boundary.toImage(pixelRatio: 3);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  if (data == null) throw const AppException("Couldn't draw the card. Try again.");
  final dir = await getTemporaryDirectory();
  final safe = '${boothLabel(row.booths)}-${row.name}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  final file = File('${dir.path}/ttspot-booth-$safe-${row.id.substring(0, 6)}.png');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return XFile(file.path, mimeType: 'image/png');
}

class _BoothQrCard extends ConsumerStatefulWidget {
  const _BoothQrCard({required this.boundaryKey, required this.eventId, required this.eventTitle, required this.row, required this.onToast});
  final GlobalKey boundaryKey;
  final String eventId;
  final String eventTitle;
  final BoothSetupRow row;
  final void Function(String) onToast;

  @override
  ConsumerState<_BoothQrCard> createState() => _BoothQrCardState();
}

class _BoothQrCardState extends ConsumerState<_BoothQrCard> {
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final f = await _renderCard(widget.boundaryKey, widget.row);
      await SharePlus.instance.share(ShareParams(files: [f], text: '${widget.row.name} stamp QR for ${widget.eventTitle}'));
    } catch (e) {
      widget.onToast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _rotate() async {
    final ok = await confirmSheet(context, title: 'New stamp code?', body: 'The printed QR for this booth stops working. Print the new one.', confirm: 'New code');
    if (!ok) return;
    try {
      await ref.read(stampsActionsProvider).rotateCode(widget.eventId, widget.row.id);
      widget.onToast('New code ready. Share and print it again.');
    } catch (e) {
      widget.onToast(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final booth = boothLabel(r.booths);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: widget.boundaryKey,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE3E3E3))),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(AppIcons.stamp, color: Color(0xFFE00008), size: 22),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text('BOOTH STAMP', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: Color(0xFFE00008))),
                    ),
                    const Spacer(),
                    const Text('TT SPOT', style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFE00008))),
                  ],
                ),
                const SizedBox(height: 12),
                if (booth.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF101010), borderRadius: BorderRadius.circular(8)),
                    child: Text(booth, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                const SizedBox(height: 8),
                Text(
                  r.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w800, height: 1.05, color: Color(0xFF101010)),
                ),
                const SizedBox(height: 12),
                QrImageView(
                  data: r.qrPayload!,
                  size: 240,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.Q,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Scan with TT Spot to collect a stamp',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF101010)),
                ),
                if (r.freebie != null) ...[
                  const SizedBox(height: 2),
                  Text('Free ${r.freebie} for stamp collectors', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF101010))),
                ],
                if (widget.eventTitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(widget.eventTitle, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 4,
          children: [
            TextButton.icon(onPressed: _rotate, icon: const Icon(AppIcons.arrowsClockwise, size: 18), label: const Text('New code')),
            TextButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.shareFat, size: 18),
              label: const Text('Share image'),
            ),
          ],
        ),
      ],
    );
  }
}
