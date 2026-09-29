import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/glass_tab_bar.dart';
import '../../social/application/community_providers.dart';
import '../../social/application/social_providers.dart';
import '../application/profile_providers.dart';
import '../domain/car.dart';
import 'widgets/car_actions_sheet.dart';

/// The signed-in member's garage: today's car up top, every car in a row
/// below, tap one to drive it today. Lives on Home (Garage tab) and at
/// [Routes.myGarage] (from the profile's garage strip).
class GarageHomeTab extends ConsumerWidget {
  const GarageHomeTab({super.key});

  /// The car that fronts everything: the flagged default, else the first.
  static Car? todaysCar(List<Car> cars) => cars.where((c) => c.isDefault).firstOrNull ?? cars.firstOrNull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const SizedBox.shrink();
    final cars = ref.watch(userCarsProvider(me));

    Future<void> refresh() async {
      final today = todaysCar(cars.value ?? const []);
      ref.invalidate(userCarsProvider(me));
      if (today != null) {
        ref.invalidate(carModsProvider(today.id));
        ref.invalidate(postsWhereProvider((column: 'car_id', value: today.id)));
      }
      await ref.read(userCarsProvider(me).future);
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: cars.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 120, 24, 0),
              child: Text(friendlyError(e), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
        data: (list) {
          final today = todaysCar(list);
          if (today == null) return const _Empty();
          // Today's car leads the carousel, the rest keep their order.
          final ordered = [today, ...list.where((c) => c.id != today.id)];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Clear of the floating tab bar so the carousel and the hint can scroll into view.
            padding: EdgeInsets.only(bottom: GlassTabBar.height + GlassTabBar.margin.bottom + MediaQuery.paddingOf(context).bottom + 24),
            children: [
              _TodayHero(car: today),
              const SizedBox(height: 28),
              _SectionLabel(list.length > 1 ? 'YOUR CARS · ${list.length}' : 'YOUR CARS'),
              const SizedBox(height: 10),
              SizedBox(
                height: 156,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: ordered.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    if (i == ordered.length) return _AddCarCard(onTap: () => context.push(Routes.newCar));
                    final c = ordered[i];
                    final isToday = c.id == today.id;
                    return _CarCard(
                      car: c,
                      isToday: isToday,
                      onTap: isToday ? () => context.push(Routes.car(c.id)) : () => _offerSwitch(context, ref, c),
                      onMore: () => showCarActionsSheet(context, ref, c),
                    );
                  },
                ),
              ),
              if (list.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    'Today\'s car shows on the map and goes with you to meets.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// "Drive the Civic today?" Make it today's car, or just open its page.
  static Future<void> _offerSwitch(BuildContext context, WidgetRef ref, Car car) async {
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(width: 64, height: 48, child: _Cover(car: car, artSize: 28)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Drive the ${car.model} today?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2)),
                        const SizedBox(height: 3),
                        Text('It shows on the map and goes with you to meets.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _FilledAction(label: 'Make it today\'s car', onTap: () => Navigator.pop(ctx, 'today')),
              const SizedBox(height: 8),
              _OutlinedAction(label: 'Open car page', onTap: () => Navigator.pop(ctx, 'open')),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'open') {
      context.push(Routes.car(car.id));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(carFormControllerProvider.notifier).setDefault(car.id);
      messenger.showSnackBar(SnackBar(content: Text('The ${car.model} is today\'s car.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

/// Full-screen garage, opened from "Manage" on the profile's garage strip.
class MyGarageScreen extends StatelessWidget {
  const MyGarageScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
          title: const Text('My garage'),
        ),
        body: const GarageHomeTab(),
      );
}

// ------------------------------------------------------------------- hero ---

class _TodayHero extends ConsumerWidget {
  const _TodayHero({required this.car});
  final Car car;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = car;
    final mods = ref.watch(carModsProvider(c.id));
    final posts = ref.watch(postsWhereProvider((column: 'car_id', value: c.id)));
    final spent = mods.value?.fold<double>(0, (s, m) => s + (m.cost ?? 0));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('TODAY\'S CAR', inset: false),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => context.push(Routes.car(c.id)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AspectRatio(aspectRatio: 16 / 10, child: _Cover(car: c, artSize: 96)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            [c.make.toUpperCase(), if (c.year != null) '${c.year}'].join(' · '),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            c.model,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w800, height: 1.05, color: AppColors.textPrimary),
          ),
          if (c.specLine != null) ...[
            const SizedBox(height: 4),
            Text(c.specLine!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(
              children: [
                _Stat(value: mods.value?.length.toString(), label: 'Mods'),
                const _StatDivider(),
                _Stat(value: spent == null ? null : 'RM ${_compactMoney(spent)}', label: 'Spent'),
                const _StatDivider(),
                _Stat(value: posts.value?.length.toString(), label: 'Posts'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _FilledAction(label: 'Open car', onTap: () => context.push(Routes.car(c.id)))),
              const SizedBox(width: 8),
              Expanded(child: _OutlinedAction(label: 'Edit', icon: AppIcons.pencilSimple, onTap: () => context.push(Routes.editCar(c.id)))),
            ],
          ),
        ],
      ),
    );
  }
}

/// RM 850 · RM 12.5k · RM 1.2m: fits a third of a phone width.
String _compactMoney(double v) {
  String trim(double x) => x.toStringAsFixed(x >= 100 || x == x.roundToDouble() ? 0 : 1);
  if (v >= 1000000) return '${trim(v / 1000000)}m';
  if (v >= 10000) return '${trim(v / 1000)}k';
  final s = v.toStringAsFixed(0);
  return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String? value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(
              value ?? '–',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w700, height: 1, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 28, color: AppColors.border);
}

// --------------------------------------------------------------- carousel ---

const _cardWidth = 132.0;
const _thumbHeight = 99.0; // 4:3 of the card width

class _CarCard extends StatelessWidget {
  const _CarCard({required this.car, required this.isToday, required this.onTap, required this.onMore});
  final Car car;
  final bool isToday;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTap,
            onLongPress: onMore,
            child: Container(
              height: _thumbHeight,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md + 3),
                border: Border.all(color: isToday ? AppColors.brand : Colors.transparent, width: 2),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md - 1), child: _Cover(car: car, artSize: 40)),
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            onLongPress: onMore,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(car.model, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 2),
              if (isToday) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: const Text('Today', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(width: 6),
              ],
              if (car.year != null) Text('${car.year}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const Spacer(),
              SizedBox(
                width: 30,
                height: 26,
                child: IconButton(
                  tooltip: 'More',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: onMore,
                  icon: Icon(AppIcons.dotsThree, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddCarCard extends StatelessWidget {
  const _AddCarCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _cardWidth,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _thumbHeight,
              width: _cardWidth,
              child: CustomPaint(
                painter: _DashedRRect(color: AppColors.textMuted, radius: AppRadius.md + 3),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
                    child: Icon(AppIcons.plus, size: 18, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Text('Add a car', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedRRect extends CustomPainter {
  const _DashedRRect({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.7));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color || old.radius != radius;
}

// ------------------------------------------------------------------ bits ---

/// The car's portrait or first photo, or the car art on grey.
class _Cover extends StatelessWidget {
  const _Cover({required this.car, required this.artSize});
  final Car car;
  final double artSize;

  @override
  Widget build(BuildContext context) {
    final cover = car.cover;
    final blank = ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(AppArt.car, size: artSize)));
    if (cover == null) return blank;
    return Image(image: CachedNetworkImageProvider(cover), fit: BoxFit.cover, errorBuilder: (_, _, _) => blank);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.inset = true});
  final String text;
  final bool inset;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: inset ? 16 : 0),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

class _FilledAction extends StatelessWidget {
  const _FilledAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.onInk,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      );
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      foregroundColor: AppColors.textPrimary,
      side: BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );
    return icon == null
        ? OutlinedButton(onPressed: onTap, style: style, child: Text(label))
        : OutlinedButton.icon(onPressed: onTap, style: style, icon: Icon(icon, size: 16), label: Text(label));
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        children: [
          const Titi(TitiPose.camera, height: 150),
          const SizedBox(height: 18),
          const Text('Park your first car', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Your daily, your project, your weekend toy. Today\'s car shows on the map and goes with you to meets.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 200,
              child: _FilledAction(label: 'Add a car', onTap: () => context.push(Routes.newCar)),
            ),
          ),
        ],
      );
}
