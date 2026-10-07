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
import '../../../../core/widgets/empty_state.dart';
import '../../../events/application/event_providers.dart';
import '../domain/contest.dart';

/// Host: one printable dash card per approved car, with its vote QR.
/// Share each as an image (or all at once) and print them at a copy shop.
class VoteQrSheetScreen extends ConsumerStatefulWidget {
  const VoteQrSheetScreen({super.key, required this.eventId, required this.contestTitle, required this.entries});
  final String eventId;
  final String contestTitle;
  final List<ContestEntry> entries;

  @override
  ConsumerState<VoteQrSheetScreen> createState() => _VoteQrSheetScreenState();
}

/// Draws a RepaintBoundary to a PNG in the temp folder.
Future<XFile> _cardFile(GlobalKey key, String name) async {
  final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw const AppException("Couldn't draw the card. Try again.");
  final img = await boundary.toImage(pixelRatio: 3);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  if (data == null) throw const AppException("Couldn't draw the card. Try again.");
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name.png');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return XFile(file.path, mimeType: 'image/png');
}

class _VoteQrSheetScreenState extends ConsumerState<VoteQrSheetScreen> {
  late final _keys = {for (final e in widget.entries) e.id: GlobalKey()};
  String? _sharing; // entry id, or '*' for all

  String _fileName(ContestEntry e) => 'ttspot-vote-${e.number ?? 0}-${e.carName}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');

  Future<void> _share(List<ContestEntry> list, {required bool all}) async {
    setState(() => _sharing = all ? '*' : list.first.id);
    try {
      final files = <XFile>[];
      for (final e in list) {
        files.add(await _cardFile(_keys[e.id]!, _fileName(e)));
      }
      await SharePlus.instance.share(ShareParams(
        files: files,
        text: all ? '${widget.contestTitle}: vote QR codes' : '#${list.first.number} ${list.first.carName}: vote QR',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _sharing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventTitle = ref.watch(eventDetailProvider(widget.eventId)).value?.event.title ?? '';
    final list = widget.entries;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Vote QR codes'),
        actions: [
          if (list.length > 1)
            TextButton(
              onPressed: _sharing != null ? null : () => _share(list, all: true),
              child: _sharing == '*' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Share all'),
            ),
        ],
      ),
      backgroundColor: AppColors.surfaceGray,
      body: list.isEmpty
          ? const EmptyState(titi: TitiPose.clipboard, icon: AppIcons.qrCode, title: 'No cars yet', subtitle: 'Approve or add cars first. Each one gets a card to put on its dash.')
          // A Column (not a lazy list) so every card is painted and "Share all" can draw them.
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Print each card and put it on the car's dash. People scan it in TT Spot to vote.",
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  for (final e in list) ...[
                    RepaintBoundary(key: _keys[e.id], child: VoteDashCard(entry: e, contestTitle: widget.contestTitle, eventTitle: eventTitle)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _sharing != null ? null : () => _share([e], all: false),
                        icon: _sharing == e.id ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.shareFat, size: 18),
                        label: const Text('Share image'),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
    );
  }
}

/// The printed card. Fixed print colours (it is paper, not the app theme).
class VoteDashCard extends StatelessWidget {
  const VoteDashCard({super.key, required this.entry, required this.contestTitle, this.eventTitle = ''});
  final ContestEntry entry;
  final String contestTitle;
  final String eventTitle;

  static const _ink = Color(0xFF101010);
  static const _red = Color(0xFFE00008);
  static const _grey = Color(0xFF6B6B6B);

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE3E3E3))),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(AppIcons.trophyFill, color: _red, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  contestTitle.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: _ink),
                ),
              ),
              const SizedBox(width: 8),
              const Text('TT SPOT', style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800, color: _red)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '#${e.number ?? '?'}',
              style: const TextStyle(fontFamily: AppFonts.display, fontSize: 110, fontWeight: FontWeight.w800, height: 1, color: _ink),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            e.carName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: AppFonts.display, fontSize: 32, fontWeight: FontWeight.w800, height: 1.05, color: _ink),
          ),
          if (e.handle.isNotEmpty)
            Text(e.handle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _grey)),
          const SizedBox(height: 12),
          QrImageView(
            data: voteQrPayload(e.id),
            size: 220,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.Q,
          ),
          const SizedBox(height: 12),
          const Text('Scan with TT Spot to vote', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
          if (eventTitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(eventTitle, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _grey)),
          ],
        ],
      ),
    );
  }
}
