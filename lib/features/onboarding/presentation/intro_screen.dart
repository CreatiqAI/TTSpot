import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/light_trails.dart';
import '../../auth/presentation/widgets/dark_auth.dart';

/// Two slides before sign-up (Intro1.dc.html, Intro2.dc.html): Never miss a
/// meet, with three glass cards rising in; Your crew, live, with TiTi in a
/// pulsing ring and five friends orbiting him. Always dark. Welcome → Get
/// started → here → Continue, Continue → Create an account. Skip (top right)
/// goes straight to Create an account. Settings → About replays it; then the
/// last button says Done and just pops.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, this.replay = false});
  /// Opened from Settings: pop at the end instead of going to sign-up.
  final bool replay;

  static const pages = 2;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  final _page = PageController();
  int _index = 0;
  /// Breathes the Continue pill's glow (3 s).
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    _glow.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    _page.dispose();
    super.dispose();
  }

  void _finish() {
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    HapticFeedback.lightImpact();
    context.push(Routes.signUp);
  }

  void _next() {
    if (_index >= IntroScreen.pages - 1) return _finish();
    _page.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _glow.isAnimating) _glow.stop();
    final last = _index == IntroScreen.pages - 1;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return AuthPage(
      lift: 0.28,
      liftHeight: 0.4,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20)),
                  child: Text(widget.replay && last ? '' : 'Skip', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7))),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  // The light trails live in a band under the copy, above the
                  // dots, where no text sits. Gone on a very short screen.
                  final band = (c.maxHeight * 0.14).clamp(0.0, 120.0);
                  return Stack(
                    children: [
                      if (band >= 56) Positioned(left: 0, right: 0, bottom: 0, height: band, child: const LightTrails()),
                      PageView(
                        controller: _page,
                        onPageChanged: (i) => setState(() => _index = i),
                        children: [
                          _MeetsSlide(reserve: band),
                          _CrewSlide(reserve: band),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 10, 24, 24 + bottomPad),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < IntroScreen.pages; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _index ? 26 : 8,
                          height: 8,
                          decoration: BoxDecoration(color: i == _index ? Colors.white : Colors.white.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  AnimatedBuilder(
                    animation: _glow,
                    builder: (_, _) => AuthPill(
                      label: widget.replay && last ? 'Done' : 'Continue',
                      onPressed: _next,
                      glow: still ? 0.3 : Curves.easeInOut.transform(_glow.value),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The copy under a slide's picture.
class _SlideText extends StatelessWidget {
  const _SlideText({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            Text(title, textAlign: TextAlign.center, style: AuthDark.display(40)),
            const SizedBox(height: 10),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 23 / 16, color: AuthDark.text)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────── 1. never miss a meet ──

class _MeetsSlide extends StatefulWidget {
  const _MeetsSlide({required this.reserve});
  /// Space kept clear at the bottom for the light trails.
  final double reserve;

  @override
  State<_MeetsSlide> createState() => _MeetsSlideState();
}

class _MeetsSlideState extends State<_MeetsSlide> with SingleTickerProviderStateMixin {
  // One 6 s loop; each card reads its own phase a quarter second after the
  // one above. The first time round, a card waits for its turn.
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _loop.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _first = false;
        _loop.forward(from: 0);
      }
    });
    _loop.forward();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _loop.isAnimating) {
      _loop.stop();
      _loop.value = 0.5;
      _first = false;
    }
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: AnimatedBuilder(
                animation: _loop,
                builder: (_, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _CardLoop(phase: _phase(i), child: _cards[i](_loop.value)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const _SlideText(title: 'NEVER MISS A MEET', body: "Tonight's TT, weekend convoys and new spots, all on one map."),
        SizedBox(height: widget.reserve),
      ],
    );
  }

  /// Where card [i] is in its own 6 s loop, or null before its first entrance.
  double? _phase(int i) {
    final delay = i * 0.25 / 6;
    final v = _loop.value - delay;
    if (v < 0) return _first ? null : v + 1;
    return v;
  }

  static final _cards = <Widget Function(double t)>[
    (t) => _GlassCard(
          leading: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/covers/tt.jpg', width: 54, height: 54, fit: BoxFit.cover, cacheWidth: 162)),
          title: 'TT at the mamak',
          subtitle: 'Tonight, 9:30 PM · Bukit Jalil',
          trailing: _Live(t: t),
        ),
    (_) => _GlassCard(
          leading: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/covers/convoy.jpg', width: 54, height: 54, fit: BoxFit.cover, cacheWidth: 162)),
          title: 'Sunrise convoy',
          subtitle: 'Saturday, 6:00 AM · Genting',
          trailing: const _Stat(value: '18', label: 'GOING', color: Color(0xFFFFB648)),
        ),
    (_) => _GlassCard(
          leading: Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFF14161C), borderRadius: BorderRadius.circular(14)),
            child: const Icon(AppIcons.mapPin, size: 26, color: Color(0xFF5CC8FF)),
          ),
          title: 'New spot nearby',
          subtitle: 'Car cafe · 2.4 km from you',
          trailing: const _Stat(value: '+20', label: 'POINTS', color: Color(0xFF5CC8FF)),
        ),
  ];
}

/// CSS `cardloop`: 0 → 10 % rise in (26 px, scale .96, fade), hold to 86 %,
/// then drift up 10 px and fade by 100 %.
class _CardLoop extends StatelessWidget {
  const _CardLoop({required this.phase, required this.child});
  final double? phase;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = phase;
    if (p == null) return Opacity(opacity: 0, child: child);
    double opacity, dy, scale;
    if (p < 0.10) {
      final k = Curves.easeOut.transform(p / 0.10);
      opacity = k;
      dy = 26 * (1 - k);
      scale = 0.96 + 0.04 * k;
    } else if (p < 0.86) {
      opacity = 1;
      dy = 0;
      scale = 1;
    } else {
      final k = Curves.easeIn.transform((p - 0.86) / 0.14);
      opacity = 1 - k;
      dy = -10 * k;
      scale = 1;
    }
    return Opacity(
      opacity: opacity.clamp(0, 1),
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Transform.scale(scale: scale, child: child),
      ),
    );
  }
}

/// A frosted row: picture, two lines, a figure on the right. Gradient glass
/// (no BackdropFilter: there is nothing behind it to blur).
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.leading, required this.title, required this.subtitle, required this.trailing});
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.13), Colors.white.withValues(alpha: 0.04)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.72))),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      );
}

/// A blinking dot and LIVE (1.2 s).
class _Live extends StatelessWidget {
  const _Live({required this.t});
  /// The loop's 0..1 value; the blink is derived from it.
  final double t;

  @override
  Widget build(BuildContext context) {
    // 6 s loop / 1.2 s blink = 5 blinks per loop; 1 → .3 → 1.
    final blink = 0.65 + 0.35 * math.cos(t * 5 * 2 * math.pi);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: blink.clamp(0.3, 1),
          child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AuthDark.link, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 6),
        const Text('LIVE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: AuthDark.link)),
      ],
    );
  }
}

/// "18 / GOING", "+20 / POINTS".
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: AuthDark.display(26, color: color).copyWith(height: 22 / 26)),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1, color: Colors.white.withValues(alpha: 0.72))),
        ],
      );
}

// ────────────────────────────────────────────────────────── 2. your crew, live ──

class _CrewSlide extends StatefulWidget {
  const _CrewSlide({required this.reserve});
  final double reserve;

  @override
  State<_CrewSlide> createState() => _CrewSlideState();
}

class _CrewSlideState extends State<_CrewSlide> with TickerProviderStateMixin {
  /// One orbit in 36 s.
  late final AnimationController _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 36));
  /// The two red rings, 3 s, the second half a cycle behind.
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  static const _glows = [Color(0xFF3CDC8C), Color(0xFF966EFF), Color(0xFF5CC8FF), Color(0xFF5082FF), Color(0xFFFF963C)];

  @override
  void initState() {
    super.initState();
    _orbit.repeat();
    _ring.repeat();
  }

  @override
  void dispose() {
    _orbit.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      if (_orbit.isAnimating) _orbit.stop();
      if (_ring.isAnimating) _ring.stop();
    }
    return Column(
      children: [
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, c) {
                // 280 on a 390 wide phone; smaller when the slide is short.
                final box = math.min(math.min(c.maxWidth - 110, c.maxHeight - 16), 280.0);
                if (box < 120) return const SizedBox.shrink();
                final s = box / 280;
                final r = 120 * s;
                final av = 64 * s;
                return SizedBox(
                  width: box,
                  height: box,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_orbit, _ring]),
                    builder: (_, _) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(child: CustomPaint(painter: _RingsPainter(t: _ring.value, inset: 20 * s))),
                        Center(child: Titi(TitiPose.wave, height: 130 * s)),
                        for (var i = 0; i < 5; i++)
                          _onOrbit(i, box: box, r: r, size: av, angle: -math.pi / 2 + i * 2 * math.pi / 5 + _orbit.value * 2 * math.pi, s: s),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const _SlideText(title: 'YOUR CREW, LIVE', body: 'See which friends are out tonight, scan a QR to add them, and roll in together.'),
        SizedBox(height: widget.reserve),
      ],
    );
  }

  /// An avatar on the ring. Placed by angle, so it is always upright.
  Widget _onOrbit(int i, {required double box, required double r, required double size, required double angle, required double s}) {
    final cx = box / 2 + r * math.cos(angle);
    final cy = box / 2 + r * math.sin(angle);
    return Positioned(
      left: cx - size / 2,
      top: cy - size / 2,
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3 * s),
          boxShadow: [BoxShadow(color: _glows[i].withValues(alpha: 0.8), blurRadius: 22 * s)],
          image: DecorationImage(image: ResizeImage(AssetImage('assets/avatars/a${i + 1}.png'), width: 192), fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// The thin standing ring plus two red pulses (scale .55 → 1.25, fading).
class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.t, required this.inset});
  final double t;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - inset;
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.16));
    for (final offset in [0.0, 0.5]) {
      final p = (t + offset) % 1;
      final k = Curves.easeOut.transform(p);
      final scale = 0.55 + 0.70 * k;
      canvas.drawCircle(c, r * scale, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = AppColors.brand.withValues(alpha: 0.7 * (1 - k)));
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.inset != inset;
}
