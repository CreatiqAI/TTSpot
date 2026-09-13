import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../events/application/event_providers.dart';
import '../data/points_repository.dart';

/// Organiser's check-in screen: a big QR that rotates every 30 s. Attendees
/// scan it with the in-app scanner to be counted (no GPS needed).
class EventQrScreen extends ConsumerStatefulWidget {
  const EventQrScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventQrScreen> createState() => _EventQrScreenState();
}

class _EventQrScreenState extends ConsumerState<EventQrScreen> {
  String? _payload;
  String? _error;
  Timer? _timer;
  int _secondsLeft = 30 - (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 30;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = 30 - (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 30;
      if (s == 30 || s == 29) _load();
      if (mounted) setState(() => _secondsLeft = s);
      if (s % 10 == 0) ref.invalidate(eventDetailProvider(widget.eventId));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await ref.read(pointsRepositoryProvider).eventQrPayload(widget.eventId);
      if (mounted) {
        setState(() {
          _payload = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(eventDetailProvider(widget.eventId)).value;
    final count = detail?.event.checkinCount ?? 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.mapBg,
        appBar: AppBar(
          backgroundColor: AppColors.mapBg,
          foregroundColor: Colors.white,
          leading: IconButton(icon: const Icon(AppIcons.x), onPressed: () => context.pop()),
          title: const Text('Check-in code', style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(detail?.event.title ?? '', textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('$count checked in', style: const TextStyle(color: AppColors.mapTextSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                  child: _error != null
                      ? SizedBox(width: 280, height: 280, child: Center(child: Text(_error!, textAlign: TextAlign.center)))
                      : _payload == null
                          ? const SizedBox(width: 280, height: 280, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                          : QrImageView(data: _payload!, size: 280, padding: EdgeInsets.zero, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: _secondsLeft / 30, minHeight: 6, backgroundColor: Colors.white12, color: AppColors.warnColor),
                  ),
                ),
                const SizedBox(height: 8),
                Text('New code in $_secondsLeft s', style: const TextStyle(color: AppColors.mapTextSecondary, fontSize: 13)),
                const SizedBox(height: 28),
                const Text(
                  'Hold this up. Everyone scans it from the app (Me → Scan) to be counted, even in a basement with no GPS.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mapTextSecondary, fontSize: 13.5, height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
