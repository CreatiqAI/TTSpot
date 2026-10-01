import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../settings/application/settings_providers.dart';
import '../../../social/application/social_providers.dart';
import '../../application/cutout_providers.dart';
import '../../application/garage_providers.dart';
import '../../application/profile_providers.dart';
import '../../domain/car.dart';
import '../../domain/garage_look.dart';
import '../widgets/car_actions_sheet.dart';
import '../widgets/car_documents_section.dart';
import 'collector_card.dart';
import 'garage_bay.dart';
import 'garage_deck.dart';

/// The car that fronts everything: the flagged default, else the first.
Car? todaysCar(List<Car> cars) => cars.where((c) => c.isDefault).firstOrNull ?? cars.firstOrNull;

/// Bays keep their order: the first car parked is bay 01. (Today's car is
/// where the garage opens, not a reshuffle.)
List<Car> garageOrder(List<Car> cars) => [...cars]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

/// A garage, mine or someone else's: the stage (roller-door bay or card deck,
/// per my `garage_view` setting), the dots, then the car's panel. Read-only
/// for someone else's: no edit, today's car or add.
class GarageBody extends ConsumerStatefulWidget {
  const GarageBody({super.key, required this.ownerId, this.header, this.bottomPadding = 24, this.empty});

  final String ownerId;
  /// Above the stage (the Home tab's own title row).
  final Widget? header;
  final double bottomPadding;
  /// Shown when the garage has no cars.
  final Widget? empty;

  @override
  ConsumerState<GarageBody> createState() => _GarageBodyState();
}

class _GarageBodyState extends ConsumerState<GarageBody> {
  int _index = 0;
  /// The car (or 'add') the garage is on, so a reload keeps the same bay.
  String? _focus;
  int _lastCars = -1;
  final _backfilled = <String>{};
  int _precached = -1;

  bool get _mine => ref.read(currentUserIdProvider) == widget.ownerId;

  /// Keeps the same car in view when the list reloads; a car just added takes
  /// the bay where "Park another car" was.
  void _sync(List<Car> cars, bool mine) {
    final count = cars.length + (mine ? 1 : 0);
    if (_focus == null) {
      final today = todaysCar(cars);
      _index = today == null ? 0 : cars.indexOf(today);
    } else if (_focus == 'add') {
      _index = mine && _lastCars >= 0 && cars.length > _lastCars ? _lastCars : cars.length;
    } else {
      final i = cars.indexWhere((c) => c.id == _focus);
      if (i >= 0) _index = i;
    }
    _index = _index.clamp(0, count - 1);
    _focus = _index < cars.length ? cars[_index].id : 'add';
    _lastCars = cars.length;
  }

  void _setIndex(int i, List<Car> cars) {
    setState(() {
      _index = i;
      _focus = i < cars.length ? cars[i].id : 'add';
    });
  }

  /// The owner's phone makes missing cut-outs as the garage opens.
  void _backfill(List<Car> cars) {
    final todo = [
      for (final c in cars)
        if (needsCutout(c) && _backfilled.add('${c.id}|${c.photoCover}')) c,
    ];
    if (todo.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = ref.read(cutoutServiceProvider);
      for (final c in todo) {
        service.ensure(c);
      }
    });
  }

  /// The cars either side are decoded before the swipe gets there.
  void _precache(List<Car> cars) {
    if (_precached == _index) return;
    _precached = _index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final i in [_index - 1, _index + 1, _index]) {
        if (i < 0 || i >= cars.length) continue;
        final c = cars[i];
        final cut = garageLookFor(c) == GarageLook.cutout ? garageCutoutProvider(c) : null;
        final photo = garagePhotoProvider(c);
        for (final p in [?cut, ?photo]) {
          precacheImage(p, context, onError: (_, _) {});
        }
      }
    });
  }

  Future<void> _refresh() async {
    final cars = ref.read(userCarsProvider(widget.ownerId)).value ?? const <Car>[];
    for (final c in cars) {
      ref.invalidate(carModsProvider(c.id));
      ref.invalidate(postsWhereProvider((column: 'car_id', value: c.id)));
      if (_mine) ref.invalidate(carDocumentsProvider(c.id));
    }
    ref.invalidate(userCarsProvider(widget.ownerId));
    await ref.read(userCarsProvider(widget.ownerId).future);
  }

  Future<void> _makeToday(Car car) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(carFormControllerProvider.notifier).setDefault(car.id);
      messenger.showSnackBar(SnackBar(content: Text('The ${car.model} is today\'s car.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final mine = me != null && me == widget.ownerId;
    final carsAsync = ref.watch(userCarsProvider(widget.ownerId));
    final view = GarageView.parse(ref.watch(settingsProvider).garageView);
    final parking = mine ? ref.watch(cutoutJobsProvider) : const <String>{};
    final screenH = MediaQuery.sizeOf(context).height;
    final stageH = (screenH * (widget.header != null ? 0.44 : 0.48)).clamp(300.0, 420.0);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: carsAsync.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ?widget.header,
            const SizedBox(height: 120),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ?widget.header,
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 120, 24, 0),
              child: Text(friendlyError(e), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
        data: (raw) {
          if (raw.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [?widget.header, ?widget.empty],
            );
          }
          final cars = garageOrder(raw);
          _sync(cars, mine);
          if (mine) _backfill(cars);
          _precache(cars);
          final today = todaysCar(cars);
          final count = cars.length + (mine ? 1 : 0);
          void onIndex(int i) => _setIndex(i, cars);
          void open(Car c) => context.push(Routes.car(c.id));
          void more(Car c) => showCarActionsSheet(context, ref, c);
          void add() => context.push(Routes.newCar);

          final stage = view == GarageView.bay
              ? GarageBayStage(
                  key: const ValueKey('bay'),
                  cars: cars,
                  index: _index,
                  onIndex: onIndex,
                  height: stageH,
                  onOpen: open,
                  onLongPress: mine ? more : null,
                  onAdd: mine ? add : null,
                  parking: parking,
                )
              : GarageCardDeck(
                  key: const ValueKey('cards'),
                  cars: cars,
                  index: _index,
                  onIndex: onIndex,
                  height: stageH,
                  onOpen: open,
                  todayId: today?.id,
                  onLongPress: mine ? more : null,
                  onAdd: mine ? add : null,
                );

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: widget.bottomPadding),
            children: [
              ?widget.header,
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: stage,
                ),
              ),
              const SizedBox(height: 4),
              _Dots(count: count, index: _index, onTap: onIndex),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a), child: child),
                ),
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                child: _index < cars.length
                    ? _CarPanel(
                        key: ValueKey(cars[_index].id),
                        car: cars[_index],
                        mine: mine,
                        today: cars[_index].id == today?.id,
                        onOpen: () => open(cars[_index]),
                        onMakeToday: () => _makeToday(cars[_index]),
                        onMore: () => more(cars[_index]),
                      )
                    : _AddPanel(key: const ValueKey('add'), onAdd: add),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bay ⇄ Cards, remembered in my settings (`garage_view`).
class GarageViewToggle extends ConsumerWidget {
  const GarageViewToggle({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = GarageView.parse(ref.watch(settingsProvider).garageView);
    final cards = view == GarageView.cards;
    return IconButton(
      tooltip: cards ? 'Bay view' : 'Cards view',
      color: color,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(cards ? AppIcons.garage : AppIcons.cards, key: ValueKey(cards)),
      ),
      onPressed: () {
        final next = cards ? GarageView.bay : GarageView.cards;
        ref.read(settingsActionsProvider).patch({'garage_view': next.name}).catchError((_) {});
      },
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.onTap});
  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox(height: 14);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            label: 'Bay ${i + 1}',
            selected: i == index,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  width: i == index ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.brand : AppColors.textMuted.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Under the stage: make, name, specs, the Mods / Spent / Posts card, papers
/// due soon, then Open car and today's car / Edit (the owner's).
class _CarPanel extends ConsumerWidget {
  const _CarPanel({super.key, required this.car, required this.mine, required this.today, required this.onOpen, required this.onMakeToday, required this.onMore});
  final Car car;
  final bool mine;
  final bool today;
  final VoidCallback onOpen;
  final VoidCallback onMakeToday;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = car;
    final mods = ref.watch(carModsProvider(c.id));
    final posts = ref.watch(postsWhereProvider((column: 'car_id', value: c.id)));
    final spent = mods.value?.fold<double>(0, (s, m) => s + (m.cost ?? 0));
    // Papers that need attention soon (expired or under two weeks away): mine only.
    final docs = mine ? ref.watch(carDocumentsProvider(c.id)).value : null;
    final dueSoon = docs == null ? const <DocChipData>[] : docChips(docs).where((d) => d.urgent).toList();
    final make = [c.make.toUpperCase(), if (c.year != null) '${c.year}'].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(make, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2.5, color: AppColors.textSecondary)),
              if (today)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text(mine ? 'TODAY\'S CAR' : 'DAILY', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            c.model,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AppFonts.display, fontSize: 38, fontWeight: FontWeight.w800, height: 1.05, color: AppColors.textPrimary),
          ),
          if (c.specLine != null) ...[
            const SizedBox(height: 2),
            Text(c.specLine!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                _Stat(value: mods.value?.length.toString(), label: 'Mods'),
                const _StatDivider(),
                if (mine)
                  _Stat(value: spent == null ? null : 'RM ${compactMoney(spent)}', label: 'Spent')
                else
                  _Stat(value: '${c.photoUrls.length}', label: 'Photos'),
                const _StatDivider(),
                _Stat(value: posts.value?.length.toString(), label: 'Posts'),
              ],
            ),
          ),
          if (dueSoon.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => context.push(Routes.carDocuments(c.id)),
              child: Wrap(spacing: 6, runSpacing: 6, children: [for (final d in dueSoon) DocChip(chip: d)]),
            ),
          ],
          const SizedBox(height: 14),
          if (mine)
            Row(
              children: [
                Expanded(child: _FilledAction(label: 'Open car', onTap: onOpen)),
                const SizedBox(width: 8),
                Expanded(
                  child: today
                      ? _OutlinedAction(label: 'Edit', icon: AppIcons.pencilSimple, onTap: () => context.push(Routes.editCar(c.id)))
                      : _OutlinedAction(label: 'Make today\'s car', onTap: onMakeToday),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'More',
                  onPressed: onMore,
                  icon: Icon(AppIcons.dotsThree, color: AppColors.textPrimary),
                ),
              ],
            )
          else
            _FilledAction(label: 'Open car', onTap: onOpen),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Under the empty bay: what it's for and the Add button.
class _AddPanel extends StatelessWidget {
  const _AddPanel({super.key, required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('EMPTY BAY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2.5, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(
              'Park another car',
              style: TextStyle(fontFamily: AppFonts.display, fontSize: 38, fontWeight: FontWeight.w800, height: 1.05, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Your daily, your project, your weekend toy. Each car gets its own bay.',
              style: TextStyle(fontSize: 14, height: 1.35, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            _FilledAction(label: 'Add a car', icon: AppIcons.plus, onTap: onAdd),
          ],
        ),
      );
}

/// RM 850 · RM 12.5k · RM 1.2m: fits a third of a phone width.
String compactMoney(double v) {
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
              style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w700, height: 1.1, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 28, color: AppColors.border);
}

class _FilledAction extends StatelessWidget {
  const _FilledAction({required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      backgroundColor: AppColors.textPrimary,
      foregroundColor: AppColors.onInk,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false);
    return icon == null
        ? FilledButton(onPressed: onTap, style: style, child: text)
        : FilledButton.icon(onPressed: onTap, style: style, icon: Icon(icon, size: 18), label: text);
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      foregroundColor: AppColors.textPrimary,
      side: BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false);
    return icon == null
        ? OutlinedButton(onPressed: onTap, style: style, child: text)
        : OutlinedButton.icon(onPressed: onTap, style: style, icon: Icon(icon, size: 16), label: text);
  }
}
