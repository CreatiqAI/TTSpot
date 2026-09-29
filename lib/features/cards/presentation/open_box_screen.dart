import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../auth/data/auth_repository.dart';
import '../../share/share_card_renderer.dart';
import '../application/cards_providers.dart';
import '../domain/cards.dart';
import 'widgets/card_face.dart';

/// The reveal: shake, buzz, reveal.
///
/// Stage A (idle): the sealed box floats and tilts with the phone (TiltTracker).
/// Each shake (ShakeDetector) or tap on the box is one step of three: the phone
/// buzzes harder (Buzz.step), the box jolts, cracks and a golden glow spread
/// from the lid seam, and TiTi eggs you on. The server roll starts on the very
/// first step so the flip never waits on the network.
///
/// Stage B (burst): once the third step lands and the result is in, a white
/// flash, the open box blows up and fades while confetti flies in the rarity
/// colour, and the card drops in face-down and flips itself over.
///
/// Stage C (revealed): rarity glow, the card in a TiltCard you can still swipe
/// to flip, name and description, TiTi's verdict, and the footer actions.
/// Legendary pulls get a longer rumble, golden sparkles and a bigger glow.
///
/// This screen is also the last onboarding step, so leaving it may need to
/// refresh the profile provider before the router notices we are onboarded.
class OpenBoxScreen extends ConsumerStatefulWidget {
  const OpenBoxScreen({super.key, required this.boxId});
  final String boxId;

  @override
  ConsumerState<OpenBoxScreen> createState() => _OpenBoxScreenState();
}

enum _Stage { idle, burst, flip, revealed }

const _boxClosed = 'assets/titi/box_closed.png';
const _boxOpen = 'assets/titi/box_open.png';
const _crackColor = Color(0xFFFFF5C2);
const _seamGold = Color(0xFFFFD54A);
const _legendaryGold = Color(0xFFF4C542);
const _rarePurple = Color(0xFF9B5CFF);

class _OpenBoxScreenState extends ConsumerState<OpenBoxScreen> with TickerProviderStateMixin {
  static const _stepsToOpen = 3;

  _Stage _stage = _Stage.idle;
  int _steps = 0;
  Future<BoxResult>? _pending;
  BoxResult? _result;
  bool _waiting = false;

  // motion
  late final ShakeDetector _shaker = ShakeDetector(onShake: _advance);
  final TiltTracker _tilt = TiltTracker();
  StreamSubscription<Offset>? _tiltSub;
  final ValueNotifier<Offset> _tiltValue = ValueNotifier(Offset.zero);

  // animation
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);
  late final AnimationController _jolt = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final CurvedAnimation _pop = CurvedAnimation(parent: _reveal, curve: Curves.easeOutBack);
  late final AnimationController _sparkle = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  late final List<_Particle> _particles = List.generate(46, (i) => _Particle.random(i));

  @override
  void initState() {
    super.initState();
    _shaker.start();
    _tilt.start();
    _tiltSub = _tilt.stream.listen((o) => _tiltValue.value = o);
    _burst.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && _stage == _Stage.burst) {
        setState(() => _stage = _Stage.flip);
        _flip.forward(from: 0);
      }
    });
    _flip.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && _stage == _Stage.flip) {
        setState(() => _stage = _Stage.revealed);
        _reveal.forward(from: 0);
        HapticFeedback.heavyImpact();
        if (_result?.card.rarity == CardRarity.legendary) unawaited(Buzz.rumble());
      }
    });
  }

  @override
  void dispose() {
    _shaker.stop();
    _tiltSub?.cancel();
    _tilt.dispose();
    _tiltValue.dispose();
    _bob.dispose();
    _jolt.dispose();
    _flash.dispose();
    _burst.dispose();
    _flip.dispose();
    _pop.dispose();
    _reveal.dispose();
    _sparkle.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- steps ---

  /// One shake or tap. Starts the server roll on the first, escalates the
  /// buzz and the cracks, and on the third waits for the result then bursts.
  Future<void> _advance() async {
    if (_stage != _Stage.idle || _waiting) return;
    _pending ??= ref.read(cardsActionsProvider).openBox(widget.boxId);
    _steps++;
    unawaited(Buzz.step(_steps));
    _jolt.forward(from: 0);
    setState(() {});
    if (_steps < _stepsToOpen) return;

    _shaker.stop();
    setState(() => _waiting = true);
    try {
      _result = await _pending!;
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      setState(() {
        _waiting = false;
        _steps = 0;
        _pending = null;
      });
      // the box may be gone (already opened elsewhere): leave
      if (msg.contains('already opened') || msg.contains('not yours')) {
        _leave();
        return;
      }
      _shaker.start();
      return;
    }
    if (!mounted) return;
    _bob.stop();
    setState(() {
      _waiting = false;
      _stage = _Stage.burst;
    });
    _flash.forward(from: 0);
    _burst.forward(from: 0);
  }

  // ------------------------------------------------------------------ flip ---

  void _dragFlip(DragUpdateDetails d, double width) {
    if (_stage != _Stage.revealed) return;
    _flip.value = (_flip.value + d.primaryDelta! / (width * 0.9)).clamp(0.0, 1.0);
  }

  void _endFlip(DragEndDetails d) {
    if (_stage != _Stage.revealed) return;
    final v = d.primaryVelocity ?? 0;
    final forward = v > 400 || (v > -400 && _flip.value > 0.5);
    if (forward) {
      _flip.animateTo(1, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      _flip.animateBack(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    }
  }

  // ------------------------------------------------------------- navigation ---

  /// Close. When this is the end of onboarding the profile provider still
  /// says "not onboarded": refresh it and wait for the answer BEFORE moving,
  /// or the router bounces through /onboarding for a frame on the way out.
  Future<void> _leave() async {
    final onboarded = ref.read(currentProfileProvider).value?.isOnboarded == true;
    if (!onboarded) {
      ref.invalidate(currentProfileProvider);
      try {
        await ref.read(currentProfileProvider.future);
      } catch (_) {/* the router copes either way */}
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.map);
    }
  }

  void _openAnother() {
    final next = ref.read(sealedBoxesProvider).where((b) => b.id != widget.boxId).firstOrNull;
    if (next == null) return;
    context.pushReplacement(Routes.openBox(next.id));
  }

  void _share() {
    final c = _result?.card;
    if (c == null) return;
    showShareCardSheet(context, CardPullShareSpec(card: c));
  }

  // ----------------------------------------------------------------- helpers ---

  static Color _glowFor(CardRarity? r) => switch (r) {
        CardRarity.legendary => _legendaryGold,
        CardRarity.rare => _rarePurple,
        _ => Colors.white,
      };

  static String _verdict(CardRarity r) => switch (r) {
        CardRarity.legendary => 'First pull and you get the legendary. Show-off.',
        CardRarity.rare => 'Nice pull. Not many of these around.',
        CardRarity.common => 'Solid. Trade doubles with friends for the ones you\'re missing.',
      };

  String _shakeBubble() => switch (_steps) {
        0 => 'Give it a shake. Something\'s rattling in there.',
        1 => 'Keep going…',
        _ => 'One more!',
      };

  /// "LEGENDARY · 1 IN 20" from the admin odds; just the rarity when the
  /// odds are missing or round to 1 in 1.
  String _rarityLabel(CardRarity r) {
    final pct = ref.watch(cardSettingsProvider).value?.pct(r);
    final n = pct == null || pct <= 0 ? null : (100 / pct).round();
    final name = r.label.toUpperCase();
    return n == null || n < 2 ? name : '$name · 1 IN $n';
  }

  // ------------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardW = math.min(size.width * 0.58, 224.0);
    final boxW = math.min(size.width * 0.6, 230.0);
    final rarity = _result?.card.rarity;
    final moreBoxes = ref.watch(sealedBoxesProvider).where((b) => b.id != widget.boxId).length;
    final revealed = _stage == _Stage.revealed;
    final legendary = rarity == CardRarity.legendary;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          // rarity glow once revealed (longer + brighter for legendary)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_reveal, _sparkle]),
              builder: (_, _) {
                final t = Curves.easeOut.transform(_reveal.value);
                final pulse = 0.85 + 0.15 * math.sin(_sparkle.value * 2 * math.pi);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.2),
                      radius: (legendary ? 1.15 : 0.85) * pulse,
                      colors: [_glowFor(rarity).withValues(alpha: (legendary ? 0.6 : 0.45) * t), AppColors.ink.withValues(alpha: 0)],
                    ),
                  ),
                );
              },
            ),
          ),
          if (revealed && legendary) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _SparklePainter(_sparkle)))),
          SafeArea(
            child: Column(
              children: [
                _topRow(moreBoxes + 1),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: switch (_stage) {
                        _Stage.idle => _boxStage(boxW),
                        _ => _cardStage(cardW, boxW),
                      },
                    ),
                  ),
                ),
                _footer(moreBoxes),
              ],
            ),
          ),
          // white flash at the burst
          if (_stage == _Stage.burst)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _flash,
                  builder: (_, _) => Opacity(opacity: 1 - Curves.easeOut.transform(_flash.value), child: const ColoredBox(color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- top row ---

  Widget _topRow(int total) {
    const labelStyle = TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2.2);
    final Widget label;
    if (_waiting) {
      label = const SizedBox(key: ValueKey('wait'), width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
    } else if (_stage == _Stage.idle) {
      label = Column(
        key: ValueKey('idle$_steps'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_steps == 0 ? 'BLIND BOX · 1 OF $total' : '$_steps OF $_stepsToOpen SHAKES', style: labelStyle),
          if (_steps > 0) ...[const SizedBox(height: 6), _buzzMeter()],
        ],
      );
    } else if (_stage == _Stage.revealed) {
      label = FadeTransition(key: const ValueKey('rarity'), opacity: _reveal, child: Text(_rarityLabel(_result!.card.rarity), style: labelStyle));
    } else {
      label = const SizedBox(key: ValueKey('none'));
    }
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(icon: const Icon(AppIcons.x, color: Colors.white), onPressed: _leave),
          Expanded(child: Center(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: label))),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// Five bars; more light up with each step.
  Widget _buzzMeter() {
    final lit = (_steps * 5 / _stepsToOpen).ceil();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 14,
            height: 4,
            decoration: BoxDecoration(color: i < lit ? _seamGold : Colors.white24, borderRadius: BorderRadius.circular(999)),
          ),
      ],
    );
  }

  // --------------------------------------------------------------- stage A ---

  Widget _boxStage(double boxW) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const TitiAvatar(TitiPose.gift, size: 48, background: Colors.white),
              const SizedBox(width: 10),
              Flexible(child: TitiBubble(_shakeBubble(), dark: false, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _box(boxW),
        const SizedBox(height: 4),
        AnimatedBuilder(
          animation: _bob,
          builder: (_, child) => Opacity(opacity: 0.7 + 0.3 * _bob.value, child: child),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.vibrate, color: Colors.white, size: 24),
              SizedBox(width: 10),
              Text('SHAKE TO OPEN', style: TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 3, color: Colors.white, height: 1)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('or tap the box three times', style: TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }

  /// The floating, tilting, jolting box with its glow, rings and cracks.
  Widget _box(double boxW) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _advance,
      child: SizedBox(
        width: boxW * 1.7,
        height: boxW * 1.5,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // soft red glow
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(radius: 0.55, colors: [AppColors.brand.withValues(alpha: 0.35), AppColors.brand.withValues(alpha: 0)]),
                ),
              ),
            ),
            _ring(boxW * 1.22, 0.45),
            _ring(boxW * 1.5, 0.2),
            AnimatedBuilder(
              animation: Listenable.merge([_bob, _jolt, _tiltValue]),
              builder: (_, child) {
                final bob = (Curves.easeInOut.transform(_bob.value) * 2 - 1) * 8;
                final t = _jolt.value;
                final amp = 0.06 + 0.05 * _steps;
                final angle = math.sin(t * math.pi * 7) * amp * (1 - t);
                final scale = 1 + math.sin(t * math.pi) * 0.06;
                final tilt = _tiltValue.value;
                final m = Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(tilt.dy * 0.25)
                  ..rotateY(tilt.dx * 0.25)
                  ..rotateZ(angle)
                  ..scaleByDouble(scale, scale, 1, 1);
                return Transform.translate(
                  offset: Offset(0, bob),
                  child: Transform(alignment: Alignment.center, transform: m, child: child),
                );
              },
              child: SizedBox(
                width: boxW,
                height: boxW,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Image.asset(_boxClosed, width: boxW, height: boxW, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _jolt,
                        builder: (_, _) => CustomPaint(
                          painter: _CrackPainter(
                            cracks: _steps.clamp(0, 3),
                            // the motion lines fade over the first 300 ms of the 420 ms jolt
                            lineAlpha: _jolt.isAnimating ? (1 - _jolt.value * 420 / 300).clamp(0.0, 1.0) : 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ring(double size, double alpha) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.18),
            border: Border.all(color: AppColors.brand.withValues(alpha: alpha), width: 1.2),
          ),
        ),
      );

  // ----------------------------------------------------------- stage B + C ---

  Widget _cardStage(double cardW, double boxW) {
    final r = _result!;
    final cardH = cardW / kCardAspect;
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

    // the drop-in during the burst; steady once flipped
    final dropped = AnimatedBuilder(
      animation: _burst,
      builder: (_, child) {
        final t = Curves.easeOutBack.transform(((_burst.value - 0.3) / 0.7).clamp(0.0, 1.0));
        return Opacity(
          opacity: (t * 2).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, -(1 - t) * 240), child: child),
        );
      },
      child: card,
    );

    final cardArea = SizedBox(
      width: cardW,
      height: cardH,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (_stage == _Stage.burst) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: OverflowBox(
                  maxWidth: cardW * 2.4,
                  maxHeight: cardH * 1.6,
                  child: AnimatedBuilder(
                    animation: _burst,
                    builder: (_, _) => CustomPaint(painter: _BurstPainter(_burst.value, _particles, _glowFor(r.card.rarity))),
                  ),
                ),
              ),
            ),
            // the open box blows up and fades over the first 550 ms
            AnimatedBuilder(
              animation: _burst,
              builder: (_, child) {
                final body = Curves.easeInCubic.transform((_burst.value / 0.5).clamp(0.0, 1.0));
                return Opacity(opacity: (1 - body).clamp(0.0, 1.0), child: Transform.scale(scale: 1 + body * 0.25, child: child));
              },
              child: Image.asset(_boxOpen, width: boxW, height: boxW, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            ),
          ],
          if (revealed)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => _dragFlip(d, cardW),
              onHorizontalDragEnd: _endFlip,
              child: SizedBox(width: cardW, height: cardH, child: TiltCard(child: card)),
            )
          else
            dropped,
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        cardArea,
        const SizedBox(height: 22),
        // name, description, count and TiTi's verdict slide in on reveal
        AnimatedBuilder(
          animation: _reveal,
          builder: (_, child) {
            final t = Curves.easeOutCubic.transform(_reveal.value);
            return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child));
          },
          child: revealed
              ? Column(
                  children: [
                    Text(r.card.name, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                    if (r.card.description != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(r.card.description!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      r.isNew ? 'NEW · first one in your collection' : 'You now have ${r.held} of these',
                      style: TextStyle(color: r.isNew ? AppColors.brand : Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const TitiAvatar(TitiPose.celebrate, size: 48, background: Colors.white),
                          const SizedBox(width: 10),
                          Flexible(child: TitiBubble(_verdict(r.card.rarity), dark: false, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                )
              // roughly the height of the text block, so the card barely moves on reveal
              : const SizedBox(height: 200),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- footer ---

  Widget _footer(int moreBoxes) {
    if (_stage != _Stage.revealed) {
      // three dots: one per shake
      final filled = _stage == _Stage.idle ? _steps : _stepsToOpen;
      return Padding(
        padding: const EdgeInsets.only(bottom: 28, top: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _stepsToOpen; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i < filled ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(color: i < filled ? AppColors.brand : Colors.white24, borderRadius: BorderRadius.circular(999)),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _pop,
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink, minimumSize: const Size(0, 54)),
                    onPressed: _leave,
                    child: const Text('Add to my cards'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 54,
                  height: 54,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _share,
                    child: const Icon(AppIcons.export, size: 22),
                  ),
                ),
              ],
            ),
          ),
          if (moreBoxes > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), minimumSize: const Size(0, 48)),
                onPressed: _openAnother,
                child: Text('Open another ($moreBoxes)'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Swipe the card to see the back · 7 to collect', style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Cracks spreading from the lid seam, a golden glow leaking out of it, and
/// short white motion lines either side of the box while it jolts.
class _CrackPainter extends CustomPainter {
  const _CrackPainter({required this.cracks, required this.lineAlpha});
  final int cracks; // 0..3
  final double lineAlpha; // 0..1, motion lines

  @override
  void paint(Canvas canvas, Size size) {
    if (cracks <= 0) return;
    // the lid seam sits about 40% down the render
    final seam = Offset(size.width / 2, size.height * 0.4);

    // gold glow leaking out of the seam; wider with every step
    final glowR = size.width * (0.07 + 0.06 * cracks);
    final glow = Paint()
      ..color = _seamGold.withValues(alpha: 0.55 + 0.15 * cracks)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowR * 0.7);
    canvas.drawOval(Rect.fromCenter(center: seam, width: glowR * 3.2, height: glowR * 1.1), glow);

    // jagged cracks; seeded so they only grow, never reshuffle
    final stroke = Paint()
      ..color = _crackColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final rnd = math.Random(11);
    for (var i = 0; i < cracks; i++) {
      final dir = i.isEven ? 1.0 : -1.0;
      var pt = seam + Offset(dir * size.width * (0.04 + rnd.nextDouble() * 0.12), 0);
      final path = Path()..moveTo(pt.dx, pt.dy);
      final segs = 3 + rnd.nextInt(3);
      for (var k = 0; k < segs; k++) {
        pt = pt + Offset(dir * size.width * (0.03 + rnd.nextDouble() * 0.08), size.height * (0.03 + rnd.nextDouble() * 0.09) * (rnd.nextBool() ? 1 : -0.6));
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, stroke);
    }

    // motion lines: cracks per side, fading with the jolt
    if (lineAlpha <= 0) return;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: lineAlpha)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final len = size.width * 0.12;
    for (var i = 0; i < cracks; i++) {
      final y = size.height * (0.32 + 0.14 * i);
      canvas.drawLine(Offset(-size.width * 0.06, y), Offset(-size.width * 0.06 - len, y), line);
      canvas.drawLine(Offset(size.width * 1.06, y), Offset(size.width * 1.06 + len, y), line);
    }
  }

  @override
  bool shouldRepaint(_CrackPainter old) => old.cracks != cracks || old.lineAlpha != lineAlpha;
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

/// Confetti and a flash ring in the rarity colour, flying out of the box.
class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.t, this.particles, this.accent);
  final double t;
  final List<_Particle> particles;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final c = Offset(size.width / 2, size.height * 0.5);
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
