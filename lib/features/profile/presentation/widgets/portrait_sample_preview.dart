import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/consent/ai_consent.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/pinch_zoom.dart';
import '../../domain/car.dart';
import '../../domain/portrait_style.dart';
import 'portrait_style_sheet.dart';

/// Full-screen look at the style samples before paying for one: the sample
/// big (pinch to zoom), its name and line, swipe for the other styles, then
/// "Paint my (car) · 300 points" runs the usual confirm and books the job.
///
/// Zooms out of the tapped card ([originOf] gives a card's place on screen)
/// and back into the card of the style showing when it closes. Answers true
/// when a portrait was started.
Future<bool?> showPortraitSamplePreview(
  BuildContext context, {
  required Car car,
  required int cost,
  int initial = 0,
  Rect? Function(int index)? originOf,
}) async {
  // Have the first picture decoded before the zoom starts, so it never pops in.
  await precacheImage(AssetImage(kPortraitStyles[initial].sampleAsset), context, onError: (_, _) {});
  if (!context.mounted) return null;
  return Navigator.of(context, rootNavigator: true).push<bool>(
    PortraitPreviewRoute(car: car, cost: cost, initial: initial, originOf: originOf),
  );
}

class PortraitPreviewRoute extends PageRouteBuilder<bool> {
  PortraitPreviewRoute({required Car car, required int cost, required int initial, Rect? Function(int index)? originOf})
      : this._(ValueNotifier<int>(initial), car, cost, initial, originOf);

  PortraitPreviewRoute._(ValueNotifier<int> page, Car car, int cost, int initial, Rect? Function(int index)? originOf)
      : super(
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, _, _) => PortraitSamplePreview(car: car, cost: cost, initial: initial, page: page),
          transitionsBuilder: (context, animation, _, child) => _ZoomFromCard(animation: animation, page: page, originOf: originOf, child: child),
        );
}

/// The preview grows out of the card it was opened from and shrinks back
/// into the card of whichever style is showing, fading as it goes.
class _ZoomFromCard extends StatelessWidget {
  const _ZoomFromCard({required this.animation, required this.page, required this.originOf, required this.child});
  final Animation<double> animation;
  final ValueNotifier<int> page;
  final Rect? Function(int index)? originOf;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        final reverse = animation.status == AnimationStatus.reverse;
        final t = (reverse ? Curves.easeInCubic : Curves.easeOutCubic).transform(animation.value);
        final from = originOf?.call(page.value);
        // Scale about the card's centre, starting at the card's width.
        final start = from == null || screen.width == 0 ? 0.6 : (from.width / screen.width).clamp(0.3, 0.9);
        // A card scrolled out of the sheet still zooms from the nearest edge.
        final align = from == null || screen.width == 0 || screen.height == 0
            ? Alignment.center
            : Alignment(((from.center.dx / screen.width) * 2 - 1).clamp(-1.0, 1.0), ((from.center.dy / screen.height) * 2 - 1).clamp(-1.0, 1.0));
        return Opacity(
          opacity: Curves.easeOut.transform(animation.value.clamp(0.0, 1.0)),
          child: Transform.scale(scale: start + (1 - start) * t, alignment: align, child: child),
        );
      },
    );
  }
}

class PortraitSamplePreview extends ConsumerStatefulWidget {
  const PortraitSamplePreview({super.key, required this.car, required this.cost, required this.initial, required this.page});
  final Car car;
  final int cost;
  final int initial;

  /// The style showing; the route reads it to close into the right card.
  final ValueNotifier<int> page;

  @override
  ConsumerState<PortraitSamplePreview> createState() => _PortraitSamplePreviewState();
}

class _PortraitSamplePreviewState extends ConsumerState<PortraitSamplePreview> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _page = widget.initial;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warm(_page);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Decode the neighbours ahead of a swipe.
  void _warm(int i) {
    precacheImage(const AssetImage(kPortraitSampleOriginal), context, onError: (_, _) {});
    for (final j in [i - 1, i + 1]) {
      if (j >= 0 && j < kPortraitStyles.length) precacheImage(AssetImage(kPortraitStyles[j].sampleAsset), context, onError: (_, _) {});
    }
  }

  void _onPage(int i) {
    setState(() => _page = i);
    widget.page.value = i;
    _warm(i);
  }

  Future<void> _paint() async {
    final style = kPortraitStyles[_page];
    final messenger = ScaffoldMessenger.of(context);
    final go = await confirmPortrait(context, car: widget.car, style: style, cost: widget.cost);
    if (!go || !mounted) return;
    if (!await ensureAiConsent(context, ref, AiConsentKind.toy) || !mounted) return;
    setState(() => _busy = true);
    final started = await requestPortrait(ref, messenger, widget.car, style);
    if (!mounted) return;
    if (started) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = kPortraitStyles[_page];
    final cost = widget.cost;
    return PopScope(
      canPop: !_busy,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // The showing sample, blurred to fill the screen behind it.
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  child: _Backdrop(key: ValueKey(style.id), style: style),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: _busy ? null : () => Navigator.of(context).maybePop(false),
                            icon: const Icon(AppIcons.x, color: Colors.white, size: 22),
                          ),
                          const Spacer(),
                          Text(
                            '${_page + 1} / ${kPortraitStyles.length}',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.75)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pages,
                        // Hold still while the sample is pinched (see PinchZoom).
                        pageSnapping: false,
                        physics: const PinchLockScrollPhysics(parent: PageScrollPhysics()),
                        onPageChanged: _onPage,
                        itemCount: kPortraitStyles.length,
                        itemBuilder: (_, i) => _SamplePage(style: kPortraitStyles[i], index: i, pages: _pages),
                      ),
                    ),
                    _Dots(count: kPortraitStyles.length, current: _page),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PressScale(
                            enabled: !_busy,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _paint,
                              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                              icon: _busy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                                  : const Icon(AppIcons.sparkle, size: 18, color: Colors.white),
                              label: Text(
                                'Paint my ${widget.car.model} · ${cost > 0 ? '$cost points' : 'free'}',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _busy ? null : () => Navigator.of(context).maybePop(false),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(44),
                              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            child: const Text('Back'),
                          ),
                        ],
                      ),
                    ),
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

/// One style: the sample with a glow in the style's colour, its name in the
/// display font, its line and whose car it is. Holding the sample shows the
/// ordinary photo it was painted from. Pages ease down and fade as they slide
/// away, so the swipe feels like a carousel. Scrolls if the text is too big
/// for the screen.
class _SamplePage extends StatefulWidget {
  const _SamplePage({required this.style, required this.index, required this.pages});
  final PortraitStyle style;
  final int index;
  final PageController pages;

  @override
  State<_SamplePage> createState() => _SamplePageState();
}

class _SamplePageState extends State<_SamplePage> {
  bool _original = false;

  void _hold(bool on) {
    if (on == _original) return;
    if (on) HapticFeedback.selectionClick();
    setState(() => _original = on);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final pages = widget.pages;
    final index = widget.index;
    final sample = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [BoxShadow(color: style.tint.withValues(alpha: 0.55), blurRadius: 44, spreadRadius: -6, offset: const Offset(0, 16))],
        ),
        child: GestureDetector(
          onLongPressStart: (_) => _hold(true),
          onLongPressEnd: (_) => _hold(false),
          onLongPressCancel: () => _hold(false),
          child: PinchZoom(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PortraitSampleImage(style: style),
                    AnimatedOpacity(
                      opacity: _original ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Image.asset(kPortraitSampleOriginal, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _original ? const _Chip(label: 'Original photo') : PortraitStyleBadge(style: style, size: 30),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final words = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Text(
            style.name.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: AppFonts.display, fontSize: 40, height: 1, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            style.description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: Colors.white.withValues(alpha: 0.82)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.car, size: 14, color: Colors.white.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Sample: ${PortraitStyle.sampleCar}'),
                        TextSpan(text: '  ·  hold to see the photo', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.55))),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.75)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: pages,
      builder: (_, child) {
        var away = 0.0;
        if (pages.hasClients && pages.position.hasContentDimensions) away = ((pages.page ?? index.toDouble()) - index).abs().clamp(0.0, 1.0);
        return Opacity(opacity: 1 - away * 0.45, child: Transform.scale(scale: 1 - away * 0.08, child: child));
      },
      child: LayoutBuilder(
        builder: (_, box) => SingleChildScrollView(
          physics: const PinchLockScrollPhysics(parent: ClampingScrollPhysics()),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [sample, const SizedBox(height: 26), words, const SizedBox(height: 12)],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sample again, blown up and blurred behind everything, darkened so
/// the white text stays readable whatever the style's colours.
class _Backdrop extends StatelessWidget {
  const _Backdrop({super.key, required this.style});
  final PortraitStyle style;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36, tileMode: TileMode.mirror),
            child: PortraitSampleImage(style: style, cacheWidth: 160),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.72), Colors.black.withValues(alpha: 0.92)],
              ),
            ),
          ),
        ],
      );
}

/// Which of the 8 is showing: a short white bar for the current one.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == current ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == current ? 0.95 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}

/// The everyday photo all eight samples were painted from.
const kPortraitSampleOriginal = 'assets/portrait_samples/base.webp';

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
      );
}
