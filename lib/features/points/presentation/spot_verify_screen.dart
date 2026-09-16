import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../social/application/community_providers.dart';
import '../application/points_providers.dart';
import '../domain/verification.dart';

/// After scanning a spot sticker: snap your car here, we check the photo, you
/// get the verified bonus on the spot (or a human looks within 24 h).
class SpotVerifyScreen extends ConsumerStatefulWidget {
  const SpotVerifyScreen({super.key, required this.placeId, required this.code});
  final String placeId;
  final String code;

  @override
  ConsumerState<SpotVerifyScreen> createState() => _SpotVerifyScreenState();
}

class _SpotVerifyScreenState extends ConsumerState<SpotVerifyScreen> {
  XFile? _photo;
  bool _busy = false;
  String _stage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    final files = await pickPhotos(context, max: 1, multi: false);
    if (files.isNotEmpty) setState(() => _photo = files.first);
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(pointsActionsProvider).verifySpot(
            placeId: widget.placeId,
            code: widget.code,
            photo: photo,
            onStage: (s) {
              if (mounted) setState(() => _stage = s);
            },
          );
      if (!mounted) return;
      await _showResult(result);
      if (mounted) context.pushReplacement(Routes.place(widget.placeId));
    } catch (e) {
      if (mounted) {
        _snack(friendlyError(e));
        setState(() {
          _busy = false;
          _stage = '';
        });
      }
    }
  }

  Future<void> _showResult(VerifyResult r) {
    final (art, title, body) = switch (r.status) {
      VerificationStatus.approved => (AppArt.star, 'Verified!', 'Your car is on the record here.'),
      VerificationStatus.rejected => (AppArt.prohibited, 'Not approved', r.reason ?? 'The photo didn\'t pass.'),
      _ => (AppArt.stopwatch, 'In review', r.reason ?? 'A human will check within 24 hours. Points land when it\'s approved.'),
    };
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtIcon(art, size: 64),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
            if (r.points > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(999)),
                child: Text('+${r.points} points', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final place = ref.watch(placeProvider(widget.placeId)).value;
    final rules = ref.watch(pointRulesProvider).value ?? const [];
    final pts = rules.where((r) => r.reason == 'spot_verified').firstOrNull?.points ?? 50;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: const Text('Verified check-in'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              ArtIcon(place?.kindArt ?? AppArt.pin, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place?.name ?? 'Spot', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('Sticker scanned · +$pts points when approved', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _busy ? null : _pick,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: _photo == null
                    ? Container(
                        color: AppColors.surfaceGray,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(AppIcons.cameraPlus, size: 40, color: AppColors.textSecondary),
                            SizedBox(height: 8),
                            Text('Photo of your car here', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    : Image.file(File(_photo!.path), fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Any angle, your car in frame, taken right here. We check it automatically. Screenshots and photos of photos don\'t count.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: _busy ? (_stage.isEmpty ? 'Working…' : _stage) : 'Submit check-in', loading: _busy, onPressed: _busy || _photo == null ? null : _submit),
          if (_photo != null && !_busy) ...[
            const SizedBox(height: 8),
            SecondaryButton(label: 'Choose a different photo', onPressed: _pick),
          ],
        ],
      ),
    );
  }
}
