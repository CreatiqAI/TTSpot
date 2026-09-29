import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/geo/latlng.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart' show PressScale;
import '../../../core/widgets/glass_tab_bar.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../events/domain/event.dart';
import '../../social/domain/club.dart';
import '../application/map_list_providers.dart';
import '../application/map_providers.dart';
import 'widgets/map_glyphs.dart' show SpotKind, paintSpotSilhouette, spotKindColor, spotKindOf;

/// The Map tab as a list: every upcoming meet, every club and every spot, in
/// three tabs. It lies over the map while [mapListViewProvider] is true; the
/// map stays live underneath, so it comes back exactly where it was. "Map"
/// at the top and "Show on map" at the bottom flip back; a spot flies the map
/// to it.
///
/// [standalone] = its own page (the /clubs route): a back arrow, and the map
/// buttons go to the Map tab.
class MapListView extends ConsumerStatefulWidget {
  const MapListView({super.key, this.initialTab, this.standalone = false});

  /// Null = follow the map's layer: Spots opens Spots, the rest open Meets.
  final MapListTab? initialTab;
  final bool standalone;

  @override
  ConsumerState<MapListView> createState() => _MapListViewState();
}

class _MapListViewState extends ConsumerState<MapListView> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab ?? (ref.read(mapModeProvider) == MapMode.spots ? MapListTab.spots : MapListTab.meets);
    _tabs = TabController(length: MapListTab.values.length, vsync: this, initialIndex: tab.index);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Back to the map (the Map tab, when this is its own page).
  void _showMap() {
    ref.read(mapListViewProvider.notifier).set(false);
    if (widget.standalone) context.go(Routes.map);
  }

  /// Fly the map to a spot. Focus first, so the Spots layer skips its
  /// "nearest spots" view (same order as "Show on map" on a spot's page).
  void _showSpot(Place p) {
    ref.read(mapFocusProvider.notifier).request(p.latLng);
    ref.read(mapModeProvider.notifier).set(MapMode.spots);
    _showMap();
  }

  @override
  Widget build(BuildContext context) {
    // Inside the shell the glass tab bar floats over the bottom; on its own
    // page there is none, only the home indicator.
    final pillBottom = widget.standalone ? MediaQuery.paddingOf(context).bottom + 12 : GlassTabBar.clearance(context);
    final listBottom = pillBottom + _ShowOnMapPill.height + 16;

    final page = Material(
      color: AppColors.bg,
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _Header(standalone: widget.standalone, onMap: _showMap),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: _Segmented(controller: _tabs),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _MeetsTab(bottom: listBottom),
                      _ClubsTab(bottom: listBottom),
                      _SpotsTab(bottom: listBottom, onShow: _showSpot),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: pillBottom,
            child: Center(child: _ShowOnMapPill(onTap: _showMap)),
          ),
        ],
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlay,
      // On the Map tab, the back gesture goes back to the map.
      child: widget.standalone
          ? page
          : PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _showMap();
              },
              child: page,
            ),
    );
  }
}

// ------------------------------------------------------------------- meets ---

enum _When { any, week, weekend }

class _MeetsTab extends ConsumerStatefulWidget {
  const _MeetsTab({required this.bottom});
  final double bottom;

  @override
  ConsumerState<_MeetsTab> createState() => _MeetsTabState();
}

// Kept alive so its filters survive a swipe to another tab and back.
class _MeetsTabState extends ConsumerState<_MeetsTab> with AutomaticKeepAliveClientMixin {
  _When _when = _When.any;
  bool _near = false;
  bool _official = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    ref.invalidate(allUpcomingMeetsProvider);
    try {
      await ref.read(allUpcomingMeetsProvider.future);
    } catch (_) {} // the tab shows the error
  }

  void _clear() => setState(() {
        _when = _When.any;
        _near = false;
        _official = false;
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final meets = ref.watch(allUpcomingMeetsProvider);
    final hosts = ref.watch(meetHostNamesProvider).value ?? const <String, String>{};
    final origin = ref.watch(listOriginProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));
    // This weekend: Saturday 00:00 (yesterday on a Sunday) to Monday 00:00.
    final sat = now.weekday == DateTime.sunday ? today.subtract(const Duration(days: 1)) : today.add(Duration(days: DateTime.saturday - now.weekday));
    final monday = sat.add(const Duration(days: 2));

    bool keep(Event e) {
      if (_when == _When.week && !e.startsAt.isBefore(weekEnd)) return false;
      if (_when == _When.weekend && !(e.startsAt.isBefore(monday) && e.closesAt.isAfter(sat))) return false;
      if (_near && distanceKm(origin, e.latLng) > kNearMeKm) return false;
      if (_official && !_isOfficial(e)) return false;
      return true;
    }

    return Column(
      children: [
        _ChipRow(
          children: [
            _Chip(label: 'This week', selected: _when == _When.week, onTap: () => setState(() => _when = _when == _When.week ? _When.any : _When.week)),
            _Chip(label: 'Weekend', selected: _when == _When.weekend, onTap: () => setState(() => _when = _when == _When.weekend ? _When.any : _When.weekend)),
            _Chip(label: 'Near me', icon: AppIcons.navigationArrow, selected: _near, onTap: () => setState(() => _near = !_near)),
            _Chip(label: 'Official', icon: AppIcons.sealCheck, selected: _official, onTap: () => setState(() => _official = !_official)),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: meets.when(
              loading: () => const _Loading(),
              error: (e, _) => _Fill(
                bottom: widget.bottom,
                child: EmptyState(icon: AppIcons.wifiSlash, title: 'Couldn\'t load meets', subtitle: friendlyError(e), actionLabel: 'Retry', onAction: _refresh),
              ),
              data: (all) {
                final list = all.where(keep).toList();
                if (list.isEmpty) {
                  return _Fill(
                    bottom: widget.bottom,
                    child: all.isEmpty
                        ? EmptyState(
                            titi: TitiPose.calendar,
                            title: 'No meets coming up',
                            subtitle: 'Plan one and your friends will come.',
                            actionLabel: 'Plan a meet',
                            onAction: () => context.push(Routes.createEvent),
                          )
                        : EmptyState(
                            titi: TitiPose.binoculars,
                            title: 'Nothing matches',
                            subtitle: _near ? 'No meets within ${kNearMeKm.round()} km right now.' : 'Try another filter.',
                            actionLabel: 'Clear filters',
                            onAction: _clear,
                          ),
                  );
                }
                // TODAY / THIS WEEK / LATER, soonest first inside each.
                final groups = <String, List<Event>>{'TODAY': [], 'THIS WEEK': [], 'LATER': []};
                final tomorrow = today.add(const Duration(days: 1));
                for (final e in list) {
                  groups[e.startsAt.isBefore(tomorrow) ? 'TODAY' : (e.startsAt.isBefore(weekEnd) ? 'THIS WEEK' : 'LATER')]!.add(e);
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: widget.bottom),
                  children: [
                    for (final g in groups.entries)
                      if (g.value.isNotEmpty) ...[
                        _Section(g.key),
                        for (final e in g.value)
                          _MeetRow(
                            event: e,
                            host: e.clubName ?? e.vendorName ?? hosts[e.organizerId] ?? '',
                            km: distanceKm(origin, e.latLng),
                            onTap: () => context.push(Routes.event(e.id)),
                          ),
                      ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Hosted by an official club, or an official event.
bool _isOfficial(Event e) => e.isOfficialClubEvent || e.type == EventType.official;

/// Date block, then title, "time · place · km" and "host · N going".
class _MeetRow extends StatelessWidget {
  const _MeetRow({required this.event, required this.host, required this.km, required this.onTap});
  final Event event;
  final String host;
  final double km;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final started = !e.startsAt.isAfter(DateTime.now());
    final official = _isOfficial(e);
    final small = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _DateBlock(at: e.startsAt),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  // A long venue name gives way; the distance always shows.
                  Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (started)
                                const TextSpan(text: 'Live now', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700))
                              else
                                TextSpan(text: formatTime(e.startsAt)),
                              TextSpan(text: ' · ${e.venueName}'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ),
                      Text(' · ${formatDistance(km)}', style: small),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (host.isNotEmpty) Flexible(child: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: small)),
                      if (official) ...[if (host.isNotEmpty) const SizedBox(width: 6), const _OfficialChip()],
                      Text('${host.isEmpty && !official ? '' : ' · '}${e.attendeeCount} going', style: small),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "WED" over "30"; the weekday goes red today.
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.at});
  final DateTime at;

  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = at.year == now.year && at.month == now.month && at.day == now.day;
    return Container(
      width: 50,
      height: 56,
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_days[at.weekday - 1], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: today ? AppColors.brand : AppColors.textSecondary)),
          Text('${at.day}', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.15, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- clubs ---

class _ClubsTab extends ConsumerStatefulWidget {
  const _ClubsTab({required this.bottom});
  final double bottom;

  @override
  ConsumerState<_ClubsTab> createState() => _ClubsTabState();
}

class _ClubsTabState extends ConsumerState<_ClubsTab> with AutomaticKeepAliveClientMixin {
  bool _near = false;
  bool _official = false;
  bool _active = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    ref.invalidate(allClubsProvider);
    ref.invalidate(clubActivityProvider);
    ref.invalidate(allUpcomingMeetsProvider);
    try {
      await ref.read(allClubsProvider.future);
    } catch (_) {} // the tab shows the error
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final clubs = ref.watch(allClubsProvider);
    final meets = ref.watch(allUpcomingMeetsProvider).value ?? const <Event>[];
    final activity = ref.watch(clubActivityProvider).value ?? const <String, int>{};
    final origin = ref.watch(listOriginProvider);

    // Each club's next meet: the meets come soonest first, so the first wins.
    final next = <String, Event>{};
    for (final e in meets) {
      if (e.clubId != null) next.putIfAbsent(e.clubId!, () => e);
    }
    // Where a club is: its garage, else where it meets next. Null = unknown.
    double? kmTo(Club c) {
      final at = c.garageLat != null && c.garageLng != null ? LatLng(c.garageLat!, c.garageLng!) : next[c.id]?.latLng;
      return at == null ? null : distanceKm(origin, at);
    }

    int byDefault(Club a, Club b) {
      if (a.isOfficial != b.isOfficial) return a.isOfficial ? -1 : 1;
      final m = b.memberCount.compareTo(a.memberCount);
      return m != 0 ? m : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    int byActivity(Club a, Club b) {
      final n = (activity[b.id] ?? 0).compareTo(activity[a.id] ?? 0);
      return n != 0 ? n : byDefault(a, b);
    }

    int byDistance(Club a, Club b) => (kmTo(a) ?? double.infinity).compareTo(kmTo(b) ?? double.infinity);

    return Column(
      children: [
        _ChipRow(
          children: [
            _Chip(label: 'Near me', icon: AppIcons.navigationArrow, selected: _near, onTap: () => setState(() => _near = !_near)),
            _Chip(label: 'Official', icon: AppIcons.sealCheck, selected: _official, onTap: () => setState(() => _official = !_official)),
            _Chip(label: 'Most active', icon: AppIcons.fire, selected: _active, onTap: () => setState(() => _active = !_active)),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: clubs.when(
              loading: () => const _Loading(),
              error: (e, _) => _Fill(
                bottom: widget.bottom,
                child: EmptyState(icon: AppIcons.wifiSlash, title: 'Couldn\'t load clubs', subtitle: friendlyError(e), actionLabel: 'Retry', onAction: _refresh),
              ),
              data: (all) {
                final list = all.where((c) => (!_official || c.isOfficial) && (!_near || (kmTo(c) ?? double.infinity) <= kNearMeKm)).toList()
                  ..sort(_active ? byActivity : (_near ? byDistance : byDefault));
                if (list.isEmpty) {
                  return _Fill(
                    bottom: widget.bottom,
                    child: all.isEmpty
                        ? EmptyState(
                            titi: TitiPose.flag,
                            title: 'No clubs yet',
                            subtitle: 'Start one and bring your crew.',
                            actionLabel: 'Start a car club',
                            onAction: () => context.push(Routes.clubApply),
                          )
                        : EmptyState(
                            titi: TitiPose.binoculars,
                            title: _near ? 'No clubs near you yet' : 'Nothing matches',
                            subtitle: _near ? 'Clubs show here once they set a garage or plan a meet within ${kNearMeKm.round()} km.' : 'Try another filter.',
                            actionLabel: 'Clear filters',
                            onAction: () => setState(() {
                              _near = false;
                              _official = false;
                              _active = false;
                            }),
                          ),
                  );
                }
                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(top: 4, bottom: widget.bottom),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ClubRow(
                    club: list[i],
                    km: kmTo(list[i]),
                    next: next[list[i].id],
                    onTap: () => context.push(Routes.club(list[i].id)),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Logo, name + OFFICIAL, "area · N members · km", and the next meet.
class _ClubRow extends StatelessWidget {
  const _ClubRow({required this.club, required this.km, required this.next, required this.onTap});
  final Club club;
  final double? km;
  final Event? next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = club;
    final state = c.homeState?.trim() ?? '';
    final garage = c.garageName?.trim() ?? '';
    final area = state.isNotEmpty ? state : (garage.isNotEmpty ? garage : '@${c.handle}');
    final n = c.memberCount;
    final meta = [area, '$n member${n == 1 ? '' : 's'}', if (km != null) formatDistance(km!)].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            UserAvatar(url: c.avatarUrl, name: c.name, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                      if (c.isOfficial) ...[const SizedBox(width: 6), const _OfficialChip()],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  if (next != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Next: ${_shortDay(next!.startsAt)}, ${next!.venueName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Today", "Tomorrow", else "Sat 4 Oct".
String _shortDay(DateTime t) {
  final now = DateTime.now();
  final days = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return formatDate(t).replaceFirst(',', '');
}

// ------------------------------------------------------------------- spots ---

class _SpotsTab extends ConsumerWidget {
  const _SpotsTab({required this.bottom, required this.onShow});
  final double bottom;
  final ValueChanged<Place> onShow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spots = ref.watch(allSpotsProvider);
    final origin = ref.watch(listOriginProvider);

    Future<void> refresh() async {
      ref.invalidate(allSpotsProvider);
      try {
        await ref.read(allSpotsProvider.future);
      } catch (_) {} // the tab shows the error
    }

    return Column(
      children: [
        // Same height as the other tabs' chips, so the lists line up.
        SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Nearest first. Tap one to see it on the map.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: spots.when(
              loading: () => const _Loading(),
              error: (e, _) => _Fill(
                bottom: bottom,
                child: EmptyState(icon: AppIcons.wifiSlash, title: 'Couldn\'t load spots', subtitle: friendlyError(e), actionLabel: 'Retry', onAction: refresh),
              ),
              data: (all) {
                if (all.isEmpty) {
                  return _Fill(
                    bottom: bottom,
                    child: EmptyState(
                      titi: TitiPose.mapPin,
                      title: 'No spots yet',
                      subtitle: 'Know a good place to meet? Suggest it.',
                      actionLabel: 'Suggest a spot',
                      onAction: () => context.push(Routes.suggestSpot),
                    ),
                  );
                }
                final list = [...all]..sort((a, b) => distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng)));
                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(top: 4, bottom: bottom),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _SpotRow(
                    place: list[i],
                    km: distanceKm(origin, list[i].latLng),
                    onTap: () => onShow(list[i]),
                    onLongPress: () => context.push(Routes.place(list[i].id)),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Kind badge, name, "kind · km", and check-ins on the right. Hold to open
/// the spot's page.
class _SpotRow extends StatelessWidget {
  const _SpotRow({required this.place, required this.km, required this.onTap, required this.onLongPress});
  final Place place;
  final double km;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = place;
    final n = p.totalCheckins;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _KindBadge(kind: spotKindOf(p.kind)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('${p.kindLabel} · ${formatDistance(km)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$n', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(n == 1 ? 'check-in' : 'check-ins', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The spot's map badge, big: its kind's colour and silhouette.
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});
  final SpotKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: spotKindColor(kind),
        borderRadius: BorderRadius.circular(12),
        // The ink circuit badge would vanish into the night ground.
        border: AppColors.dark ? Border.all(color: Colors.white.withValues(alpha: 0.14)) : null,
      ),
      child: CustomPaint(painter: _SilhouettePainter(kind)),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter(this.kind);
  final SpotKind kind;

  @override
  void paint(Canvas canvas, Size size) => paintSpotSilhouette(canvas, kind, size.center(Offset.zero), size.shortestSide * 0.8);

  @override
  bool shouldRepaint(_SilhouettePainter old) => old.kind != kind;
}

// ------------------------------------------------------------------ pieces ---

/// "Around you", and the Map button that flips back.
class _Header extends StatelessWidget {
  const _Header({required this.standalone, required this.onMap});
  final bool standalone;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(standalone ? 4 : 16, 8, 16, 10),
      child: Row(
        children: [
          if (standalone)
            IconButton(
              icon: const Icon(AppIcons.arrowLeft),
              onPressed: () => context.canPop() ? context.pop() : context.go(Routes.map),
            ),
          Expanded(
            child: Text('Around you', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.textPrimary)),
          ),
          PressScale(
            child: Material(
              color: AppColors.surfaceGray,
              shape: const StadiumBorder(),
              child: InkWell(
                onTap: onMap,
                customBorder: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.mapTrifold, size: 18, color: AppColors.textPrimary),
                      const SizedBox(width: 6),
                      Text('Map', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Meets · Clubs · Spots. A raised thumb slides along with the swipe.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    const tabs = MapListTab.values;
    final thumb = AppColors.dark ? AppColors.border : AppColors.surface;
    final animation = controller.animation!;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / tabs.length;
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = animation.value;
              return Stack(
                children: [
                  Positioned(
                    left: t * w,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: thumb,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final tab in tabs)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: (t - tab.index).abs() < 0.5,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => controller.animateTo(tab.index),
                              child: Center(
                                child: Text(
                                  tab.label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: (t - tab.index).abs() < 0.5 ? FontWeight.w700 : FontWeight.w600,
                                    color: (t - tab.index).abs() < 0.5 ? AppColors.textPrimary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// A row of filter chips that scrolls sideways when it runs out of room.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/// Same pill as the Home feed's For you / Following switch.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.bg : AppColors.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
            Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Gold "OFFICIAL" tag for official clubs and their meets.
class _OfficialChip extends StatelessWidget {
  const _OfficialChip();

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.dark ? const Color(0xFFE6B422) : const Color(0xFFB8860B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFD4A017).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.sealCheck, size: 11, color: gold),
          const SizedBox(width: 3),
          Text('OFFICIAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: gold)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

/// Black pill floating above the tab bar: back to the map.
class _ShowOnMapPill extends StatelessWidget {
  const _ShowOnMapPill({required this.onTap});
  final VoidCallback onTap;

  static const height = 46.0;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: AppColors.textPrimary,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.mapTrifold, size: 18, color: AppColors.onInk),
                    const SizedBox(width: 8),
                    Text('Show on map', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.onInk)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(strokeWidth: 2));
}

/// Centres an empty or error state in the room above the floating pill, and
/// still scrolls so pull-to-refresh works on it.
class _Fill extends StatelessWidget {
  const _Fill({required this.bottom, required this.child});
  final double bottom;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, c.maxHeight - bottom)),
            child: Center(child: child),
          ),
        ),
      );
}
