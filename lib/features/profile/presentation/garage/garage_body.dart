import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
import 'collector_card.dart';
import 'garage_bay.dart';
import 'garage_deck.dart';
import 'garage_panel.dart';

export 'garage_panel.dart' show GarageFacts, compactMoney;

/// The car that fronts everything: the flagged default, else the first.
Car? todaysCar(List<Car> cars) => cars.where((c) => c.isDefault).firstOrNull ?? cars.firstOrNull;

/// Bays keep their order: the first car parked is bay 01. (Today's car is
/// where the garage opens, not a reshuffle.)
List<Car> garageOrder(List<Car> cars) => [...cars]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

/// Height of the floating top bar (back, title, Bay ⇄ Cards, add).
const kGarageBarHeight = 56.0;

/// A garage, mine or someone else's, full screen: the bay (or the card
/// deck, per my `garage_view` setting) from edge to edge, the top bar
/// floating over it and the car's panel at the bottom. Read-only for someone
/// else's: no edit, today's car or add.
class GarageBody extends ConsumerStatefulWidget {
  const GarageBody({super.key, required this.ownerId, required this.title, this.onBack, this.bottomPadding = 0, this.empty});

  final String ownerId;

  /// "My garage", "Keith's garage".
  final String title;

  /// Shows the back button (the full-screen routes; not the Home tab).
  final VoidCallback? onBack;

  /// Room the panel keeps clear at the bottom: the home indicator, or the
  /// floating tab bar on Home.
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
    final view = GarageView.parse(ref.watch(settingsProvider).garageView);
    final parking = mine ? ref.watch(cutoutJobsProvider) : const <String>{};
    void add() => context.push(Routes.newCar);

    Widget plain(Widget child) => GaragePlainPage(
          title: widget.title,
          onBack: widget.onBack,
          onAdd: mine ? add : null,
          onRefresh: _refresh,
          bottomPadding: widget.bottomPadding,
          child: child,
        );

    return carsAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => plain(const Padding(padding: EdgeInsets.only(top: 120), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
      error: (e, _) => plain(
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 120, 24, 0),
          child: Text(friendlyError(e), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
        ),
      ),
      data: (raw) {
        if (raw.isEmpty) return plain(widget.empty ?? const SizedBox.shrink());
        final cars = garageOrder(raw);
        _sync(cars, mine);
        if (mine) _backfill(cars);
        _precache(cars);
        final today = todaysCar(cars);
        // The panel's numbers, for the car in the bay.
        final cur = _index < cars.length ? cars[_index] : null;
        var facts = const GarageFacts();
        if (cur != null) {
          final docs = mine ? ref.watch(carDocumentsProvider(cur.id)) : null;
          facts = GarageFacts(
            mods: ref.watch(carModsProvider(cur.id)).value,
            meets: ref.watch(carMeetsProvider(cur.id)).value?.length,
            posts: ref.watch(postsWhereProvider((column: 'car_id', value: cur.id))).value?.length,
            papers: docs?.value,
            papersLoaded: docs?.hasValue ?? false,
          );
        }
        return GarageScene(
          cars: cars,
          index: _index,
          onIndex: (i) => _setIndex(i, cars),
          mine: mine,
          view: view,
          title: widget.title,
          todayId: today?.id,
          parking: parking,
          facts: facts,
          bottomPadding: widget.bottomPadding,
          onBack: widget.onBack,
          onToggleView: () {
            final next = view == GarageView.cards ? GarageView.bay : GarageView.cards;
            ref.read(settingsActionsProvider).patch({'garage_view': next.name}).catchError((_) {});
          },
          onAdd: mine ? add : null,
          onOpen: (c) => context.push(Routes.car(c.id)),
          onMore: mine ? (c) => showCarActionsSheet(context, ref, c) : null,
          onMakeToday: mine ? _makeToday : null,
          onEdit: mine ? (c) => context.push(Routes.editCar(c.id)) : null,
          onPapers: mine ? (c) => context.push(Routes.carDocuments(c.id)) : null,
          onRefresh: _refresh,
        );
      },
    );
  }
}

/// The garage on the whole screen, from plain data (no providers), so it can
/// be pumped in tests: the bay or the card deck edge to edge, the top bar
/// floating over it, and the slim panel at the bottom. The panel names the
/// car and holds its buttons; pulled up (to ~60 %) it shows the numbers,
/// papers and latest mods while the bay rises and the car shrinks to stay in
/// view. Swiping the bay changes car and the panel cross-fades to it.
class GarageScene extends StatefulWidget {
  const GarageScene({
    super.key,
    required this.cars,
    required this.index,
    required this.onIndex,
    required this.mine,
    required this.view,
    required this.title,
    required this.onOpen,
    this.todayId,
    this.parking = const {},
    this.facts = const GarageFacts(),
    this.bottomPadding = 0,
    this.onBack,
    this.onToggleView,
    this.onAdd,
    this.onMore,
    this.onMakeToday,
    this.onEdit,
    this.onPapers,
    this.onRefresh,
  });

  final List<Car> cars;
  final int index;
  final ValueChanged<int> onIndex;
  final bool mine;
  final GarageView view;
  final String title;
  final ValueChanged<Car> onOpen;
  final String? todayId;
  final Set<String> parking;

  /// The numbers for the car in the bay ([index]).
  final GarageFacts facts;
  final double bottomPadding;
  final VoidCallback? onBack;
  final VoidCallback? onToggleView;

  /// The owner's: the + in the top bar and the empty bay at the end.
  final VoidCallback? onAdd;

  /// The owner's: the car's menu (long-press, or More in the panel).
  final ValueChanged<Car>? onMore;
  final ValueChanged<Car>? onMakeToday;
  final ValueChanged<Car>? onEdit;
  final ValueChanged<Car>? onPapers;
  final Future<void> Function()? onRefresh;

  @override
  State<GarageScene> createState() => _GarageSceneState();
}

class _GarageSceneState extends State<GarageScene> {
  final _sheet = DraggableScrollableController();

  /// How far the panel is pulled up past its collapsed height, in px.
  final _lift = ValueNotifier<double>(0);

  /// The roller door (0 shut, 1 up): the panel slides in as it opens.
  late final _door = ValueNotifier<double>(widget.view == GarageView.bay && GarageBayStage.doorWillPlay ? 0 : 1);

  /// Measured heights of the collapsed part and of the rest of the panel.
  double? _peek;
  double? _rest;
  double _height = 0;
  double _minSize = 0.2;
  double _maxSize = 0.6;
  double? _lastMin;
  double? _lastMax;

  bool get _onAddBay => widget.index >= widget.cars.length;

  @override
  void didUpdateWidget(GarageScene old) {
    super.didUpdateWidget(old);
    // Bay chosen again before the door has played this session: it rolls,
    // and the panel waits for it.
    if (old.view != widget.view && widget.view == GarageView.bay && GarageBayStage.doorWillPlay) _door.value = 0;
  }

  @override
  void dispose() {
    _sheet.dispose();
    _lift.dispose();
    _door.dispose();
    super.dispose();
  }

  void _onPeek(Size s) {
    if (!mounted) return;
    if (_peek == null || (s.height - _peek!).abs() > 0.5) setState(() => _peek = s.height);
  }

  void _onRest(Size s) {
    if (!mounted) return;
    if (_rest == null || (s.height - _rest!).abs() > 0.5) setState(() => _rest = s.height);
  }

  bool _onSheet(DraggableScrollableNotification n) {
    _lift.value = math.max(0, (n.extent - n.minExtent) * _height);
    return false;
  }

  void _toggle() {
    if (!_sheet.isAttached) return;
    final open = _lift.value > 8;
    _sheet.animateTo(open ? _minSize : _maxSize, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  /// When the sizes change under it (a new car, data arriving, a new text
  /// size) the panel keeps its state: collapsed stays collapsed, open grows
  /// or shrinks to the new content.
  void _track(double min, double max) {
    final lastMin = _lastMin, lastMax = _lastMax;
    _lastMin = min;
    _lastMax = max;
    if (lastMin == null || lastMax == null) return;
    if ((min - lastMin).abs() < 0.0005 && (max - lastMax).abs() < 0.0005) return;
    final wasOpen = _lift.value > 8;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheet.isAttached) return;
      final size = _sheet.size;
      if (!wasOpen && (size - min).abs() > 0.0005) {
        _sheet.jumpTo(min);
      } else if (wasOpen && (size - lastMax).abs() < 0.01 && (max - size).abs() > 0.0005 && max > min) {
        _sheet.animateTo(max, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      }
      _lift.value = math.max(0, (_sheet.size - min) * _height);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        final h = size.height;
        _height = h;
        final k = garageScale(size);
        final padTop = MediaQuery.paddingOf(context).top;
        final topInset = padTop + kGarageBarHeight;
        final pad = widget.bottomPadding;
        // Until the panel has been measured (the first frame): a fair guess.
        final peek = _peek ?? (150 + 72 * MediaQuery.textScalerOf(context).scale(1)) * k;
        final collapsed = peek + pad;
        final min = (collapsed / h).clamp(0.1, 0.9);
        // Pulled up: ~60 % of the screen, more on a short one, never more
        // than the content, and a strip of the bay always shows.
        final scene = math.max(80.0, h * 0.16);
        final cap = math.max(min, math.min(math.max(0.6, min + 0.3), (h - topInset - scene) / h));
        final rest = _onAddBay ? 0.0 : (_rest ?? double.infinity);
        final max = rest < 1 ? min : ((collapsed + rest) / h).clamp(min, cap);
        _minSize = min;
        _maxSize = max;
        _track(min, max);

        final insets = EdgeInsets.only(top: topInset, bottom: collapsed);
        final stage = widget.view == GarageView.bay
            ? GarageBayStage(
                key: const ValueKey('bay'),
                cars: widget.cars,
                index: widget.index,
                onIndex: widget.onIndex,
                onOpen: widget.onOpen,
                insets: insets,
                lift: _lift,
                door: _door,
                onLongPress: widget.onMore,
                onAdd: widget.onAdd,
                parking: widget.parking,
              )
            : GarageCardDeck(
                key: const ValueKey('cards'),
                cars: widget.cars,
                index: widget.index,
                onIndex: widget.onIndex,
                onOpen: widget.onOpen,
                insets: insets,
                lift: _lift,
                todayId: widget.todayId,
                onLongPress: widget.onMore,
                onAdd: widget.onAdd,
              );

        Widget bay = AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: stage,
        );
        final refresh = widget.onRefresh;
        if (refresh != null) {
          // Pull the bay down to refresh (it never moves itself).
          bay = RefreshIndicator(
            onRefresh: refresh,
            edgeOffset: topInset,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
              child: SingleChildScrollView(
                primary: false,
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                child: SizedBox(width: size.width, height: h, child: bay),
              ),
            ),
          );
        }

        final count = widget.cars.length + (widget.onAdd != null ? 1 : 0);
        final car = _onAddBay ? null : widget.cars[widget.index];
        final id = car?.id ?? 'add';
        final peekChild = car == null
            ? GarageAddPeek(key: const ValueKey('peek-add'), k: k, onAdd: widget.onAdd ?? () {})
            : GarageCarPeek(
                key: ValueKey('peek-$id'),
                car: car,
                mine: widget.mine,
                today: car.id == widget.todayId,
                k: k,
                onOpen: () => widget.onOpen(car),
                onMakeToday: widget.onMakeToday == null ? null : () => widget.onMakeToday!(car),
                onEdit: widget.onEdit == null ? null : () => widget.onEdit!(car),
                onMore: widget.onMore == null ? null : () => widget.onMore!(car),
              );
        final restChild = car == null
            ? const SizedBox.shrink(key: ValueKey('more-add'))
            : GarageCarMore(
                key: ValueKey('more-$id'),
                car: car,
                mine: widget.mine,
                facts: widget.facts,
                k: k,
                onOpen: () => widget.onOpen(car),
                onPapers: widget.onPapers == null ? null : () => widget.onPapers!(car),
              );

        final sheet = DraggableScrollableSheet(
          controller: _sheet,
          initialChildSize: min,
          minChildSize: min,
          maxChildSize: max,
          snap: max > min + 0.01,
          builder: (context, scroll) => PanelGlass(
            child: SingleChildScrollView(
              controller: scroll,
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SizeReporter(
                    onSize: _onPeek,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _lift,
                          builder: (_, up, _) => PanelHandle(
                            count: count,
                            index: widget.index,
                            onDot: widget.onIndex,
                            expanded: up > 8,
                            onToggle: max > min + 0.01 ? _toggle : null,
                          ),
                        ),
                        _crossFade(peekChild),
                      ],
                    ),
                  ),
                  // Out of sight (and reach) until the panel is pulled up.
                  _SizeReporter(
                    onSize: _onRest,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _lift,
                      builder: (_, up, child) => IgnorePointer(
                        ignoring: up < 8,
                        child: Opacity(opacity: (up / 48).clamp(0.0, 1.0), child: child),
                      ),
                      child: _crossFade(restChild),
                    ),
                  ),
                  SizedBox(height: pad),
                ],
              ),
            ),
          ),
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.systemOverlay.copyWith(statusBarIconBrightness: Brightness.light, statusBarBrightness: Brightness.dark),
          child: ColoredBox(
            color: GarageColors.wallBottom,
            child: Stack(
              fit: StackFit.expand,
              children: [
                bay,
                // The panel slides up as the roller door finishes.
                NotificationListener<DraggableScrollableNotification>(
                  onNotification: _onSheet,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _door,
                    builder: (_, door, child) {
                      final t = widget.view == GarageView.cards ? 1.0 : Curves.easeOutCubic.transform(((door - 0.45) / 0.55).clamp(0.0, 1.0));
                      // One shape whatever the door does: the sheet must
                      // never be rebuilt from scratch (it owns the controller).
                      return IgnorePointer(
                        ignoring: t < 1,
                        child: Transform.translate(offset: Offset(0, (1 - t) * (collapsed + 40)), child: child),
                      );
                    },
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: sheet),
                    ),
                  ),
                ),
                Positioned(
                  top: padTop,
                  left: 0,
                  right: 0,
                  child: GarageTopBar(
                    title: widget.title,
                    onDark: true,
                    onBack: widget.onBack,
                    view: widget.view,
                    onToggleView: widget.onToggleView,
                    onAdd: widget.onAdd,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _crossFade(Widget child) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, fit: StackFit.passthrough, children: [...previous, ?current]),
        child: child,
      );
}

/// The floating bar over the bay: back, the title, Bay ⇄ Cards and add, as
/// white glass buttons ([onDark]), or plain ones on a light page.
class GarageTopBar extends StatelessWidget {
  const GarageTopBar({super.key, required this.title, required this.onDark, this.onBack, this.view = GarageView.bay, this.onToggleView, this.onAdd});
  final String title;
  final bool onDark;
  final VoidCallback? onBack;
  final GarageView view;
  final VoidCallback? onToggleView;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : AppColors.textPrimary;
    Widget button(IconData icon, String tooltip, VoidCallback onTap) => onDark
        ? PanelIconButton(icon: icon, tooltip: tooltip, onTap: onTap, size: 40)
        : IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon, color: fg));
    final cards = view == GarageView.cards;
    return SizedBox(
      height: kGarageBarHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: onDark ? 12 : 4),
        child: Row(
          children: [
            if (onBack != null) ...[
              button(AppIcons.arrowLeft, 'Back', onBack!),
              SizedBox(width: onDark ? 10 : 2),
            ] else
              SizedBox(width: onDark ? 6 : 16),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: 0.2,
                  color: fg,
                  shadows: onDark ? const [Shadow(color: Color(0x99000000), blurRadius: 8)] : null,
                ),
              ),
            ),
            if (onToggleView != null) ...[
              const SizedBox(width: 8),
              button(cards ? AppIcons.garage : AppIcons.cards, cards ? 'Bay view' : 'Cards view', onToggleView!),
            ],
            if (onAdd != null) ...[
              const SizedBox(width: 8),
              button(AppIcons.plus, 'Add a car', onAdd!),
            ],
          ],
        ),
      ),
    );
  }
}

/// While the cars load, or when there are none: the top bar on a plain
/// page over [child], pull to refresh.
class GaragePlainPage extends StatelessWidget {
  const GaragePlainPage({super.key, required this.title, required this.child, this.onBack, this.onAdd, this.onRefresh, this.bottomPadding = 0});
  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onAdd;
  final Future<void> Function()? onRefresh;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: [child],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlay,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top),
          GarageTopBar(title: title, onDark: false, onBack: onBack, onAdd: onAdd),
          Expanded(child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list)),
        ],
      ),
    );
  }
}

/// Reports its child's size after each layout that changes it (the panel
/// measures itself to know how far to collapse and open).
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    SchedulerBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}
