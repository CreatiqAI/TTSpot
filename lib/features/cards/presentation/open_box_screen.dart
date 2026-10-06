import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart' show VelocityTracker, kTouchSlop;
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
import '../../../core/widgets/glass.dart';
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
/// Stage C (revealed): rarity glow, the card in a TiltCard that turns over
/// on every swipe (either way) or tap, name and description, TiTi's verdict,
/// and a big red "Add to my cards" that rises in and breathes. Pressing it
/// flies the card down into the button ("My cards", +1) and closes.
/// Rare glows silver. Secret (legendary) pulls get a longer rumble, golden
/// sparkles and a bigger gold glow.
///
/// Leaving never loses a card: `open_box()` adds it to `user_cards` and
/// marks the box opened in the same transaction, on the first shake, before
/// anything is shown. "Add to my cards" is the celebration, not a save. So
/// once it is revealed, every way out (the X, a tap outside the card, back,
/// a swipe down) plays the same flight, quicker, and closes.
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

/// QA only: `/cards/box/preview` (ttspot://cards/box/preview) runs the whole
/// reveal on a sample card without the server: no box, no roll, nothing
/// saved. Debug builds and the local release smoke test only; store builds
/// compile it out (both flags are const false there).
const kOpenBoxPreviewId = 'preview';
const _canPreview = kDebugMode || bool.fromEnvironment('LOCAL_RELEASE_TEST');

class _OpenBoxScreenState extends ConsumerState<OpenBoxScreen> with TickerProviderStateMixin {
  static const _stepsToOpen = 3;

  /// "Add to my cards": the flight into the button, its bump, a beat on "Saved".
  static const _collectSlow = Duration(milliseconds: 1100);
  /// Any other way out after the reveal: the same flight, quicker.
  static const _collectFast = Duration(milliseconds: 700);
  /// Where in [_collect] the card lands in the button.
  static const _landAt = 0.66;
  /// A drag down this far (from outside the card) closes.
  static const _pullToClose = 90.0;

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

  // stage C
  /// The revealed card's turn in half turns: even = front, odd = back. No
  /// bounds, so it keeps turning over either way for as long as you like.
  late final AnimationController _turn = AnimationController.unbounded(vsync: this);
  /// Where [_turn] is heading (a whole number).
  double _turnTarget = 0;
  double _dragFrom = 0;
  /// "Add to my cards" rising in once the card has settled.
  late final AnimationController _cta = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  /// Its slow breath and the shine across it.
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  /// The card flying into "My cards" on the way out.
  late final AnimationController _collect = AnimationController(vsync: this, duration: _collectSlow);
  /// Swipe down to close: how far the page is pulled.
  late final AnimationController _pull = AnimationController.unbounded(vsync: this);
  bool _collecting = false;
  bool _landed = false;
  bool _leaving = false;
  /// The card's box when the flight started (in [_stackKey]'s space) and
  /// the way to the button's centre.
  Rect? _flyFrom;
  Offset _flyDelta = Offset.zero;
  int? _pullPointer;
  Offset _pullStart = Offset.zero;
  final _stackKey = GlobalKey();
  final _cardKey = GlobalKey();
  final _targetKey = GlobalKey();
  final _scroll = ScrollController();

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
        _turn.value = 0;
        _turnTarget = 0;
        setState(() => _stage = _Stage.revealed);
        _reveal.forward(from: 0);
        _cta.forward(from: 0);
        HapticFeedback.heavyImpact();
        if (_result?.card.rarity == CardRarity.legendary) unawaited(Buzz.rumble());
      }
    });
    _cta.addStatusListener((s) {
      if (s != AnimationStatus.completed || !mounted || _collecting) return;
      if (!MediaQuery.disableAnimationsOf(context)) _pulse.repeat();
    });
    _collect.addListener(() {
      if (_landed || _collect.value < _landAt || !mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _landed = true);
    });
    _collect.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) _leave();
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
    _turn.dispose();
    _cta.dispose();
    _pulse.dispose();
    _collect.dispose();
    _pull.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- steps ---

  /// One shake or tap. Starts the server roll on the first, escalates the
  /// buzz and the cracks, and on the third waits for the result then bursts.
  Future<void> _advance() async {
    if (_stage != _Stage.idle || _waiting || _leaving) return;
    _pending ??= _canPreview && widget.boxId == kOpenBoxPreviewId ? _previewResult() : ref.read(cardsActionsProvider).openBox(widget.boxId);
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

  /// The preview's card: one of the live designs when they have loaded (a
  /// different one most times), else card 1's art.
  Future<BoxResult> _previewResult() async {
    var all = const <CardType>[];
    try {
      all = await ref.read(cardTypesProvider.future);
    } catch (_) {/* the placeholder below */}
    final types = [for (final t in all) if (t.active) t];
    final card = types.isEmpty
        ? const CardType(id: 'c1', setId: 'preview', number: 1, name: 'Preview', rarity: CardRarity.common, color: Color(0xFF9AA0A8), active: true, sort: 1)
        : types[DateTime.now().millisecond % types.length];
    return BoxResult(userCardId: 'preview', card: card, held: 1);
  }

  // ------------------------------------------------------------------ flip ---

  bool get _canFlip => _stage == _Stage.revealed && !_collecting;

  // Swipes on the card come from raw pointer events, not a drag recognizer:
  // the card's finger tilt (TiltCard's pan) would otherwise win the gesture
  // arena on a fast flick whose first move already passes the pan slop, and
  // that swipe would not turn the card. This way both happen at once.
  int? _flipPointer;
  Offset _flipDown = Offset.zero;
  bool _flipDragging = false;
  VelocityTracker? _flipVelocity;

  void _cardDown(PointerDownEvent e) {
    if (!_canFlip || _flipPointer != null) return;
    _flipPointer = e.pointer;
    _flipDown = e.position;
    _flipDragging = false;
    _flipVelocity = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
  }

  /// Once the finger has moved sideways past the touch slop the card
  /// follows it, at most one turn per swipe.
  void _cardMove(PointerMoveEvent e, double width) {
    if (e.pointer != _flipPointer || !_canFlip) return;
    _flipVelocity?.addPosition(e.timeStamp, e.position);
    final d = e.position - _flipDown;
    if (!_flipDragging) {
      if (d.dx.abs() < kTouchSlop || d.dx.abs() < d.dy.abs()) return;
      _flipDragging = true;
      _turn.stop();
      _dragFrom = _turn.value.roundToDouble();
    }
    _turn.value = (_dragFrom + d.dx / (width * 0.9)).clamp(_dragFrom - 1, _dragFrom + 1);
  }

  /// A flick turns it over that way; a slow drag past halfway does too;
  /// anything less springs back.
  void _cardUp(PointerUpEvent e) {
    if (e.pointer != _flipPointer) return;
    _flipPointer = null;
    if (!_flipDragging) return;
    _flipDragging = false;
    if (!_canFlip) return;
    final v = _flipVelocity?.getVelocity().pixelsPerSecond.dx ?? 0;
    final step = v.abs() > 350 ? v.sign : (_turn.value - _dragFrom).roundToDouble();
    _turnTo(_dragFrom + step);
  }

  void _cardCancel(PointerCancelEvent e) {
    if (e.pointer != _flipPointer) return;
    _flipPointer = null;
    if (!_flipDragging) return;
    _flipDragging = false;
    if (_canFlip) _turnTo(_turn.value.roundToDouble());
  }

  /// Tap: over to the other side.
  void _tapFlip() {
    if (!_canFlip) return;
    _turnTo(_turnTarget.roundToDouble() + 1);
  }

  void _turnTo(double target, {int ms = 380}) {
    if (target.round().isOdd != _turn.value.round().isOdd) HapticFeedback.selectionClick();
    _turnTarget = target;
    _turn.animateTo(target, duration: Duration(milliseconds: ms), curve: Curves.easeOutCubic);
  }

  // ------------------------------------------------------------- closing ---

  /// The X, back, a tap outside the card or a swipe down. Before the reveal
  /// it leaves at once (the box stays sealed, or, once a shake started the
  /// roll, the card is already in the collection). After it the card flies
  /// into "My cards" first.
  void _close() {
    if (_collecting || _leaving) return;
    if (_stage == _Stage.revealed) {
      _startCollect(fast: true);
    } else {
      _leave();
    }
  }

  void _addToCards() {
    if (_collecting || _leaving || _stage != _Stage.revealed) return;
    _startCollect(fast: false);
  }

  /// The card shrinks and flies down into the button, which then bumps and
  /// says it's saved; the screen closes when the flight ends.
  void _startCollect({required bool fast}) {
    HapticFeedback.lightImpact();
    _pulse.stop();
    final stack = _stackKey.currentContext?.findRenderObject();
    final card = _cardKey.currentContext?.findRenderObject();
    final target = _targetKey.currentContext?.findRenderObject();
    if (stack is RenderBox && card is RenderBox && stack.hasSize && card.hasSize) {
      final from = card.localToGlobal(Offset.zero, ancestor: stack) & card.size;
      final to = target is RenderBox && target.hasSize
          ? target.localToGlobal(target.size.center(Offset.zero), ancestor: stack)
          : Offset(from.center.dx, stack.size.height + from.height / 2);
      _flyFrom = from;
      _flyDelta = to - from.center;
    }
    // Front up on the way down.
    final front = (_turnTarget / 2).roundToDouble() * 2;
    if (front != _turnTarget) _turnTo(front, ms: 300);
    setState(() => _collecting = true);
    _collect.duration = fast ? _collectFast : _collectSlow;
    _collect.forward(from: 0);
  }

  // Swipe down: raw pointer events, so the card's own drags (flip, tilt)
  // and the buttons never compete with it. Only from outside the card, and
  // only while the page is not scrolled.
  void _onPointerDown(PointerDownEvent e) {
    if (_stage != _Stage.revealed || _collecting || _leaving || _pullPointer != null) return;
    if (_scroll.hasClients && _scroll.offset > 0) return;
    final card = _cardKey.currentContext?.findRenderObject();
    if (card is RenderBox && card.hasSize && (card.localToGlobal(Offset.zero) & card.size).contains(e.position)) return;
    _pull.stop();
    _pullPointer = e.pointer;
    _pullStart = e.position;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _pullPointer) return;
    _pull.value = math.max(0.0, e.position.dy - _pullStart.dy);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _pullPointer) return;
    _pullPointer = null;
    final d = e.position - _pullStart;
    if (d.dy > _pullToClose && d.dy > d.dx.abs()) {
      _close();
    } else {
      _pull.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _pullPointer) return;
    _pullPointer = null;
    _pull.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  // ------------------------------------------------------------- navigation ---

  /// Close. When this is the end of onboarding the profile provider still
  /// says "not onboarded": refresh it and wait for the answer BEFORE moving,
  /// or the router bounces through /onboarding for a frame on the way out.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
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
    if (_collecting || _leaving) return;
    final next = ref.read(sealedBoxesProvider).where((b) => b.id != widget.boxId).firstOrNull;
    if (next == null) return;
    context.pushReplacement(Routes.openBox(next.id));
  }

  void _share() {
    final c = _result?.card;
    if (c == null || _collecting) return;
    showShareCardSheet(context, CardPullShareSpec(card: c));
  }

  // ----------------------------------------------------------------- helpers ---

  static Color _glowFor(CardRarity? r) => switch (r) {
        CardRarity.legendary => _legendaryGold,
        CardRarity.rare => kSilverLight,
        _ => Colors.white,
      };

  /// Confetti in the rarity's metal; common gets the party mix (no blue or
  /// silver, so it never reads as a rare).
  static List<Color> _confettiFor(CardRarity r) => switch (r) {
        CardRarity.legendary => const [_legendaryGold, Color(0xFFFFD866), Colors.white, AppColors.brand, Color(0xFFFFB020)],
        CardRarity.rare => const [kSilverLight, Color(0xFFEEF0F3), kSilverDark, Colors.white, AppColors.brand],
        CardRarity.common => const [AppColors.brand, Color(0xFFFFC532), Colors.white, Color(0xFF4CC38A)],
      };

  static String _verdict(CardRarity r) => switch (r) {
        CardRarity.legendary => 'SECRET! One of the numbered few. Show-off.',
        CardRarity.rare => 'Nice pull. Not many of these around.',
        CardRarity.common => 'Solid. Trade doubles with friends for the ones you\'re missing.',
      };

  String _shakeBubble() => switch (_steps) {
        0 => 'Give it a shake. Something\'s rattling in there.',
        1 => 'Keep going…',
        _ => 'One more!',
      };

  /// "SECRET · 1 IN 200" from the admin odds; just the rarity when the
  /// odds are missing or round to 1 in 1.
  String _rarityLabel(CardRarity r) {
    final pct = ref.watch(cardSettingsProvider).value?.pct(r);
    final n = pct == null || pct <= 0 ? null : (100 / pct).round();
    final name = r.label.toUpperCase();
    return n == null || n < 2 ? name : '$name · 1 IN $n';
  }

  /// "NO. 37 OF 100" for a Secret pull, once the collection refetch lands.
  String? _serialLabel(BoxResult r) {
    if (r.card.rarity != CardRarity.legendary) return null;
    final serial = ref.watch(myCardsProvider).value?.where((c) => c.id == r.userCardId).firstOrNull?.serial;
    if (serial == null) return null;
    final total = ref.watch(boxOddsProvider).value?.legendaryTotal;
    return total == null ? 'NO. $serial' : 'NO. $serial OF $total';
  }

  /// 0 → 1 over [from]..[to] of [t].
  static double _span(double t, double from, double to) => ((t - from) / (to - from)).clamp(0.0, 1.0);

  // ------------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Shorter phones get a smaller card, so the verdict and buttons still fit.
    final cardW = math.min(math.min(size.width * 0.58, 224.0), size.height * 0.39 * kCardAspect);
    final boxW = math.min(size.width * 0.6, 230.0);
    final rarity = _result?.card.rarity;
    final moreBoxes = ref.watch(sealedBoxesProvider).where((b) => b.id != widget.boxId).length;
    final revealed = _stage == _Stage.revealed;
    final legendary = rarity == CardRarity.legendary;
    final rare = rarity == CardRarity.rare;
    final result = _result;

    return PopScope(
      // Back always comes through here: after the reveal it flies the card
      // home first, and at the end of onboarding [_leave] refreshes the
      // profile before moving.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: Stack(
          key: _stackKey,
          children: [
            // rarity glow once revealed (silver for rare; bigger + gold for the Secret)
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
                        radius: (legendary ? 1.15 : (rare ? 0.95 : 0.85)) * pulse,
                        colors: [_glowFor(rarity).withValues(alpha: (legendary ? 0.6 : (rare ? 0.5 : 0.45)) * t), AppColors.ink.withValues(alpha: 0)],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (revealed && legendary) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _SparklePainter(_sparkle)))),
            // After the reveal, everything outside the card is the backdrop:
            // a tap on it closes (the card is already saved), and so does a
            // swipe down that starts outside the card.
            Positioned.fill(
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: GestureDetector(
                  key: const ValueKey('open-box-backdrop'),
                  behavior: HitTestBehavior.opaque,
                  onTap: revealed && !_collecting ? _close : null,
                  child: AnimatedBuilder(
                    animation: _pull,
                    builder: (_, child) {
                      final pull = math.max(0.0, _pull.value);
                      return Opacity(
                        opacity: 1 - (pull / 500).clamp(0.0, 0.35),
                        child: Transform.translate(offset: Offset(0, pull * 0.6), child: child),
                      );
                    },
                    child: SafeArea(
                      child: Column(
                        children: [
                          _topRow(moreBoxes + 1),
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                controller: _scroll,
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
                  ),
                ),
              ),
            ),
            // the card on its way into "My cards", above everything
            if (_flyFrom case final from? when _collecting && result != null)
              Positioned.fromRect(
                rect: from,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _collect,
                    builder: (_, child) {
                      final p = _collect.value;
                      final hop = Curves.easeOut.transform(_span(p, 0, 0.2));
                      final fly = Curves.easeInCubic.transform(_span(p, 0.14, _landAt));
                      final scale = (1 - 0.06 * hop) * (1 - 0.86 * fly);
                      final offset = Offset(0, -18 * hop * (1 - fly)) + _flyDelta * fly;
                      return Opacity(
                        opacity: 1 - _span(p, _landAt - 0.08, _landAt),
                        child: Transform.translate(
                          offset: offset,
                          child: Transform.rotate(angle: -0.2 * fly, child: Transform.scale(scale: scale, child: child)),
                        ),
                      );
                    },
                    child: _turningCard(result.card, from.width),
                  ),
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
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 60),
          Expanded(child: Center(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: label))),
          // Always there, in the corner people look for it: a filled round X.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: 'Close',
              child: Material(
                color: Colors.white.withValues(alpha: 0.16),
                shape: const CircleBorder(),
                child: InkWell(
                  key: const ValueKey('open-box-close'),
                  customBorder: const CircleBorder(),
                  onTap: _close,
                  child: const SizedBox(width: 44, height: 44, child: Icon(AppIcons.x, color: Colors.white, size: 22)),
                ),
              ),
            ),
          ),
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
          // Shrinks rather than overflows on a narrow phone with big text.
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.vibrate, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Text('SHAKE TO OPEN', style: TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 3, color: Colors.white, height: 1)),
                ],
              ),
            ),
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

  /// The revealed card at its current turn: the front on even half turns,
  /// the back on odd ones, never mirrored.
  Widget _turningCard(CardType card, double width) {
    return AnimatedBuilder(
      animation: _turn,
      builder: (_, _) {
        final angle = _turn.value * math.pi;
        final front = math.cos(angle) >= 0;
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateY(front ? angle : angle - math.pi);
        return Transform(
          alignment: Alignment.center,
          transform: m,
          child: front ? CardFace(key: const ValueKey('card-front'), card: card, width: width) : CardBack(key: const ValueKey('card-back'), width: width),
        );
      },
    );
  }

  Widget _cardStage(double cardW, double boxW) {
    final r = _result!;
    final cardH = cardW / kCardAspect;
    final revealed = _stage == _Stage.revealed;

    // the drop-in: face-down, then it turns itself over
    final dropCard = AnimatedBuilder(
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
      child: dropCard,
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
                    builder: (_, _) => CustomPaint(painter: _BurstPainter(_burst.value, _particles, _glowFor(r.card.rarity), _confettiFor(r.card.rarity))),
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
            // Swipe either way, as often as you like, or tap: it turns over.
            // Hidden while its copy flies into "My cards".
            Opacity(
              opacity: _collecting && _flyFrom != null ? 0 : 1,
              child: Listener(
                onPointerDown: _cardDown,
                onPointerMove: (e) => _cardMove(e, cardW),
                onPointerUp: _cardUp,
                onPointerCancel: _cardCancel,
                child: GestureDetector(
                  key: _cardKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: _tapFlip,
                  child: SizedBox(width: cardW, height: cardH, child: TiltCard(child: _turningCard(r.card, cardW))),
                ),
              ),
            )
          else
            dropped,
        ],
      ),
    );

    // Fades in with the reveal, out as the card leaves.
    Widget revealFade(Widget child, {double rise = 18}) => AnimatedBuilder(
          animation: Listenable.merge([_reveal, _collect]),
          builder: (_, child) {
            final t = Curves.easeOutCubic.transform(_reveal.value);
            final out = _collecting ? _span(_collect.value, 0, 0.3) : 0.0;
            return Opacity(opacity: (t * (1 - out)).clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, (1 - t) * rise), child: child));
          },
          child: child,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        cardArea,
        // "Swipe to flip", right under the card
        SizedBox(
          height: 40,
          child: revealed
              ? revealFade(
                  rise: 6,
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      key: ValueKey('flip-hint'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.arrowLeft, color: Colors.white54, size: 14),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Swipe or tap to flip',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(AppIcons.arrowRight, color: Colors.white54, size: 14),
                      ],
                    ),
                  ),
                )
              : null,
        ),
        // name, description, count and TiTi's verdict slide in on reveal
        if (revealed)
          revealFade(
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(r.card.name, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                ),
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
                if (_serialLabel(r) case final no?) ...[
                  const SizedBox(height: 6),
                  Text(no, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1, color: _legendaryGold)),
                ],
                const SizedBox(height: 16),
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
            ),
          )
        // roughly the height of the text block, so the card barely moves on reveal
        else
          const SizedBox(height: 180),
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
    // Everything but the button steps aside while the card flies into it.
    Widget aside(Widget child) => AnimatedBuilder(
          animation: Listenable.merge([_cta, _collect]),
          builder: (_, child) => Opacity(
            opacity: (_span(_cta.value, 0.5, 0.9) * (1 - (_collecting ? _span(_collect.value, 0, 0.25) : 0))).clamp(0.0, 1.0),
            child: child,
          ),
          child: child,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _collectButton()),
              const SizedBox(width: 10),
              aside(
                SizedBox(
                  width: 56,
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(56, 56),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _share,
                    child: const Icon(AppIcons.export, size: 22),
                  ),
                ),
              ),
            ],
          ),
          if (moreBoxes > 0) ...[
            const SizedBox(height: 10),
            aside(
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), minimumSize: const Size(0, 48)),
                  onPressed: _openAnother,
                  child: Text('Open another ($moreBoxes)'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          aside(
            const Text(
              'Already in your cards · tap outside to close',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  /// "Add to my cards": rises in once the card has settled, then breathes
  /// with a shine sweeping across. Pressed, it becomes the "My cards" the
  /// card flies into, bumps when it lands and shows +1.
  Widget _collectButton() {
    final Widget label;
    if (!_collecting) {
      label = const Row(
        key: ValueKey('add'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.plusCircle, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Flexible(child: Text('Add to my cards', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
        ],
      );
    } else if (!_landed) {
      label = const Row(
        key: ValueKey('target'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.cards, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Flexible(child: Text('My cards', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
        ],
      );
    } else {
      label = const Row(
        key: ValueKey('saved'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.checkCircleFill, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Flexible(child: Text('Saved to My cards', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
        ],
      );
    }

    final button = Container(
      key: _targetKey,
      height: 56,
      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(16)),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('open-box-add'),
          onTap: _addToCards,
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // the shine: a soft band sweeping across now and then
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, _) => _pulse.isAnimating ? CustomPaint(painter: _ShinePainter(_span(_pulse.value, 0.05, 0.5))) : const SizedBox.shrink(),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    // out first, then in: the two labels never overlap
                    switchInCurve: const Interval(0.5, 1, curve: Curves.easeOut),
                    switchOutCurve: const Interval(0.5, 1, curve: Curves.easeIn),
                    child: label,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_cta, _pulse, _collect]),
      builder: (_, child) {
        final shown = _span(_cta.value, 0.35, 0.65);
        final rise = Curves.easeOutBack.transform(_span(_cta.value, 0.35, 1));
        final breath = _pulse.isAnimating ? math.sin(_pulse.value * 2 * math.pi) : 0.0;
        final bump = _collecting ? math.sin(math.pi * _span(_collect.value, _landAt, _landAt + 0.18)) : 0.0;
        final glow = (0.3 + 0.15 * breath + 0.4 * bump) * shown;
        return Opacity(
          opacity: shown,
          child: Transform.translate(
            offset: Offset(0, (1 - rise) * 72),
            child: Transform.scale(
              scale: 1 + 0.022 * breath + 0.09 * bump,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: glow.clamp(0.0, 1.0)), blurRadius: 22, spreadRadius: 1)],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PressScale(enabled: !_collecting, child: button),
          // +1 pops on the corner when the card lands
          Positioned(
            top: -10,
            right: -6,
            child: IgnorePointer(
              child: AnimatedScale(
                scale: _landed ? 1 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                  child: const Text('+1', style: TextStyle(color: AppColors.brand, fontSize: 13, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft white band sweeping left to right across the button at [t] (0..1).
class _ShinePainter extends CustomPainter {
  const _ShinePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final band = size.height * 1.1;
    final x = -band + (size.width + band * 2) * Curves.easeInOut.transform(t);
    final rect = Rect.fromLTWH(x - band / 2, 0, band, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.save();
    // lean the band like light across a glossy face
    canvas.translate(x, size.height / 2);
    canvas.skew(-0.45, 0);
    canvas.translate(-x, -size.height / 2);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.t != t;
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
  _Particle(this.angle, this.speed, this.size, this.slot, this.spin);
  final double angle, speed, size, spin;
  /// Which colour of the burst's palette.
  final int slot;

  static _Particle random(int i) {
    final r = math.Random(i * 31 + 3);
    return _Particle(r.nextDouble() * 2 * math.pi, 140 + r.nextDouble() * 260, 5 + r.nextDouble() * 9, i, r.nextDouble() * 6);
  }
}

/// Confetti and a flash ring in the rarity colour, flying out of the box.
class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.t, this.particles, this.accent, this.palette);
  final double t;
  final List<_Particle> particles;
  final Color accent;
  final List<Color> palette;

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
      final paint = Paint()..color = palette[p.slot % palette.length].withValues(alpha: (1 - t).clamp(0, 1));
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

/// Slow golden sparkles for the Secret reveal.
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
