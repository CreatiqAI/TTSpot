import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/dates.dart';
import '../../../../../core/utils/friendly_error.dart';
import '../../../../../core/utils/open_external.dart';

/// "8:05:09 PM": the live clock on a hand-over card (a screenshot shows a
/// frozen time, a live phone doesn't).
String clockWithSeconds(DateTime t) {
  final l = t.toLocal();
  var h = l.hour % 12;
  if (h == 0) h = 12;
  String two(int n) => n.toString().padLeft(2, '0');
  return '$h:${two(l.minute)}:${two(l.second)} ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// The big voucher the member shows at a booth (freebie) or at the counter
/// (stamp rally reward). A shimmer and a ticking clock make a screenshot
/// obvious; booth staff swipe "Hand over" on the member's phone, confirm,
/// and it turns into "Handed over · 2:14 PM".
class HandOverCard extends StatefulWidget {
  const HandOverCard({
    super.key,
    required this.item,
    required this.kind,
    this.from,
    this.showTo = 'Show this to the booth staff',
    this.redeemedAt,
    required this.onRedeem,
  });

  /// "Keychain"
  final String item;

  /// "FREEBIE", "STAMP RALLY"
  final String kind;

  /// "Brembo MY · A019"
  final String? from;
  final String showTo;
  final DateTime? redeemedAt;

  /// Hands it over on the server; returns when.
  final Future<DateTime> Function() onRedeem;

  @override
  State<HandOverCard> createState() => _HandOverCardState();
}

class _HandOverCardState extends State<HandOverCard> with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  Timer? _clock;
  DateTime _now = DateTime.now();
  DateTime? _redeemedAt;

  @override
  void initState() {
    super.initState();
    _redeemedAt = widget.redeemedAt;
    if (_redeemedAt == null) _startLive();
  }

  void _startLive() {
    _shine.repeat();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _stopLive() {
    _clock?.cancel();
    _clock = null;
    _shine.stop();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _shine.dispose();
    super.dispose();
  }

  Future<bool> _confirm() async {
    final ok = await confirmSheet(
      context,
      title: 'Hand over ${widget.item}?',
      body: "Staff only. This can't be undone.",
      confirm: 'Hand over',
      icon: AppIcons.gift,
    );
    if (!ok || !mounted) return false;
    try {
      final at = await widget.onRedeem();
      if (!mounted) return true;
      _stopLive();
      setState(() => _redeemedAt = at);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _redeemedAt != null;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text(widget.kind, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white)),
                ),
              ),
              const Spacer(),
              const Text('TT SPOT', style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(done ? AppIcons.check : AppIcons.gift, size: 36, color: done ? AppColors.success : AppColors.brand),
          ),
          const SizedBox(height: 12),
          Text(
            widget.item,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: AppFonts.display, fontSize: 36, height: 1.05, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          if (widget.from != null && widget.from!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.from!, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 18),
          if (done) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.checkCircleFill, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Handed over · ${formatTime(_redeemedAt!)}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
            ),
          ] else ...[
            Text(
              clockWithSeconds(_now),
              style: const TextStyle(fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
            ),
            Text(formatDate(_now), style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
            const SizedBox(height: 14),
            Text(widget.showTo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 12),
            SwipeToConfirm(label: 'Staff: swipe to hand over', onConfirmed: _confirm),
          ],
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: done
              ? const LinearGradient(colors: [Color(0xFF1C1F26), AppColors.ink], begin: Alignment.topLeft, end: Alignment.bottomRight)
              : const LinearGradient(colors: [AppColors.brand, AppColors.brandDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Stack(
          children: [
            body,
            if (!done)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _shine,
                    builder: (_, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
                          stops: const [0.35, 0.5, 0.65],
                          transform: _SlideGradient(_shine.value),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Moves a gradient across its box: t = 0 starts off the left, 1 ends off the right.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);
  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2.4 - 1.2), bounds.height * (t * 2.4 - 1.2) * 0.3, 0);
}

/// A pill the staff drag right to confirm. [onConfirmed] returns false to
/// snap the thumb back (cancelled or failed).
class SwipeToConfirm extends StatefulWidget {
  const SwipeToConfirm({super.key, required this.label, required this.onConfirmed});
  final String label;
  final Future<bool> Function() onConfirmed;

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm> {
  static const _thumb = 52.0;
  static const _inset = 4.0;
  double _dx = 0;
  bool _dragging = false;
  bool _busy = false;

  Future<void> _fire(double travel) async {
    setState(() {
      _busy = true;
      _dragging = false;
      _dx = travel;
    });
    final ok = await widget.onConfirmed();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _dx = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final travel = (c.maxWidth - _thumb - _inset * 2).clamp(0.0, double.infinity);
      return Semantics(
        button: true,
        label: widget.label,
        onTap: _busy ? null : () => _fire(travel),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _busy ? null : (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: _busy ? null : (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, travel)),
          onHorizontalDragEnd: _busy
              ? null
              : (_) {
                  if (travel > 0 && _dx >= travel * 0.85) {
                    _fire(travel);
                  } else {
                    setState(() {
                      _dragging = false;
                      _dx = 0;
                    });
                  }
                },
          child: Stack(
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: _thumb + _inset * 2),
                alignment: Alignment.center,
                padding: const EdgeInsets.fromLTRB(_thumb + 14, 10, 18, 10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              AnimatedPositioned(
                duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                left: _inset + _dx,
                top: _inset,
                bottom: _inset,
                child: Container(
                  width: _thumb,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.brand))
                      : const Icon(AppIcons.caretDoubleRight, color: AppColors.brand, size: 24),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
