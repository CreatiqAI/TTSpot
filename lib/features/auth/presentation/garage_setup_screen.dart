import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/light_trails.dart';
import '../../profile/domain/car.dart';
import 'widgets/dark_auth.dart';

/// "Building your garage" (Setup.dc.html): shown once, between the last form
/// step of onboarding and the first blind box. The member's car is revealed
/// left to right behind a thin scan line, a red bar fills and three lines
/// light up in turn. Always dark. No TiTi here.
///
/// Behind the scenes it re-reads the car row every [poll] through [readCar]
/// (a plain select on `cars` by id). If `toy_url` turns up, the toy is
/// revealed and the screen moves on about 1.2 s later. Otherwise it shows the
/// best picture there is (cut-out, else the cover photo in a rounded frame)
/// and moves on at [cap]. Never shorter than [minTime], so it cannot flash.
/// Any error moves on too: nobody gets stuck here.
class GarageSetupScreen extends StatefulWidget {
  const GarageSetupScreen({
    super.key,
    required this.car,
    required this.readCar,
    required this.onDone,
    this.poll = const Duration(seconds: 3),
    this.minTime = const Duration(milliseconds: 3500),
    this.cap = const Duration(seconds: 12),
    this.afterToy = const Duration(milliseconds: 1200),
    this.imageWait = const Duration(milliseconds: 2500),
    this.imageFor,
  });

  final Car car;
  /// Fresh copy of the car row, or null when it is gone.
  final Future<Car?> Function(String carId) readCar;
  /// Called exactly once, when the screen is finished with.
  final VoidCallback onDone;
  final Duration poll;
  final Duration minTime;
  final Duration cap;
  /// How long the toy stays on screen once revealed.
  final Duration afterToy;
  /// How long a picture may take to load before its reveal starts anyway
  /// (the reveal sweeping over nothing looks broken). Zero skips the wait.
  final Duration imageWait;
  /// Image provider for a URL; tests inject one that needs no network.
  final ImageProvider Function(String url)? imageFor;

  @override
  State<GarageSetupScreen> createState() => _GarageSetupScreenState();
}

class _GarageSetupScreenState extends State<GarageSetupScreen> with TickerProviderStateMixin {
  /// 0 → 1 over [cap]; jumps to 1 when the toy arrives.
  late final AnimationController _progress = AnimationController(vsync: this, duration: widget.cap);
  /// One reveal per picture: the clip sweeps left to right behind the line.
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  Timer? _pollTimer;
  Timer? _capTimer;
  Timer? _doneTimer;
  Timer? _minTimer;
  bool _reading = false;
  bool _done = false;
  /// [minTime] has passed; a finish asked for earlier goes through now.
  bool _minPassed = false;
  bool _finishAsked = false;
  String? _toyUrl;

  @override
  void initState() {
    super.initState();
    try {
      _minTimer = Timer(widget.minTime, () {
        _minPassed = true;
        if (_finishAsked) _finish();
      });
      if (widget.car.toyUrl != null) {
        // Already made: no waiting, but the lines still light in turn.
        _toyArrived(widget.car.toyUrl!);
      } else {
        _progress.forward();
        final first = widget.car.cutoutUrl ?? widget.car.photoCover ?? widget.car.portraitUrl;
        WidgetsBinding.instance.addPostFrameCallback((_) => _revealWhenLoaded(first));
        _pollTimer = Timer.periodic(widget.poll, (_) => _read());
        _capTimer = Timer(widget.cap, _finish);
      }
    } catch (_) {
      _finish();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _capTimer?.cancel();
    _doneTimer?.cancel();
    _minTimer?.cancel();
    _progress.dispose();
    _reveal.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (_reading || _done) return;
    _reading = true;
    try {
      final fresh = await widget.readCar(widget.car.id);
      if (!mounted || _done) return;
      if (fresh == null) return _finish(); // the car is gone: nothing to wait for
      if (fresh.toyUrl != null) {
        _toyArrived(fresh.toyUrl!);
      } else if (fresh.toyStatus == 'failed') {
        _finish(); // no toy coming; the garage falls back to the photo
      }
    } catch (_) {
      // A failed read is just a missed poll; the cap still ends the wait.
    } finally {
      _reading = false;
    }
  }

  /// Starts the left-to-right reveal once [url]'s picture is decoded (or
  /// after [GarageSetupScreen.imageWait], whichever comes first).
  Future<void> _revealWhenLoaded(String? url) async {
    if (url != null && widget.imageWait > Duration.zero && mounted) {
      try {
        await precacheImage(_provider(url), context).timeout(widget.imageWait);
      } catch (_) {/* reveal whatever there is */}
    }
    if (mounted && !_done) _reveal.forward(from: 0);
  }

  bool _toyHandled = false;

  void _toyArrived(String url) {
    if (_done || _toyHandled) return;
    _toyHandled = true;
    _pollTimer?.cancel();
    _capTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _done) return;
      if (widget.imageWait > Duration.zero) {
        try {
          await precacheImage(_provider(url), context).timeout(widget.imageWait);
        } catch (_) {/* show it anyway */}
      }
      if (!mounted || _done) return;
      setState(() => _toyUrl = url);
      const reveal = Duration(milliseconds: 1000);
      // The bar fills and the three lines light in turn while the toy is
      // revealed and held.
      _progress.animateTo(1, duration: reveal + widget.afterToy, curve: Curves.linear);
      _reveal
        ..duration = reveal
        ..forward(from: 0);
      _doneTimer = Timer(reveal + widget.afterToy, _finish);
    });
  }

  /// Once, and never before [minTime] (the minimum timer calls back here).
  void _finish() {
    if (_done) return;
    if (!_minPassed) {
      _finishAsked = true;
      return;
    }
    _done = true;
    _pollTimer?.cancel();
    _capTimer?.cancel();
    _doneTimer?.cancel();
    if (_progress.value < 1) _progress.animateTo(1, duration: const Duration(milliseconds: 300));
    widget.onDone();
  }

  ImageProvider _provider(String url) => (widget.imageFor ?? (u) => CachedNetworkImageProvider(u))(url);

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      if (_reveal.isAnimating) _reveal.value = 1;
    }
    // The toy, else the cut-out (both transparent, no frame), else the cover
    // photo in a rounded frame, else a quiet placeholder.
    final transparentUrl = _toyUrl ?? car.cutoutUrl;
    final photoUrl = car.photoCover ?? car.portraitUrl;
    final Widget picture;
    if (transparentUrl != null) {
      picture = Image(image: _provider(transparentUrl), fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => const _NoPicture());
    } else if (photoUrl != null) {
      picture = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image(image: _provider(photoUrl), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const _NoPicture()),
      );
    } else {
      picture = const _NoPicture();
    }

    return AuthPage(
      lift: 0.38,
      liftHeight: 0.4,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final imgW = (w - 90).clamp(200.0, 300.0);
            final imgH = imgW * 168 / 300;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    Text('BUILDING YOUR GARAGE', textAlign: TextAlign.center, style: AuthDark.display(40)),
                    const SizedBox(height: 48),
                    // Picture, its shadow and the floor line. The light trails
                    // run under the floor, clear of the title and the card.
                    SizedBox(
                      height: imgH + 60,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          Positioned(left: -24, right: -24, top: imgH - 20, height: 80, child: const LightTrails(opacity: 0.3)),
                          Positioned(
                            top: imgH - 20,
                            width: imgW * 0.84,
                            height: 30,
                            // A circle of shade stretched into a wide ellipse.
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.diagonal3Values(imgW * 0.84 / 30, 1, 1),
                              child: Center(
                                child: SizedBox.square(
                                  dimension: 30,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(colors: [Colors.black.withValues(alpha: 0.95), Colors.transparent], stops: const [0, 1]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: -24,
                            right: -24,
                            top: imgH + 2,
                            height: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [Colors.transparent, Colors.white.withValues(alpha: 0.22), Colors.transparent]),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            width: imgW,
                            height: imgH,
                            child: _Reveal(reveal: _reveal, child: picture),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AuthDark.panel,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: AnimatedBuilder(
                        animation: _progress,
                        builder: (_, _) {
                          final p = Curves.easeInOut.transform(_progress.value);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  height: 8,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.14))),
                                      Positioned.fill(
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: 0.04 + 0.96 * p,
                                          child: const ColoredBox(color: AppColors.brand),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _Step('Matching your car model', lit: p >= 0.22),
                              const SizedBox(height: 16),
                              _Step('Painting it your colour', lit: p >= 0.44),
                              const SizedBox(height: 16),
                              _Step('Wrapping your first blind box', lit: p >= 0.66),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A dim copy of the picture, the bright one clipped from the left as the
/// reveal runs, and a glowing scan line on the clip's edge (gone at the end).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.reveal, required this.child});
  final Animation<double> reveal;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: reveal,
        builder: (context, _) {
          final k = Curves.easeInOut.transform(reveal.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              ColorFiltered(colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.84), BlendMode.srcATop), child: child),
              ClipRect(
                child: Align(alignment: Alignment.centerLeft, widthFactor: k.clamp(0.001, 1), child: SizedBox.expand(child: child)),
              ),
              if (k < 1)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment(-1 + 2 * k, 0),
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.7), blurRadius: 16, spreadRadius: 3)],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

/// One line of the card: tick and words, dim until [lit].
class _Step extends StatelessWidget {
  const _Step(this.text, {required this.lit});
  final String text;
  final bool lit;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        opacity: lit ? 1 : 0.28,
        child: Row(
          children: [
            const Icon(AppIcons.check, size: 20, color: Color(0xFF3DDC84)),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: Colors.white))),
          ],
        ),
      );
}

/// When there is no picture at all (or it failed to load): a quiet car
/// outline so the reveal still has something to sweep.
class _NoPicture extends StatelessWidget {
  const _NoPicture();

  @override
  Widget build(BuildContext context) => Center(child: Icon(AppIcons.car, size: 96, color: Colors.white.withValues(alpha: 0.5)));
}
