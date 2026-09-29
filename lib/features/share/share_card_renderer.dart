import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/friendly_error.dart';
import '../points/application/points_providers.dart';
import '../points/data/points_repository.dart';
import '../profile/application/profile_providers.dart';
import '../profile/domain/car.dart';
import 'share_card.dart';

export 'share_card.dart' show ShareCardSpec, CheckinShareSpec, CardPullShareSpec, MeetInviteShareSpec, DrawWinShareSpec;

/// A meet's invite code, for the host's "Join us" card.
final _shareInviteCodeProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, eventId) => ref.watch(pointsRepositoryProvider).eventInviteCode(eventId),
);

/// The member's default car (else the first), for the check-in card.
Car? myShareCar(WidgetRef ref) {
  final me = ref.read(currentUserIdProvider);
  if (me == null) return null;
  final cars = ref.read(userCarsProvider(me)).value ?? const <Car>[];
  if (cars.isEmpty) return null;
  return cars.where((c) => c.isDefault).firstOrNull ?? cars.first;
}

/// Preview sheet: the card scaled down, then Share turns it into a
/// 1080x1920 PNG and opens the native share sheet with the link.
Future<void> showShareCardSheet(BuildContext context, ShareCardSpec spec) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShareCardSheet(spec: spec),
  );
}

class _ShareCardSheet extends ConsumerStatefulWidget {
  const _ShareCardSheet({required this.spec});
  final ShareCardSpec spec;

  @override
  ConsumerState<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends ConsumerState<_ShareCardSheet> {
  final _boundary = GlobalKey();
  bool _imagesReady = false;
  bool _busy = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _precache();
  }

  /// Decode every picture on the card before it can be captured, so the PNG
  /// never has holes. Gives up waiting after a few seconds.
  Future<void> _precache() async {
    final jobs = [
      for (final p in widget.spec.images) precacheImage(p, context, onError: (_, _) {}),
      precacheImage(const AssetImage('assets/brand/logo_dark.png'), context, onError: (_, _) {}),
    ];
    try {
      await Future.wait(jobs).timeout(const Duration(seconds: 8));
    } catch (_) {/* share what we have */}
    if (mounted) setState(() => _imagesReady = true);
  }

  bool get _hostInvite => switch (widget.spec) {
        MeetInviteShareSpec s => s.hostInvite,
        _ => false,
      };

  /// (link shown on the card without the scheme, ready to share?)
  (String, bool) _footer() {
    final spec = widget.spec;
    if (spec is MeetInviteShareSpec && spec.hostInvite) {
      final code = ref.watch(_shareInviteCodeProvider(spec.event.id));
      return switch (code) {
        AsyncData(:final value) when value.isNotEmpty => ('ttspot.my/e/$value', true),
        AsyncError() => _referral(),
        _ => ('ttspot.my', false),
      };
    }
    return _referral();
  }

  (String, bool) _referral() {
    final code = ref.watch(myReferralCodeProvider);
    return switch (code) {
      AsyncData(:final value) => (value.isEmpty ? 'ttspot.my' : 'ttspot.my/r/$value', true),
      AsyncError() => ('ttspot.my', true),
      _ => ('ttspot.my', false),
    };
  }

  Future<void> _share(String link) async {
    setState(() => _busy = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw const AppException('Couldn\'t draw the card. Try again.');
      final img = await boundary.toImage(pixelRatio: kSharePixelRatio);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (data == null) throw const AppException('Couldn\'t draw the card. Try again.');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ttspot-${widget.spec.fileTag.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')}-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: widget.spec.shareText('https://$link'),
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (link, linkReady) = _footer();
    final ready = _imagesReady && linkReady && !_busy;
    final maxH = MediaQuery.sizeOf(context).height * 0.62;
    final previewH = maxH.clamp(260.0, 520.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: previewH,
              child: AspectRatio(
                aspectRatio: kShareCardSize.width / kShareCardSize.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FittedBox(
                      child: RepaintBoundary(
                        key: _boundary,
                        child: ShareCard(
                          spec: widget.spec,
                          footerLink: link,
                          footerLead: _hostInvite ? 'Join us on TT Spot' : 'Join me on TT Spot',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: ready ? () => _share(link) : null,
                icon: ready
                    ? const Icon(AppIcons.shareFat, size: 18)
                    : SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary)),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
