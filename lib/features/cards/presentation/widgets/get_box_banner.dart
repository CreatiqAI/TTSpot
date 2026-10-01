import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';

/// "Get a blind box" on my profile's Cards tab: the red box floating and
/// wobbling on a dark product card, a shine sweeping across it now and then,
/// the price in points (or the boxes already waiting) and one call to action.
/// Dark in both themes, like the box shop it leads to, so the red box pops.
class GetBoxBanner extends StatefulWidget {
  const GetBoxBanner({super.key, required this.waiting, required this.cost, required this.onTap});

  /// Sealed boxes I already have. More than 0: the banner opens one.
  final int waiting;

  /// Points per box; null while the price loads.
  final int? cost;
  final VoidCallback onTap;

  @override
  State<GetBoxBanner> createState() => _GetBoxBannerState();
}

class _GetBoxBannerState extends State<GetBoxBanner> with SingleTickerProviderStateMixin {
  /// One 3.2 s loop: float up and down, a small wobble, the shine in the
  /// first third.
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce motion: the box sits still.
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop.stop();
      _loop.value = 0.5;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = widget.waiting;
    final title = waiting > 0 ? 'Open your blind box' : 'Get a blind box';
    final cta = waiting > 0 ? 'Open it' : 'Get one';
    return Semantics(
      button: true,
      label: waiting > 0 ? '$title. $waiting waiting.' : '$title${widget.cost == null ? '' : ', ${widget.cost} points'}.',
      excludeSemantics: true,
      child: Material(
        color: const Color(0xFF101114),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.brand.withValues(alpha: 0.45))),
        child: InkWell(
          onTap: widget.onTap,
          child: Stack(
            children: [
              // A soft red glow behind the box.
              Positioned(
                right: -30,
                top: -40,
                child: IgnorePointer(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [AppColors.brand.withValues(alpha: 0.5), AppColors.brand.withValues(alpha: 0)])),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BLIND BOX · SERIES 01', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: Color(0xFFFF7A80))),
                          const SizedBox(height: 4),
                          Text(title.toUpperCase(), style: const TextStyle(fontFamily: AppFonts.display, fontSize: 26, height: 1, fontWeight: FontWeight.w800, color: Colors.white)),
                          const SizedBox(height: 6),
                          if (waiting > 0)
                            _Line(icon: AppIcons.gift, text: waiting == 1 ? '1 free box waiting' : '$waiting free boxes waiting', highlight: true)
                          else if (widget.cost != null)
                            Row(
                              children: [
                                const PointsCoin(size: 16),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text('${widget.cost} points · 1 of 7 TiTi cards', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8))),
                                ),
                              ],
                            ),
                          const SizedBox(height: 10),
                          // The call to action, a pill that breathes with the box.
                          AnimatedBuilder(
                            animation: _loop,
                            builder: (_, child) => Transform.scale(alignment: Alignment.centerLeft, scale: 1 + 0.03 * math.sin(_loop.value * 2 * math.pi), child: child),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
                              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(AppRadius.pill)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(child: Text(cta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white))),
                                  const SizedBox(width: 4),
                                  const Icon(AppIcons.caretRight, size: 14, color: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _FloatingBox(loop: _loop, size: 108),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.highlight = false});
  final IconData icon;
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: highlight ? const Color(0xFFFFC94D) : Colors.white70),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: highlight ? const Color(0xFFFFC94D) : Colors.white.withValues(alpha: 0.8))),
          ),
        ],
      );
}

/// The closed box, floating, with a small wobble and a shine sweeping
/// across it once per loop.
class _FloatingBox extends StatelessWidget {
  const _FloatingBox({required this.loop, required this.size});
  final Animation<double> loop;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: loop,
        builder: (_, child) {
          final t = loop.value;
          final lift = -5 + 10 * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
          // A quick wobble in the middle of the loop, still otherwise.
          final w = t > 0.55 && t < 0.75 ? math.sin((t - 0.55) / 0.2 * 4 * math.pi) * (1 - (t - 0.55) / 0.2) : 0.0;
          // The shine crosses in the first 35 % of the loop.
          final p = -0.3 + (t / 0.35) * 1.6;
          return Transform.translate(
            offset: Offset(0, lift),
            child: Transform.rotate(
              angle: w * 0.07,
              child: ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0)],
                  stops: [(p - 0.12).clamp(0.0, 1.0), p.clamp(0.0, 1.0), (p + 0.12).clamp(0.0, 1.0)],
                ).createShader(rect),
                child: child,
              ),
            ),
          );
        },
        child: Image.asset('assets/titi/box_closed.png', width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      );
}
