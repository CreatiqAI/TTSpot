import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../map/presentation/widgets/car_marker.dart' show kCarColors, kCarColorLabels;
import '../../domain/car.dart';
import '../../domain/car_documents.dart';
import '../widgets/toy_car_image.dart';
import 'garage_facts.dart';

// The garage: one studio card with a toy model of the member's car, a rail of
// the other cars' toys, the numbers, the buttons and the car's papers. Always
// the night palette, in light and dark mode alike.

/// The studio's fixed palette (from the approved mockup).
abstract final class StudioColors {
  static const page = Color(0xFF07080B);
  static const card = Color(0xFF111318);
  static const lift = Color(0xFF262932);
  static const edge = Color(0x1FFFFFFF); // white 12 %
  static const glass = Color(0x14FFFFFF); // white 8 %
  static const glassEdge = Color(0x2EFFFFFF); // white 18 %
  static const text = Colors.white;
  static const textSoft = Color(0xB8FFFFFF); // white 72 %
  static const amber = Color(0xFFFFB648);
  static const green = Color(0xFF6BE09A);
  static const red = Color(0xFFFF8A8A);
}

const _kPad = 20.0;
const _kRadius = 28.0;

/// Text may grow with the system size, within reason: the card is artwork.
TextScaler _scaler(BuildContext context) => MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

/// Where the garage's toy transition lands: subtle overshoot, like easeOutBack.
const kToyLandCurve = Cubic(0.2, 0.9, 0.25, 1.06);
const kToyLandDuration = Duration(milliseconds: 450);

/// The garage from plain data (no providers), so it can be pumped in tests:
/// the header, the hero card (a pager over the cars), the thumbnail rail,
/// the stats, the buttons and the papers rows. With no cars: the header and
/// [empty].
class GarageStudio extends StatefulWidget {
  const GarageStudio({
    super.key,
    required this.cars,
    required this.index,
    required this.onIndex,
    required this.mine,
    required this.title,
    required this.onOpen,
    this.todayId,
    this.facts = const GarageFacts(),
    this.bottomPadding = 0,
    this.onBack,
    this.onAdd,
    this.onMore,
    this.onMakeToday,
    this.onEdit,
    this.onPapers,
    this.onRefresh,
    this.empty,
    this.loading = false,
    this.error,
  });

  final List<Car> cars;
  final int index;
  final ValueChanged<int> onIndex;
  final bool mine;

  /// "My garage", "Keith's garage" (shown in capitals).
  final String title;
  final ValueChanged<Car> onOpen;
  final String? todayId;

  /// The numbers and papers for the car in view ([index]).
  final GarageFacts facts;
  final double bottomPadding;
  final VoidCallback? onBack;

  /// The owner's: the round + in the header.
  final VoidCallback? onAdd;

  /// The owner's: the car's menu (the … button, or a long press on the toy).
  final ValueChanged<Car>? onMore;
  final ValueChanged<Car>? onMakeToday;
  final ValueChanged<Car>? onEdit;
  final ValueChanged<Car>? onPapers;
  final Future<void> Function()? onRefresh;

  /// Shown under the header when there are no cars.
  final Widget? empty;
  final bool loading;
  final String? error;

  @override
  State<GarageStudio> createState() => _GarageStudioState();
}

class _GarageStudioState extends State<GarageStudio> {
  late final PageController _pager = PageController(initialPage: widget.index);
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _shown = widget.index;
  }

  @override
  void didUpdateWidget(GarageStudio old) {
    super.didUpdateWidget(old);
    final want = widget.index.clamp(0, widget.cars.isEmpty ? 0 : widget.cars.length - 1);
    if (want != _shown && _pager.hasClients) {
      _shown = want;
      _pager.animateToPage(want, duration: kToyLandDuration, curve: Curves.easeOutCubic);
    } else if (want != _shown) {
      _shown = want;
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _onPage(int i) {
    if (i == _shown) return;
    _shown = i;
    HapticFeedback.selectionClick();
    widget.onIndex(i);
  }

  @override
  Widget build(BuildContext context) {
    final cars = widget.cars;
    final index = widget.index.clamp(0, cars.isEmpty ? 0 : cars.length - 1);
    final car = cars.isEmpty ? null : cars[index];
    final padTop = MediaQuery.paddingOf(context).top;

    final children = <Widget>[
      SizedBox(height: padTop + 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPad),
        child: GarageHeader(title: widget.title, onBack: widget.onBack, onAdd: widget.onAdd),
      ),
      const SizedBox(height: 22),
      if (widget.loading)
        const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
      else if (widget.error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
          child: Text(widget.error!, textAlign: TextAlign.center, style: const TextStyle(color: StudioColors.textSoft, fontSize: 14, height: 1.4)),
        )
      else if (car == null)
        widget.empty ?? const SizedBox.shrink()
      else ...[
        LayoutBuilder(
          builder: (context, c) {
            final cardW = c.maxWidth - _kPad * 2;
            return SizedBox(
              height: GarageHeroCard.heightFor(context, cardW),
              child: PageView.builder(
                controller: _pager,
                itemCount: cars.length,
                onPageChanged: _onPage,
                itemBuilder: (context, i) {
                  final c = cars[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _kPad),
                    child: GarageHeroCard(
                      key: ValueKey('hero-${c.id}'),
                      car: c,
                      mine: widget.mine,
                      today: c.id == widget.todayId,
                      active: i == index,
                      onTap: () => widget.onOpen(c),
                      onLongPress: widget.onMore == null ? null : () => widget.onMore!(c),
                    ),
                  );
                },
              ),
            );
          },
        ),
        if (cars.length > 1) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kPad),
            child: ToyRail(cars: cars, index: index, mine: widget.mine, onPick: widget.onIndex),
          ),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPad),
          child: StatsRow(facts: widget.facts, mine: widget.mine),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPad),
          child: widget.mine
              ? Row(
                  children: [
                    Expanded(child: StudioButton(label: 'Open car', onTap: () => widget.onOpen(car))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: car.id == widget.todayId
                          ? StudioButton(label: 'Edit', filled: false, onTap: () => widget.onEdit?.call(car))
                          : StudioButton(label: 'Make today\'s car', filled: false, onTap: () => widget.onMakeToday?.call(car)),
                    ),
                    if (widget.onMore != null) ...[
                      const SizedBox(width: 12),
                      StudioRoundButton(icon: AppIcons.dotsThree, tooltip: 'More', size: 52, onTap: () => widget.onMore!(car)),
                    ],
                  ],
                )
              : StudioButton(label: 'Open car', onTap: () => widget.onOpen(car)),
        ),
        if (widget.mine) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kPad),
            child: PapersRows(facts: widget.facts, onTap: widget.onPapers == null ? null : () => widget.onPapers!(car)),
          ),
        ],
      ],
      SizedBox(height: 24 + widget.bottomPadding),
    ];

    Widget list = ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      padding: EdgeInsets.zero,
      children: children,
    );
    final refresh = widget.onRefresh;
    if (refresh != null) {
      list = RefreshIndicator(onRefresh: refresh, color: Colors.white, backgroundColor: StudioColors.card, edgeOffset: padTop, child: list);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlay.copyWith(statusBarIconBrightness: Brightness.light, statusBarBrightness: Brightness.dark),
      child: ColoredBox(
        color: StudioColors.page,
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: StudioColors.text),
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: list)),
        ),
      ),
    );
  }
}

/// Back (on the full-screen routes), the title in capitals and the owner's
/// round + button.
class GarageHeader extends StatelessWidget {
  const GarageHeader({super.key, required this.title, this.onBack, this.onAdd});
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (onBack != null) ...[
            StudioRoundButton(icon: AppIcons.arrowLeft, tooltip: 'Back', onTap: onBack!),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
              style: const TextStyle(fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w800, height: 1, letterSpacing: 0.3, color: StudioColors.text),
            ),
          ),
          if (onAdd != null) ...[
            const SizedBox(width: 12),
            StudioRoundButton(icon: AppIcons.plus, tooltip: 'Add a car', onTap: onAdd!),
          ],
        ],
      );
}

/// A round glass button: back, add, more.
class StudioRoundButton extends StatelessWidget {
  const StudioRoundButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.size = 44});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: StudioColors.glass,
            shape: const CircleBorder(side: BorderSide(color: StudioColors.glassEdge)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(width: size, height: size, child: Icon(icon, size: 20, color: Colors.white)),
            ),
          ),
        ),
      );
}

/// The studio card: make and year, the model name, TODAY'S CAR, the toy on
/// its contact shadow, and the colour line. Fixed height for its width (see
/// [heightFor]) so the pager can hold it.
class GarageHeroCard extends StatelessWidget {
  const GarageHeroCard({super.key, required this.car, required this.mine, required this.today, required this.active, this.onTap, this.onLongPress});

  final Car car;
  final bool mine;
  final bool today;

  /// The card in view: its toy lands (fades and scales in) when this turns on.
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The toy's width for a card [cardW] wide (300 on the mockup's 350).
  static double toyWidthFor(double cardW) => cardW * 0.86;

  static double heightFor(BuildContext context, double cardW) {
    final ts = _scaler(context);
    final toyH = toyWidthFor(cardW) / kToyAspect;
    final header = ts.scale(12) * 1.25 + 2 + ts.scale(30) * 1.0;
    final line = ts.scale(13) * 1.3;
    return 18 + header + 8 + toyH + 36 + line + 16;
  }

  @override
  Widget build(BuildContext context) {
    final c = car;
    final ts = _scaler(context);
    final make = [c.make.toUpperCase(), if (c.year != null) '${c.year}'].join(' · ');
    final colour = (c.color ?? '').trim().isEmpty ? null : c.color!.trim();
    final colourName = colour == null ? null : (kCarColorLabels[colour] ?? (colour[0].toUpperCase() + colour.substring(1)));
    return Semantics(
      button: onTap != null,
      label: '${c.make} ${c.model}${today ? ', today\'s car' : ''}',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: LayoutBuilder(
          builder: (context, box) {
            final cardW = box.maxWidth;
            final toyW = toyWidthFor(cardW);
            return Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_kRadius),
                border: Border.all(color: StudioColors.edge),
                gradient: const RadialGradient(
                  center: Alignment(0, 0.16),
                  radius: 0.9,
                  colors: [StudioColors.lift, StudioColors.card],
                  stops: [0, 0.78],
                  transform: _Ellipse(0.61),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(_kPad, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              make,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textScaler: ts,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5, height: 1.25, color: StudioColors.textSoft),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textScaler: ts,
                              style: const TextStyle(fontFamily: AppFonts.display, fontSize: 30, fontWeight: FontWeight.w800, height: 1, color: StudioColors.text),
                            ),
                          ],
                        ),
                      ),
                      if (today) ...[
                        const SizedBox(width: 10),
                        TodayChip(text: mine ? 'TODAY\'S CAR' : 'DAILY'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Center(
                      child: HeroToy(car: c, width: toyW, mine: mine, active: active),
                    ),
                  ),
                  SizedBox(
                    height: ts.scale(13) * 1.3,
                    child: colour == null
                        ? null
                        : Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: kCarColors[colour] ?? const Color(0xFFB0B4BC),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '$colourName, matched from ${mine ? 'your' : 'the'} photo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: ts,
                                  style: const TextStyle(fontSize: 13, height: 1.3, color: StudioColors.textSoft),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Stretches a radial gradient sideways: a circle becomes a wide ellipse
/// ([ratio] = height over width).
class _Ellipse extends GradientTransform {
  const _Ellipse(this.ratio);
  final double ratio;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final c = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(1, ratio * bounds.width / bounds.height, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }
}

/// Stretches a radial gradient to its box's width: the circle (sized by the
/// box's height) becomes an ellipse as wide as the box.
class _Flatten extends GradientTransform {
  const _Flatten();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final c = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(bounds.width / bounds.height, 1, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }
}

/// TODAY'S CAR, in brand red.
class TodayChip extends StatelessWidget {
  const TodayChip({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(14)),
        child: Text(
          text,
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white, height: 1.2),
        ),
      );
}

/// The toy on the card, on a soft elliptical contact shadow. When the card
/// lands ([active] turns on) the toy fades and scales in from 0.86, then one
/// streak of light crosses its own pixels. Nothing else moves.
class HeroToy extends StatefulWidget {
  const HeroToy({super.key, required this.car, required this.width, required this.mine, required this.active});
  final Car car;
  final double width;
  final bool mine;
  final bool active;

  @override
  State<HeroToy> createState() => _HeroToyState();
}

class _HeroToyState extends State<HeroToy> with TickerProviderStateMixin {
  late final _land = AnimationController(vsync: this, duration: kToyLandDuration);
  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _land.addStatusListener((s) {
      if (s == AnimationStatus.completed && widget.active) _sweep.forward(from: 0);
    });
    if (widget.active) _land.forward();
  }

  @override
  void didUpdateWidget(HeroToy old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _sweep.value = 0;
      _land.forward(from: 0);
    } else if (!widget.active && old.active) {
      _sweep.stop();
      _sweep.value = 0;
      _land.animateBack(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _land.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = w / kToyAspect;
    return SizedBox(
      width: w,
      height: h + 24,
      child: AnimatedBuilder(
        animation: Listenable.merge([_land, _sweep]),
        builder: (context, child) {
          final t = kToyLandCurve.transform(_land.value);
          final scale = 0.86 + 0.14 * t;
          final opacity = (0.35 + 0.65 * t).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              alignment: const Alignment(0, 0.3),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // Contact shadow under the wheels.
                  Positioned(
                    left: w * 0.07,
                    right: w * 0.07,
                    top: h * 0.78,
                    height: h * 0.22,
                    child: const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            radius: 0.5,
                            colors: [Color(0xF2000000), Color(0x00000000)],
                            stops: [0, 0.7],
                            transform: _Flatten(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ToySweep(t: _sweep.value, child: child!),
                ],
              ),
            ),
          );
        },
        child: ToyCarImage(car: widget.car, width: w, mine: widget.mine),
      ),
    );
  }
}

/// The streak of light that crosses the toy after it lands, drawn on the
/// toy's own pixels (srcATop), so it follows the car's shape.
class ToySweep extends StatelessWidget {
  const ToySweep({super.key, required this.t, required this.child});

  /// 0–1 across; nothing drawn at either end.
  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (t <= 0 || t >= 1) return child;
    final strength = t < 0.2 ? t / 0.2 : 1 - (t - 0.2) / 0.8;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (r) => LinearGradient(
        begin: const Alignment(-1, -0.35),
        end: const Alignment(1, 0.35),
        colors: [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, 0.45 * strength), const Color(0x00FFFFFF)],
        stops: const [0.4, 0.5, 0.6],
        transform: _Shift((t * 2.4 - 1.2) * r.width),
      ).createShader(r),
      child: child,
    );
  }
}

class _Shift extends GradientTransform {
  const _Shift(this.dx);
  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, 0, 0);
}

/// Small toy thumbnails, one per car, the one in view with a brand-red
/// border. Four to a row; more scroll sideways.
class ToyRail extends StatelessWidget {
  const ToyRail({super.key, required this.cars, required this.index, required this.mine, required this.onPick});
  final List<Car> cars;
  final int index;
  final bool mine;
  final ValueChanged<int> onPick;

  static const gap = 10.0;
  static const height = 72.0;

  @override
  Widget build(BuildContext context) {
    if (cars.length <= 4) {
      return SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < cars.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(child: _Thumb(car: cars[i], selected: i == index, mine: mine, onTap: () => onPick(i))),
            ],
          ],
        ),
      );
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: cars.length,
        separatorBuilder: (_, _) => const SizedBox(width: gap),
        itemBuilder: (_, i) => SizedBox(width: 84, child: _Thumb(car: cars[i], selected: i == index, mine: mine, onTap: () => onPick(i))),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.car, required this.selected, required this.mine, required this.onTap});
  final Car car;
  final bool selected;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '${car.make} ${car.model}',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: StudioColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? AppColors.brand : StudioColors.edge, width: 2),
            ),
            child: Center(child: ToyCarImage(car: car, width: 64, mine: mine, caption: false)),
          ),
        ),
      );
}

/// Mods / Spent (mine) / Meets / Posts, in one card. A number still loading
/// shows as a dash.
class StatsRow extends StatelessWidget {
  const StatsRow({super.key, required this.facts, required this.mine});
  final GarageFacts facts;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final f = facts;
    final spent = f.spent;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: StudioColors.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: StudioColors.edge)),
      child: Row(
        children: [
          _Stat(value: f.mods?.length.toString(), label: 'Mods'),
          if (mine) _Stat(value: spent == null ? null : 'RM ${compactMoney(spent)}', label: 'Spent'),
          _Stat(value: f.meets?.toString(), label: 'Meets'),
          _Stat(value: f.posts?.toString(), label: 'Posts'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ts = _scaler(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value ?? '–',
                maxLines: 1,
                textScaler: ts,
                style: const TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w800, height: 1, color: StudioColors.text),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textScaler: ts, style: const TextStyle(fontSize: 12, height: 1.2, color: StudioColors.textSoft)),
          ],
        ),
      ),
    );
  }
}

/// A 52 px pill: white (filled) or glass. A long label shrinks to fit.
class StudioButton extends StatelessWidget {
  const StudioButton({super.key, required this.label, required this.onTap, this.filled = true, this.icon});
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? StudioColors.page : Colors.white;
    return Semantics(
      button: true,
      child: Material(
        color: filled ? Colors.white : StudioColors.glass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: filled ? BorderSide.none : const BorderSide(color: Color(0x33FFFFFF)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
                      Text(label, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The owner's papers, one row each: road tax, insurance, PUSPAKOM, service.
/// Nothing is made up: no papers saved shows one quiet row to add them, and
/// nothing at all until they have loaded.
class PapersRows extends StatelessWidget {
  const PapersRows({super.key, required this.facts, this.onTap});
  final GarageFacts facts;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!facts.papersLoaded) return const SizedBox.shrink();
    final dues = facts.papers?.dues ?? const <DocDue>[];
    if (dues.isEmpty) {
      return _PaperRow(
        dot: StudioColors.textSoft,
        title: 'Road tax and insurance',
        subtitle: 'Add the dates to get a reminder',
        trailing: 'Add',
        trailingColor: Colors.white,
        onTap: onTap,
      );
    }
    return Column(
      children: [
        for (var i = 0; i < dues.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _PaperRow.due(dues[i], onTap: onTap),
        ],
      ],
    );
  }
}

class _PaperRow extends StatelessWidget {
  const _PaperRow({required this.dot, required this.title, required this.subtitle, required this.trailing, required this.trailingColor, this.onTap});

  factory _PaperRow.due(DocDue d, {VoidCallback? onTap}) {
    final days = d.daysLeft;
    final (Color color, String word) = days < 0
        ? (StudioColors.red, d.kind.expires ? 'Expired' : 'Overdue')
        : days < 30
            ? (StudioColors.amber, 'Soon')
            : (StudioColors.green, 'OK');
    final when = d.when;
    return _PaperRow(
      dot: color,
      title: d.kind.label,
      subtitle: when[0].toUpperCase() + when.substring(1),
      trailing: word,
      trailingColor: color,
      onTap: onTap,
    );
  }

  final Color dot;
  final String title;
  final String subtitle;
  final String trailing;
  final Color trailingColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ts = _scaler(context);
    return Semantics(
      button: onTap != null,
      child: Material(
        color: StudioColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: StudioColors.edge)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textScaler: ts, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25, color: StudioColors.text)),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, textScaler: ts, style: const TextStyle(fontSize: 13, height: 1.25, color: StudioColors.textSoft)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(trailing, maxLines: 1, textScaler: ts, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: trailingColor)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A studio card for an empty garage: TiTi, a title, a line and, for the
/// owner, the Add a car button.
class GarageEmptyCard extends StatelessWidget {
  const GarageEmptyCard({super.key, required this.pose, required this.title, required this.subtitle, this.actionLabel, this.onAction});
  final TitiPose pose;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPad),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(color: StudioColors.edge),
            gradient: const RadialGradient(
              center: Alignment(0, -0.2),
              radius: 0.9,
              colors: [StudioColors.lift, StudioColors.card],
              stops: [0, 0.78],
              transform: _Ellipse(0.61),
            ),
          ),
          child: Column(
            children: [
              Titi(pose, height: 140),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w800, height: 1, color: StudioColors.text)),
              const SizedBox(height: 8),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.4, color: StudioColors.textSoft)),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                SizedBox(width: 200, child: StudioButton(label: actionLabel!, icon: AppIcons.plus, onTap: onAction!)),
              ],
            ],
          ),
        ),
      );
}
