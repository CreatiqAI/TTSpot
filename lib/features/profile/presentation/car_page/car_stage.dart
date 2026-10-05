import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverScrollHeaderStretchConfiguration;
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car.dart';
import '../garage/garage_images.dart';
import '../garage/garage_scenery.dart';
import 'car_page_model.dart';

/// How far the white sheet rides up over the bottom of the stage.
const kSheetOverlap = 22.0;

/// The top of the car page: the dark garage bay with the selected media on
/// it (the cut-out standing on the floor, or a photo or portrait as a framed
/// print), back / share / more over it and a caption bottom-left. Scrolling
/// slides the bay away at half speed under the sheet and leaves a plain bar
/// with the car's name pinned at the top.
class CarStageDelegate extends SliverPersistentHeaderDelegate {
  CarStageDelegate({
    required this.car,
    required this.media,
    required this.mine,
    required this.topInset,
    required this.stageHeight,
    required this.imageFor,
    required this.onBack,
    required this.onShare,
    required this.onMore,
    required this.onOpen,
    this.bayIndex,
  });

  final Car car;

  /// What's on the stage; null when the car has no picture at all.
  final CarMedia? media;
  final bool mine;
  final double topInset;

  /// The bay's height below the status bar.
  final double stageHeight;
  final CarImageResolver imageFor;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback? onMore;
  final VoidCallback onOpen;
  final int? bayIndex;

  static const _bar = 56.0;

  @override
  double get minExtent => topInset + _bar;

  @override
  double get maxExtent => topInset + stageHeight;

  @override
  bool shouldRebuild(covariant CarStageDelegate old) => true;

  /// Pulled past the top (iOS bounce), the bay grows instead of showing a gap.
  @override
  OverScrollHeaderStretchConfiguration get stretchConfiguration => OverScrollHeaderStretchConfiguration();

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    // The plain bar fades in over the last part of the collapse.
    final bar = ((t - 0.72) / 0.24).clamp(0.0, 1.0);
    final overlay = bar > 0.5
        ? AppTheme.systemOverlay
        : AppTheme.systemOverlay.copyWith(statusBarIconBrightness: Brightness.light, statusBarBrightness: Brightness.dark);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: ClipRect(
        child: LayoutBuilder(
          // Taller than its full height only while stretched.
          builder: (context, c) => Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: c.maxHeight > maxExtent ? 0 : -shrinkOffset * 0.5,
                left: 0,
                right: 0,
                height: c.maxHeight > maxExtent ? c.maxHeight : maxExtent,
                child: CarStageScene(
                  car: car,
                  media: media,
                  mine: mine,
                  topInset: topInset,
                  bayIndex: bayIndex,
                  imageFor: imageFor,
                  onTap: t < 0.3 ? onOpen : null,
                ),
              ),
              // The sheet's rounded top edge, riding up over the floor.
              Positioned(
                left: 0,
                right: 0,
                bottom: -1,
                height: kSheetOverlap + 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24 * (1 - bar))),
                    ),
                  ),
                ),
              ),
              if (bar > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.bg.withValues(alpha: bar),
                        border: Border(bottom: BorderSide(color: AppColors.divider.withValues(alpha: bar))),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: topInset + 6,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    _StageButton(icon: AppIcons.arrowLeft, tooltip: 'Back', t: bar, onTap: onBack),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Opacity(
                        opacity: bar,
                        child: Text(
                          car.model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: AppFonts.display, fontSize: 21, fontWeight: FontWeight.w800, height: 1.1, color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StageButton(icon: AppIcons.shareFat, tooltip: 'Share', t: bar, onTap: onShare),
                    if (onMore != null) ...[
                      const SizedBox(width: 8),
                      _StageButton(icon: AppIcons.dotsThree, tooltip: 'More', t: bar, onTap: onMore!),
                    ],
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

/// A round button on the bay: frosted white on the dark stage, plain once
/// the stage has scrolled away ([t] = 1).
class _StageButton extends StatelessWidget {
  const _StageButton({required this.icon, required this.tooltip, required this.t, required this.onTap});
  final IconData icon;
  final String tooltip;
  final double t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.12 * (1 - t))),
              child: Icon(icon, size: 20, color: Color.lerp(Colors.white, AppColors.textPrimary, t)),
            ),
          ),
        ),
      );
}

/// The bay itself with one piece of media on it. [onTap] opens it full screen.
class CarStageScene extends StatelessWidget {
  const CarStageScene({super.key, required this.car, required this.media, required this.mine, required this.topInset, required this.imageFor, this.bayIndex, this.onTap});

  final Car car;
  final CarMedia? media;
  final bool mine;
  final double topInset;
  final CarImageResolver imageFor;
  final int? bayIndex;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final stage = h - topInset;
        final m = media;
        final caption = m == null ? (mine ? 'NO PHOTO YET · ADD ONE IN EDIT' : 'NO PHOTO YET') : m.caption(mine: mine);
        return Stack(
          fit: StackFit.expand,
          children: [
            const BayBackdrop(floorAt: 0.62, lineInset: 36),
            if (bayIndex != null)
              Positioned(
                right: 20,
                top: topInset + stage * 0.23,
                child: BayNumber(text: bayNumber(bayIndex!), size: stage * 0.35),
              ),
            CeilingLight(top: topInset + 52, inset: 60, washCenter: const Alignment(0, -0.64), floorPoolHeight: h * 0.4),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: m == null ? null : onTap,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), alignment: Alignment.bottomCenter, child: child),
                  ),
                  layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                  child: KeyedSubtree(
                    key: ValueKey(m?.url ?? 'none'),
                    child: switch (m?.kind) {
                      null => _GhostCar(car: car, stageWidth: w, stageHeight: h, topInset: topInset),
                      CarMediaKind.cutout => _CutoutOnStage(
                          car: car,
                          image: imageFor(m!.url),
                          fallback: car.photoCover == null ? null : imageFor(car.photoCover!),
                          stageWidth: w,
                          stageHeight: h,
                          topInset: topInset,
                        ),
                      _ => _PrintOnStage(image: imageFor(m!.url), label: m.caption(mine: mine), stageWidth: w, stageHeight: h, topInset: topInset),
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: kSheetOverlap + 8,
              child: IgnorePointer(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2, color: Colors.white.withValues(alpha: 0.55)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Where a print hangs: centred, 46 px above the stage's bottom, landscape,
/// and clear of the ceiling tube and the buttons.
Rect _printRect(double w, double h, double topInset) {
  const bottom = 46.0;
  const aspect = 1.45;
  final stage = h - topInset;
  final room = stage - bottom - 68;
  var pw = w * 0.72 < 300 ? w * 0.72 : 300.0;
  var ph = pw / aspect;
  if (ph > room) {
    ph = room;
    pw = ph * aspect;
  }
  return Rect.fromLTWH((w - pw) / 2, h - bottom - ph, pw, ph);
}

/// A photo or portrait as a framed print on the back wall.
class _PrintOnStage extends StatelessWidget {
  const _PrintOnStage({required this.image, required this.label, required this.stageWidth, required this.stageHeight, required this.topInset});
  final ImageProvider image;
  final String label;
  final double stageWidth;
  final double stageHeight;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final r = _printRect(stageWidth, stageHeight, topInset);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: r,
          child: SilverPrint(
            child: Image(
              image: image,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              semanticLabel: label,
              errorBuilder: (_, _, _) => Center(child: Icon(AppIcons.imageBroken, color: Colors.white.withValues(alpha: 0.4))),
            ),
          ),
        ),
      ],
    );
  }
}

/// The cut-out standing on the floor with its reflection. Fades in once it
/// has loaded; if it can't load, the cover photo hangs as a print instead.
class _CutoutOnStage extends StatefulWidget {
  const _CutoutOnStage({required this.car, required this.image, required this.fallback, required this.stageWidth, required this.stageHeight, required this.topInset});
  final Car car;
  final ImageProvider image;
  final ImageProvider? fallback;
  final double stageWidth;
  final double stageHeight;
  final double topInset;

  @override
  State<_CutoutOnStage> createState() => _CutoutOnStageState();
}

class _CutoutOnStageState extends State<_CutoutOnStage> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    (_, _) => _update(() => _ready = true),
    onError: (_, _) => _update(() => _failed = true),
  );
  bool _ready = false;
  bool _failed = false;
  bool _resolving = false;

  void _update(VoidCallback change) {
    if (_resolving) {
      change();
    } else if (mounted) {
      setState(change);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = widget.image.resolve(createLocalImageConfiguration(context));
    if (next.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _resolving = true;
    _stream = next..addListener(_listener);
    _resolving = false;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.stageWidth, h = widget.stageHeight;
    if (_failed) {
      final f = widget.fallback;
      return f == null
          ? _GhostCar(car: widget.car, stageWidth: w, stageHeight: h, topInset: widget.topInset)
          : _PrintOnStage(image: f, label: widget.car.title, stageWidth: w, stageHeight: h, topInset: widget.topInset);
    }
    const floor = kSheetOverlap + 32;
    final stage = h - widget.topInset;
    final box = (h * 0.5).clamp(0.0, stage - floor - 56);
    return AnimatedOpacity(
      opacity: _ready ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: StandingCutout(image: widget.image, stageWidth: w, stageHeight: h, box: box, bottom: floor, side: 22, semanticLabel: widget.car.title),
    );
  }
}

/// No picture yet: a grey silhouette of the body style on the floor.
class _GhostCar extends StatelessWidget {
  const _GhostCar({required this.car, required this.stageWidth, required this.stageHeight, required this.topInset});
  final Car car;
  final double stageWidth;
  final double stageHeight;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final stage = stageHeight - topInset;
    const floor = kSheetOverlap + 30;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 40,
          right: 40,
          bottom: floor,
          height: (stage * 0.48).clamp(0.0, stage - floor - 56),
          child: ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF2A2E36), Color(0xFF3A3F49)]).createShader(r),
            child: Image.asset(carPlaceholderAsset(car.bodyStyle), fit: BoxFit.contain, alignment: Alignment.bottomCenter),
          ),
        ),
      ],
    );
  }
}

/// Under the stage: one thumbnail per media, the selected one ringed in red,
/// portraits marked with a small sparkle.
class CarMediaStrip extends StatelessWidget {
  const CarMediaStrip({super.key, required this.media, required this.selected, required this.onPick, required this.imageFor});
  final List<CarMedia> media;
  final int selected;
  final ValueChanged<int> onPick;
  final CarImageResolver imageFor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: media.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final m = media[i];
          final on = i == selected;
          return Semantics(
            button: true,
            selected: on,
            label: m.label,
            child: GestureDetector(
              onTap: () => onPick(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: GarageColors.wallMid,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: on ? AppColors.brand : Colors.transparent, width: 2.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11.5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image(
                        image: ResizeImage(imageFor(m.url), width: 180, policy: ResizeImagePolicy.fit),
                        fit: m.kind == CarMediaKind.cutout ? BoxFit.contain : BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => Icon(AppIcons.image, size: 18, color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      if (m.isPortrait)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            width: 16,
                            height: 16,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                            child: const Icon(AppIcons.sparkle, size: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
