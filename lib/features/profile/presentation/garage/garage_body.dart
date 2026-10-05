import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../social/application/social_providers.dart';
import '../../application/cutout_providers.dart';
import '../../application/garage_providers.dart';
import '../../application/profile_providers.dart';
import '../../application/toy_providers.dart';
import '../../domain/car.dart';
import '../../domain/garage_look.dart';
import '../widgets/car_actions_sheet.dart';
import 'garage_facts.dart';
import 'garage_images.dart';
import 'garage_studio.dart';

export 'garage_facts.dart' show GarageFacts, compactMoney;

/// The car that fronts everything: the flagged default, else the first.
Car? todaysCar(List<Car> cars) => cars.where((c) => c.isDefault).firstOrNull ?? cars.firstOrNull;

/// Cars keep their order: the first car parked comes first. (Today's car is
/// where the garage opens, not a reshuffle.)
List<Car> garageOrder(List<Car> cars) => [...cars]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

/// A garage, mine or someone else's: the studio card with the car's toy, the
/// rail of the other cars, the numbers and buttons. Read-only for someone
/// else's: no edit, today's car or add.
class GarageBody extends ConsumerStatefulWidget {
  const GarageBody({super.key, required this.ownerId, required this.title, this.onBack, this.bottomPadding = 0, this.empty});

  final String ownerId;

  /// "My garage", "Keith's garage".
  final String title;

  /// Shows the back button (the full-screen routes; not the Home tab).
  final VoidCallback? onBack;

  /// Room kept clear at the bottom: the home indicator, or the floating tab
  /// bar on Home.
  final double bottomPadding;

  /// Shown when the garage has no cars.
  final Widget? empty;

  @override
  ConsumerState<GarageBody> createState() => _GarageBodyState();
}

class _GarageBodyState extends ConsumerState<GarageBody> {
  int _index = 0;

  /// The car the garage is on, so a reload keeps the same car in view.
  String? _focus;
  final _backfilled = <String>{};
  int _precached = -1;

  bool get _mine => ref.read(currentUserIdProvider) == widget.ownerId;

  /// Keeps the same car in view when the list reloads; a car just added
  /// comes into view.
  void _sync(List<Car> cars) {
    if (_focus == null) {
      final today = todaysCar(cars);
      _index = today == null ? 0 : cars.indexOf(today);
    } else {
      final i = cars.indexWhere((c) => c.id == _focus);
      _index = i >= 0 ? i : cars.length - 1;
    }
    _index = _index.clamp(0, cars.length - 1);
    _focus = cars[_index].id;
  }

  void _setIndex(int i, List<Car> cars) {
    if (i < 0 || i >= cars.length) return;
    setState(() {
      _index = i;
      _focus = cars[i].id;
    });
  }

  /// The owner's phone makes missing cut-outs as the garage opens (the toy's
  /// stand-in while it is built).
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
        final toy = garageToyProvider(c);
        final cut = toy == null && garageLookFor(c) == GarageLook.cutout ? garageCutoutProvider(c) : null;
        final photo = toy == null && cut == null ? garagePhotoProvider(c) : null;
        for (final p in [?toy, ?cut, ?photo]) {
          precacheImage(p, context, onError: (_, _) {});
        }
      }
    });
  }

  Future<void> _refresh() async {
    final cars = ref.read(userCarsProvider(widget.ownerId)).value ?? const <Car>[];
    for (final c in cars) {
      ref.invalidate(carModsProvider(c.id));
      ref.invalidate(carMeetsProvider(c.id));
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
    // The owner's garage keeps the toy watcher alive: a toy that lands swaps
    // in on its own.
    if (mine) ref.watch(toyWatcherProvider);
    void add() => context.push(Routes.newCar);

    GarageStudio studio({List<Car> cars = const [], GarageFacts facts = const GarageFacts(), bool loading = false, String? error}) => GarageStudio(
          cars: cars,
          index: _index,
          onIndex: (i) => _setIndex(i, cars),
          mine: mine,
          title: widget.title,
          todayId: todaysCar(cars)?.id,
          facts: facts,
          bottomPadding: widget.bottomPadding,
          onBack: widget.onBack,
          onAdd: mine ? add : null,
          onOpen: (c) => context.push(Routes.car(c.id)),
          onMore: mine ? (c) => showCarActionsSheet(context, ref, c) : null,
          onMakeToday: mine ? _makeToday : null,
          onEdit: mine ? (c) => context.push(Routes.editCar(c.id)) : null,
          onPapers: mine ? (c) => context.push(Routes.carDocuments(c.id)) : null,
          onRefresh: _refresh,
          empty: widget.empty,
          loading: loading,
          error: error,
        );

    return carsAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => studio(loading: true),
      error: (e, _) => studio(error: friendlyError(e)),
      data: (raw) {
        if (raw.isEmpty) return studio();
        final cars = garageOrder(raw);
        _sync(cars);
        if (mine) _backfill(cars);
        _precache(cars);
        final cur = cars[_index];
        final docs = mine ? ref.watch(carDocumentsProvider(cur.id)) : null;
        final facts = GarageFacts(
          mods: ref.watch(carModsProvider(cur.id)).value,
          meets: ref.watch(carMeetsProvider(cur.id)).value?.length,
          posts: ref.watch(postsWhereProvider((column: 'car_id', value: cur.id))).value?.length,
          papers: docs?.value,
          papersLoaded: docs?.hasValue ?? false,
        );
        return studio(cars: cars, facts: facts);
      },
    );
  }
}
