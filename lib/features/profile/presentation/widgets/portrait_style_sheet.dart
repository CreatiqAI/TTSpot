import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_header.dart';
import '../../../points/application/points_providers.dart';
import '../../application/portrait_providers.dart';
import '../../domain/car.dart';
import '../../domain/portrait_style.dart';
import 'portrait_sample_preview.dart';

/// "Which look?" The 8 portrait styles, each with a real sample (one Porsche
/// 911 in every style). Tapping one opens the full-screen preview, whose
/// "Paint my …" button runs the confirm sheet (price in points) and books the
/// job; the server takes the points and the car page shows it painting.
Future<void> showPortraitStyleSheet(BuildContext context, WidgetRef ref, Car car) async {
  final messenger = ScaffoldMessenger.of(context);
  if (car.photoUrls.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Add a photo of the car first. The portrait is painted from it.')));
    return;
  }
  // Fresh switch and price: an admin may have changed either since the page opened.
  ref.invalidate(portraitSettingsProvider);
  final settings = await ref.read(portraitSettingsProvider.future);
  if (!context.mounted) return;
  if (!settings.enabled) {
    messenger.showSnackBar(const SnackBar(content: Text('AI portraits are paused right now. Try again later.')));
    return;
  }
  ref.invalidate(pointsBalanceProvider); // the confirm sheet shows a fresh balance
  await showModalBottomSheet<void>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Opens at about 85 % of the screen with the page peeking above it, so
    // it reads as a sheet you can swipe away (the content drags it down too).
    builder: (ctx) => LayoutBuilder(
      builder: (ctx, c) {
        final full = c.maxHeight * kPortraitSheetSize;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: kPortraitSheetSize,
          maxChildSize: kPortraitSheetSize,
          minChildSize: 0, // dragged all the way down: the sheet closes
          snap: true,
          // The picker keeps its open height while the sheet slides away
          // (clipped, not squeezed), so a swipe down never overflows.
          builder: (ctx, scroll) => ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: full,
              maxHeight: full,
              child: PortraitStylePicker(car: car, cost: settings.cost, scrollController: scroll),
            ),
          ),
        );
      },
    ),
  );
}

/// Share of the screen the style sheet opens at.
const kPortraitSheetSize = 0.85;

/// The sheet's body: header, one line on price and timing, then the styles
/// two to a row. Rows size to their text (no fixed tile height), so long
/// descriptions and big font sizes wrap instead of clipping.
class PortraitStylePicker extends StatefulWidget {
  const PortraitStylePicker({super.key, required this.car, required this.cost, this.scrollController});
  final Car car;
  final int cost;

  /// The sheet's controller, so a swipe down on the styles drags the sheet
  /// once they are scrolled to the top.
  final ScrollController? scrollController;

  @override
  State<PortraitStylePicker> createState() => _PortraitStylePickerState();
}

class _PortraitStylePickerState extends State<PortraitStylePicker> {
  // One per tile, so the preview can zoom out of (and back into) its card.
  final _tiles = [for (final _ in kPortraitStyles) GlobalKey()];

  Rect? _tileRect(int i) {
    final box = _tiles[i].currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _open(int i) async {
    final started = await showPortraitSamplePreview(context, car: widget.car, cost: widget.cost, initial: i, originOf: _tileRect);
    // Painting started from the preview: the sheet's job is done too.
    if (started == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cost = widget.cost;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(title: 'Paint your ${widget.car.model}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Same car, plate blanked, in a look you pick. ${cost > 0 ? '$cost points each. ' : ''}Tap a look to see a sample first.',
              style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                controller: widget.scrollController,
                child: Column(
                  children: [
                    for (var r = 0; r < kPortraitStyles.length; r += 2) ...[
                      if (r > 0) const SizedBox(height: 10),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = r; i < r + 2; i++) ...[
                              if (i > r) const SizedBox(width: 10),
                              Expanded(
                                child: i < kPortraitStyles.length
                                    ? PortraitStyleTile(key: _tiles[i], style: kPortraitStyles[i], onTap: () => _open(i))
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Uses 300 points · you have 1,240", then Generate / Cancel. With too few
/// points Generate stays off and the sheet points to how to earn more.
/// Answers true for Generate.
Future<bool> confirmPortrait(BuildContext context, {required Car car, required PortraitStyle style, required int cost}) async {
  final go = await showModalBottomSheet<bool>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ConfirmPortraitSheet(car: car, style: style, cost: cost),
  );
  return go == true;
}

class _ConfirmPortraitSheet extends ConsumerWidget {
  const _ConfirmPortraitSheet({required this.car, required this.style, required this.cost});
  final Car car;
  final PortraitStyle style;
  final int cost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(pointsBalanceProvider);
    final have = balance.value;
    final enough = cost <= 0 || (have != null && have >= cost);
    final short = have == null ? 0 : cost - have;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(width: 88, height: 66, child: PortraitSampleImage(style: style, cacheWidth: 264)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${style.name} portrait', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Your ${car.model}. ${style.description}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(
                children: [
                  const PointsCoin(size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        children: [
                          TextSpan(text: cost > 0 ? 'Uses ${_n(cost)} points' : 'Free right now', style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: ' · you have ${have == null ? '…' : _n(have)}', style: TextStyle(color: enough ? AppColors.textSecondary : AppColors.danger)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!enough && have != null) ...[
              const SizedBox(height: 10),
              Text('You need ${_n(short)} more points. Check in at meets and spots to earn them.', style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.danger)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () {
                    final router = GoRouter.of(context);
                    // Close the confirm sheet and everything under it that is
                    // part of this flow (preview, style sheet), then go earn.
                    Navigator.of(context).popUntil((r) => r is! PopupRoute && r is! PortraitPreviewRoute);
                    router.push(Routes.points);
                  },
                  child: const Text('How to earn points'),
                ),
              ),
            ] else if (cost > 0) ...[
              const SizedBox(height: 8),
              Text('If it doesn\'t come out, you get the points back.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 16),
            PrimaryButton(label: 'Generate', loading: balance.isLoading && have == null, onPressed: enough ? () => Navigator.pop(context, true) : null),
            const SizedBox(height: 8),
            SecondaryButton(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
          ],
        ),
      ),
    );
  }

  static String _n(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// One style in the picker: its sample with the style's icon in the corner,
/// then the name and the full description (wraps; the row grows to fit).
class PortraitStyleTile extends StatelessWidget {
  const PortraitStyleTile({super.key, required this.style, required this.onTap});
  final PortraitStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Decode about as wide as the tile is drawn, not the full 1024 px.
    final px = (MediaQuery.sizeOf(context).width / 2 * MediaQuery.devicePixelRatioOf(context)).clamp(240, 1024).round();
    return Semantics(
      button: true,
      label: '${style.name}. ${style.description} See a sample.',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PortraitSampleImage(style: style, cacheWidth: px),
                    Positioned(left: 8, top: 8, child: PortraitStyleBadge(style: style)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(style.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(style.description, style: TextStyle(fontSize: 11.5, height: 1.3, color: AppColors.textSecondary)),
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

/// The style's own icon on a soft dark disc, for the corner of a sample.
class PortraitStyleBadge extends StatelessWidget {
  const PortraitStyleBadge({super.key, required this.style, this.size = 26});
  final PortraitStyle style;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.38), shape: BoxShape.circle),
        child: Icon(style.icon, size: size * 0.56, color: Colors.white.withValues(alpha: 0.95)),
      );
}

/// A style's sample picture, cropped to fill. Falls back to the style's
/// colour if the asset can't be read.
class PortraitSampleImage extends StatelessWidget {
  const PortraitSampleImage({super.key, required this.style, this.cacheWidth, this.fit = BoxFit.cover});
  final PortraitStyle style;
  final int? cacheWidth;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.asset(
        style.sampleAsset,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => ColoredBox(color: style.tint),
      );
}

/// Books the job for [style] after the member said yes. The confirm sheet
/// has already shown the price; the server checks the points again and takes
/// them. Answers true when the job started.
Future<bool> requestPortrait(WidgetRef ref, ScaffoldMessengerState messenger, Car car, PortraitStyle style) async {
  try {
    await ref.read(portraitActionsProvider).request(car.id, style.id);
    messenger.showSnackBar(SnackBar(content: Text('Painting your ${car.model} in ${style.name}. We\'ll ping you when it\'s ready.')));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return false;
  }
}
