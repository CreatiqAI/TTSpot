import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';

/// TiTi's pose for what he is doing: a calendar for meets, a pin for spots…
TitiPose titiPoseFor(String? tool) => switch (tool) {
      'search_meets' || 'my_meets' || 'meet_details' || 'join_meet' || 'leave_meet' => TitiPose.calendar,
      'search_spots' || 'my_saved_spots' || 'save_spot' || 'open_directions' || 'tt_here' => TitiPose.mapPin,
      'search_clubs' || 'my_clubs' => TitiPose.flag,
      'my_cars' || 'my_car_mods' => TitiPose.wrench,
      'my_car_documents' || 'road_tax_estimate' => TitiPose.clipboard,
      'my_points' => TitiPose.trophy,
      'my_vouchers' || 'partner_offers' || 'claim_voucher' => TitiPose.voucher,
      'my_cards' || 'open_box_shop' => TitiPose.gift,
      'my_notifications' => TitiPose.bell,
      'fuel_prices' => TitiPose.rolling,
      'my_summary' => TitiPose.magnifier,
      'open_page' => TitiPose.thumbsUp,
      _ => TitiPose.chat,
    };

/// Waiting for words: dots type in a bubble, and the latest status
/// ("Checking meets near you…") sits under it, fading across when it changes.
/// TiTi hops beside it (TitiHop, drawn by the answer next to its bubbles).
class TitiThinkingBubble extends StatelessWidget {
  const TitiThinkingBubble({super.key, this.status});
  final String? status;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4)),
            ),
            // Its own layer: the dots repaint every frame, the chat doesn't.
            child: const RepaintBoundary(child: TypingDots()),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              // Old and new status on top of each other: a cross-fade, no jump.
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
              child: status == null || status!.isEmpty
                  ? const SizedBox(key: ValueKey('none'), height: 0, width: 0)
                  : Padding(
                      key: ValueKey(status),
                      padding: const EdgeInsets.only(top: 5, left: 4),
                      child: Text(status!, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ),
            ),
          ),
        ],
      );
}

/// TiTi in his circle, hopping: a small bounce with a wiggle, looping.
class TitiHop extends StatefulWidget {
  const TitiHop({super.key, required this.pose, this.size = 40});
  final TitiPose pose;
  final double size;

  @override
  State<TitiHop> createState() => _TitiHopState();
}

class _TitiHopState extends State<TitiHop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final avatar = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: child),
      child: TitiAvatar(widget.pose, key: ValueKey(widget.pose), size: widget.size),
    );
    if (still) return avatar;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        // One hop per loop (up on the first half), a wiggle through the whole loop.
        final hop = t < 0.5 ? math.sin(t * 2 * math.pi) : 0.0;
        final wiggle = math.sin(t * 4 * math.pi) * 0.07;
        return Transform.translate(offset: Offset(0, -widget.size * 0.12 * hop), child: Transform.rotate(angle: wiggle, child: child));
      },
      child: avatar,
    );
  }
}

/// Three dots that pulse one after another.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color});
  final Color? color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.textSecondary;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Builder(builder: (_) {
              final phase = (_c.value - i * 0.18) % 1.0;
              final lift = phase < 0.4 ? math.sin(phase / 0.4 * math.pi) : 0.0;
              return Transform.translate(
                offset: Offset(0, -3 * lift),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.35 + 0.65 * lift), shape: BoxShape.circle),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
