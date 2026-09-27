import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/cards_providers.dart';
import '../domain/cards.dart';
import 'widgets/card_face.dart';

/// The reveal. Tap the box three times to crack it (each tap shakes harder),
/// the lid blows off, a card rises face-down, and you swipe to flip it. The
/// roll happens on the server on the first tap so the flip never waits.
class OpenBoxScreen extends ConsumerStatefulWidget {
  const OpenBoxScreen({super.key, required this.boxId});
  final String boxId;

  @override
  ConsumerState<OpenBoxScreen> createState() => _OpenBoxScreenState();
}

enum _Stage { box, burst, flip, revealed }

class _OpenBoxScreenState extends ConsumerState<OpenBoxScreen> with TickerProviderStateMixin {
  static const _tapsToOpen = 3;

  _Stage _stage = _Stage.box;
  int _taps = 0;
  Future<BoxResult>? _pending;
  BoxResult? _result;
  bool _waiting = false;

  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _sparkle = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  late final AnimationController _hint = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  late final List<_Particle> _particles = List.generate(46, (i) => _Particle.random(i));
  bool _dragged = false;

  @override
  void initState() {
    super.initState();
    _burst.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _stage = _Stage.flip);
    });
    _flip.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && _stage == _Stage.flip) {
        setState(() => _stage = _Stage.revealed);
        _reveal.forward(from: 0);
        HapticFeedback.heavyImpact();
        if (_result?.card.rarity == CardRarity.legendary) {
          Future.delayed(const Duration(milliseconds: 220), HapticFeedback.heavyImpact);
          Future.delayed(const Duration(milliseconds: 440), HapticFeedback.heavyImpact);
        }
      }
    });
  }

  @override
  void dispose() {
    _shake.dispose();
    _burst.dispose();
    _flip.dispose();
    _reveal.dispose();
    _sparkle.dispose();
    _hint.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ box ---

  Future<void> _tapBox() async {
    if (_stage != _Stage.box || _waiting) return;
    _pending ??= ref.read(cardsActionsProvider).openBox(widget.boxId);
    _taps++;
    HapticFeedback.mediumImpact();
    _shake.forward(from: 0);
    setState(() {});
    if (_taps < _tapsToOpen) return;
    setState(() => _waiting = true);
    try {
      _result = await _pending!;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      setState(() {
        _waiting = false;
        _taps = 0;
        _pending = null;
      });
      // the box may be gone (already opened elsewhere): leave
      if (friendlyError(e).contains('already opened') || friendlyError(e).contains('not yours')) context.pop();
      return;
    }
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _waiting = false;
      _stage = _Stage.burst;
    });
    _burst.forward(from: 0);
  }

  // ----------------------------------------------------------------- flip ---

  void _dragFlip(DragUpdateDetails d, double width) {
    if (_stage != _Stage.flip) return;
    _dragged = true;
    _flip.value = (_flip.value + d.primaryDelta! / (width * 0.9)).clamp(0.0, 1.0);
  }

  void _endFlip(DragEndDetails d) {
    if (_stage != _Stage.flip) return;
    final v = d.primaryVelocity ?? 0;
    if (_flip.value > 0.45 || v > 500) {
      _flip.fling(velocity: 1.6);
    } else if (v < -500 || _flip.value <= 0.45) {
      _flip.animateBack(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    }
  }

  void _openAnother() {
    final next = ref.read(sealedBoxesProvider).where((b) => b.id != widget.boxId).firstOrNull;
    if (next == null) return;
    context.pushReplacement(Routes.openBox(next.id));
  }

  // ---------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardW = math.min(size.width * 0.62, 250.0);
    final rarity = _result?.card.rarity;
    final moreBoxes = ref.watch(sealedBoxesProvider).where((b) => b.id != widget.boxId).length;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          // rarity glow once revealed
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_reveal, _sparkle]),
              builder: (_, _) {
                final t = Curves.easeOut.transform(_reveal.value);
                final pulse = 0.85 + 0.15 * math.sin(_sparkle.value * 2 * math.pi);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.15),
                      radius: 0.9 * pulse,
                      colors: [(rarity?.color ?? AppColors.brand).withValues(alpha: 0.55 * t), AppColors.ink.withValues(alpha: 0)],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_stage == _Stage.revealed && rarity == CardRarity.legendary)
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _SparklePainter(_sparkle)))),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(icon: const Icon(AppIcons.x, color: Colors.white), onPressed: () => context.pop()),
                    const Spacer(),
                    if (moreBoxes > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text('$moreBoxes more box${moreBoxes == 1 ? '' : 'es'}', style: const TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: switch (_stage) {
                      _Stage.box => _boxStage(cardW),
                      _Stage.burst => _burstStage(cardW),
                      _Stage.flip || _Stage.revealed => _cardStage(cardW),
                    },
                  ),
                ),
                _footer(cardW, moreBoxes),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _boxStage(double cardW) {
    final boxW = cardW * 0.9;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _tapBox,
          child: AnimatedBuilder(
            animation: _shake,
            builder: (_, child) {
              final t = _shake.value;
              final amp = 0.06 + _taps * 0.05;
              final angle = math.sin(t * math.pi * 7) * amp * (1 - t);
              final scale = 1 + math.sin(t * math.pi) * 0.06;
              return Transform.rotate(angle: angle, child: Transform.scale(scale: scale, child: child));
            },
            child: _BlindBox(width: boxW, cracks: _taps / _tapsToOpen, lidLift: 0, lidOpacity: 1, bodyOpacity: 1),
          ),
        ),
        const SizedBox(height: 36),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _waiting
              ? const SizedBox(key: ValueKey('w'), width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Column(
                  key: ValueKey(_taps),
                  children: [
                    Text(
                      switch (_taps) { 0 => 'Tap the box to crack it open', 1 => 'Again!', _ => 'One more…' },
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _tapsToOpen; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i < _taps ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(color: i < _taps ? AppColors.brand : Colors.white24, borderRadius: BorderRadius.circular(999)),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _burstStage(double cardW) {
    final boxW = cardW * 0.9;
    return AnimatedBuilder(
      animation: _burst,
      builder: (_, _) {
        final t = _burst.value;
        final lid = Curves.easeOutCubic.transform(t);
        final body = Curves.easeInCubic.transform((t / 0.55).clamp(0, 1));
        final card = Curves.easeOutBack.transform(((t - 0.35) / 0.65).clamp(0, 1));
        return SizedBox(
          width: cardW * 1.8,
          height: cardW / kCardAspect + 80,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: _BurstPainter(t, _particles, _result?.card.rarity.color ?? AppColors.brand))),
              Opacity(
                opacity: card.clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(0, (1 - card) * 90),
                  child: Transform.scale(scale: 0.55 + 0.45 * card, child: CardBack(width: cardW)),
                ),
              ),
              Transform.scale(
                scale: 1 + body * 0.25,
                child: Opacity(
                  opacity: (1 - body).clamp(0, 1),
                  child: _BlindBox(width: boxW, cracks: 1, lidLift: lid * 260, lidOpacity: (1 - lid).clamp(0, 1), bodyOpacity: 1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cardStage(double cardW) {
    final r = _result!;
    final revealed = _stage == _Stage.revealed;
    final card = AnimatedBuilder(
      animation: _flip,
      builder: (_, _) {
        final angle = _flip.value * math.pi;
        final showFront = angle > math.pi / 2;
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateY(showFront ? angle - math.pi : angle);
        return Transform(
          alignment: Alignment.center,
          transform: m,
          child: showFront ? CardFace(card: r.card, width: cardW) : CardBack(width: cardW),
        );
      },
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (revealed)
          SizedBox(width: cardW, height: cardW / kCardAspect, child: TiltCard(child: card))
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => _dragFlip(d, cardW),
            onHorizontalDragEnd: _endFlip,
            onTap: () => _flip.fling(velocity: 1.4),
            child: card,
          ),
        const SizedBox(height: 26),
        if (!revealed)
          AnimatedBuilder(
            animation: _hint,
            builder: (_, _) => Opacity(
              opacity: _dragged ? 0 : 0.5 + 0.5 * _hint.value,
              child: Transform.translate(
                offset: Offset(_hint.value * 14 - 7, 0),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.arrowRight, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Swipe to flip', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          )
        else
          AnimatedBuilder(
            animation: _reveal,
            builder: (_, child) {
              final t = Curves.easeOutCubic.transform(_reveal.value);
              return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child));
            },
            child: Column(
              children: [
                RarityPill(rarity: r.card.rarity, scale: 1.3),
                const SizedBox(height: 10),
                Text(r.card.name, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                const SizedBox(height: 6),
                Text(
                  r.isNew ? 'NEW · first one in your collection' : 'You now have ${r.held} of these',
                  style: TextStyle(color: r.isNew ? AppColors.brand : Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                if (r.card.description != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(r.card.description!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4)),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _footer(double cardW, int moreBoxes) {
    if (_stage != _Stage.revealed) return const SizedBox(height: 72);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
              onPressed: () => context.pop(),
              child: const Text('Keep it'),
            ),
          ),
          if (moreBoxes > 0) ...[
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _openAnother,
                child: Text('Open another ($moreBoxes)'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A red box with a black ribbon and a lid. Cracks appear as taps land.
class _BlindBox extends StatelessWidget {
  const _BlindBox({required this.width, required this.cracks, required this.lidLift, required this.lidOpacity, required this.bodyOpacity});
  final double width;
  final double cracks; // 0..1
  final double lidLift;
  final double lidOpacity;
  final double bodyOpacity;

  @override
  Widget build(BuildContext context) {
    final h = width * 0.82;
    final lidH = width * 0.2;
    final ribbon = width * 0.14;
    return SizedBox(
      width: width * 1.2,
      height: h + lidH + 60,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // body
          Opacity(
            opacity: bodyOpacity,
            child: Container(
              width: width,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width * 0.07),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF3B3B), AppColors.brand, AppColors.brandDeep]),
                boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, 16))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned(left: (width - ribbon) / 2, top: 0, bottom: 0, child: Container(width: ribbon, color: AppColors.ink)),
                  Positioned(left: 0, right: 0, top: (h - ribbon) / 2, child: Container(height: ribbon, color: AppColors.ink)),
                  Positioned.fill(child: CustomPaint(painter: _CracksPainter(cracks))),
                  Center(
                    child: Text('?', style: TextStyle(fontFamily: AppFonts.display, fontSize: width * 0.3, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.9), height: 1)),
                  ),
                ],
              ),
            ),
          ),
          // lid
          Positioned(
            bottom: h - lidH * 0.35 + lidLift,
            child: Opacity(
              opacity: lidOpacity,
              child: Transform.rotate(
                angle: -lidLift / 400,
                child: Container(
                  width: width * 1.12,
                  height: lidH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(width * 0.05),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF5A5A), AppColors.brand]),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 8))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned(left: (width * 1.12 - ribbon) / 2, top: 0, bottom: 0, child: Container(width: ribbon, color: AppColors.ink)),
                      // bow
                      Positioned(
                        left: (width * 1.12 - ribbon * 2.6) / 2,
                        top: -ribbon * 0.4,
                        child: Row(
                          children: [
                            _bowLoop(ribbon, true),
                            SizedBox(width: ribbon * 0.2),
                            _bowLoop(ribbon, false),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bowLoop(double ribbon, bool left) => Transform.rotate(
        angle: left ? -0.5 : 0.5,
        child: Container(
          width: ribbon * 1.2,
          height: ribbon * 0.8,
          decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white24, width: 1.5)),
        ),
      );
}

class _CracksPainter extends CustomPainter {
  const _CracksPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final rnd = math.Random(7);
    final n = (t * 9).round();
    for (var i = 0; i < n; i++) {
      final start = Offset(size.width * (0.2 + rnd.nextDouble() * 0.6), size.height * (0.2 + rnd.nextDouble() * 0.6));
      final path = Path()..moveTo(start.dx, start.dy);
      var pt = start;
      for (var k = 0; k < 4; k++) {
        pt = pt + Offset((rnd.nextDouble() - 0.5) * size.width * 0.25, (rnd.nextDouble() - 0.5) * size.height * 0.25);
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_CracksPainter old) => old.t != t;
}

class _Particle {
  _Particle(this.angle, this.speed, this.size, this.color, this.spin);
  final double angle, speed, size, spin;
  final Color color;

  static _Particle random(int i) {
    final r = math.Random(i * 31 + 3);
    const palette = [AppColors.brand, Color(0xFFFFC532), Colors.white, Color(0xFF2B7CFF), Color(0xFF4CC38A)];
    return _Particle(r.nextDouble() * 2 * math.pi, 140 + r.nextDouble() * 260, 5 + r.nextDouble() * 9, palette[i % palette.length], r.nextDouble() * 6);
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.t, this.particles, this.accent);
  final double t;
  final List<_Particle> particles;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final c = Offset(size.width / 2, size.height * 0.62);
    // flash ring
    final ring = Paint()
      ..color = accent.withValues(alpha: (1 - t).clamp(0, 1) * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14 * (1 - t) + 1;
    canvas.drawCircle(c, 30 + t * size.width * 0.9, ring);
    final e = Curves.easeOutCubic.transform(t);
    for (final p in particles) {
      final d = p.speed * e;
      final pos = c + Offset(math.cos(p.angle) * d, math.sin(p.angle) * d + 160 * t * t); // gravity
      final paint = Paint()..color = p.color.withValues(alpha: (1 - t).clamp(0, 1));
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t * 3);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6), const Radius.circular(1.5)), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// Slow golden sparkles for the legendary reveal.
class _SparklePainter extends CustomPainter {
  _SparklePainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(99);
    for (var i = 0; i < 36; i++) {
      final x = rnd.nextDouble() * size.width;
      final base = rnd.nextDouble();
      final y = ((base - anim.value * (0.3 + rnd.nextDouble() * 0.4)) % 1.0) * size.height;
      final phase = (anim.value * 3 + rnd.nextDouble()) % 1.0;
      final a = (math.sin(phase * math.pi)).clamp(0.0, 1.0);
      final s = 2 + rnd.nextDouble() * 3;
      final p = Paint()..color = const Color(0xFFFFD866).withValues(alpha: a * 0.9);
      final path = Path()
        ..moveTo(x, y - s * 2)
        ..lineTo(x + s * 0.6, y)
        ..lineTo(x, y + s * 2)
        ..lineTo(x - s * 0.6, y)
        ..close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => false;
}
