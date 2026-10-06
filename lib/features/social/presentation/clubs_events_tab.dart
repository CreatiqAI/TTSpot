import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/geo/latlng.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/tab_reselect.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_tab_bar.dart';
import '../../../core/widgets/thumb_image.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../events/domain/event.dart';
import '../../friends/application/friends_providers.dart';
import '../../map/application/map_list_providers.dart';
import '../../map/application/map_providers.dart' show userLocationProvider;
import '../application/community_providers.dart';
import '../domain/club.dart';
import 'widgets/club_name_tag.dart' show officialGold, officialGoldTint;
import 'widgets/club_requests.dart' show askClubJoinMessage;

/// What the Clubs & Events tab lists.
enum ClubsEventsFilter {
  all('All'),
  official('Official clubs'),
  underground('Underground clubs'),
  events('Events');

  const ClubsEventsFilter(this.label);
  final String label;
}

/// All: this many clubs, then "See all".
const kClubsPreview = 5;

/// Home's second tab: car clubs and what's on, as one list. Chips pick All ·
/// Official clubs · Underground clubs · Events; a search box narrows it.
///
/// Clubs: official first (then the biggest), each with Join (public, one
/// tap), Request (private) or Joined. Events: everything under way or still
/// to come, live first, then day by day; inside a day the nearest first
/// when we know where the member is. Same data as the map's list view.
class ClubsEventsTab extends ConsumerStatefulWidget {
  const ClubsEventsTab({super.key, this.tabIndex = 1});

  /// Its place in Home's tabs: a Home re-tap scrolls this list only while it shows.
  final int tabIndex;

  @override
  ConsumerState<ClubsEventsTab> createState() => _ClubsEventsTabState();
}

class _ClubsEventsTabState extends ConsumerState<ClubsEventsTab> with AutomaticKeepAliveClientMixin {
  ClubsEventsFilter _filter = ClubsEventsFilter.all;
  bool _allClubs = false;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _refresh = GlobalKey<RefreshIndicatorState>();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    ref.invalidate(allClubsProvider);
    ref.invalidate(allUpcomingMeetsProvider);
    ref.invalidate(myClubsProvider);
    try {
      await Future.wait([ref.read(allClubsProvider.future), ref.read(allUpcomingMeetsProvider.future)]);
    } catch (_) {} // the list shows the error
  }

  /// Home tapped again while this tab shows: top of the list, fresh data.
  Future<void> _backToTop() async {
    final tabs = DefaultTabController.maybeOf(context);
    if (tabs != null && tabs.index != widget.tabIndex) return;
    if (_scroll.hasClients) await _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    if (mounted) _refresh.currentState?.show();
  }

  void _pick(ClubsEventsFilter f) => setState(() {
    _filter = f;
    _allClubs = false;
  });

  void _clearSearch() {
    _search.clear();
    FocusScope.of(context).unfocus();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen(homeReselectProvider, (_, _) => _backToTop());
    final clubs = ref.watch(allClubsProvider);
    final meets = ref.watch(allUpcomingMeetsProvider);
    final hosts = ref.watch(meetHostNamesProvider).value ?? const <String, String>{};
    final mine = {for (final c in ref.watch(myClubsProvider).value ?? const <Club>[]) c.id};
    final origin = ref.watch(listOriginProvider);
    // Distances only when we really know where the member is (not the KL default).
    final located = ref.watch(userLocationProvider).value != null;

    final q = _query.trim().toLowerCase();
    bool clubMatches(Club c) => q.isEmpty || [c.name, c.handle, c.homeState ?? ''].any((s) => s.toLowerCase().contains(q));
    String hostOf(Event e) => e.clubName ?? e.vendorName ?? hosts[e.organizerId] ?? '';
    bool eventMatches(Event e) => q.isEmpty || [e.title, e.venueName, hostOf(e)].any((s) => s.toLowerCase().contains(q));

    final wantClubs = _filter != ClubsEventsFilter.events;
    final wantEvents = _filter == ClubsEventsFilter.all || _filter == ClubsEventsFilter.events;

    final slivers = <Widget>[];
    final waiting = (wantClubs && clubs.isLoading && !clubs.hasValue) || (wantEvents && meets.isLoading && !meets.hasValue);
    final failure = (wantClubs && clubs.hasError && !clubs.hasValue) ? clubs.error : ((wantEvents && meets.hasError && !meets.hasValue) ? meets.error : null);

    if (waiting) {
      slivers.add(const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    } else if (failure != null) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: EmptyState(icon: AppIcons.wifiSlash, title: 'Couldn\'t load clubs and events', subtitle: friendlyError(failure), actionLabel: 'Retry', onAction: _reload),
          ),
        ),
      );
    } else {
      final allClubs = clubs.value ?? const <Club>[];
      final allMeets = meets.value ?? const <Event>[];
      final shownClubs = wantClubs ? sortClubsForList(allClubs.where((c) => _keepClub(c) && clubMatches(c))) : const <Club>[];
      final shownEvents = wantEvents ? sortEventsForList(allMeets.where(eventMatches), origin: located ? origin : null) : const <Event>[];

      if (shownClubs.isEmpty && shownEvents.isEmpty) {
        slivers.add(SliverFillRemaining(hasScrollBody: false, child: Center(child: _empty(allClubs, allMeets))));
      } else {
        final rows = <Widget>[];
        if (shownClubs.isNotEmpty) {
          final cap = _filter == ClubsEventsFilter.all && !_allClubs && q.isEmpty ? kClubsPreview : shownClubs.length;
          if (_filter == ClubsEventsFilter.all) rows.add(_Section('CLUBS · ${shownClubs.length}'));
          for (final c in shownClubs.take(cap)) {
            rows.add(ClubListRow(club: c, isMember: mine.contains(c.id)));
          }
          if (cap < shownClubs.length) {
            rows.add(_SeeAll(label: 'See all ${shownClubs.length} clubs', onTap: () => setState(() => _allClubs = true)));
          }
        }
        if (wantEvents) {
          if (_filter == ClubsEventsFilter.all) {
            rows.add(_Section(shownEvents.isEmpty ? 'EVENTS' : 'EVENTS · ${shownEvents.length}'));
            if (shownEvents.isEmpty) rows.add(_NoEventsLine(onPlan: () => context.push(Routes.createEvent)));
          }
          String? last;
          for (final e in shownEvents) {
            // Events alone: LIVE NOW / TODAY / THIS WEEK / LATER headings.
            if (_filter == ClubsEventsFilter.events) {
              final g = eventGroupOf(e);
              if (g != last) rows.add(_Section(g));
              last = g;
            }
            rows.add(EventListRow(event: e, host: hostOf(e), km: located ? distanceKm(origin, e.latLng) : null));
          }
        }
        slivers.add(SliverList.list(children: rows));
      }
    }

    return RefreshIndicator(
      key: _refresh,
      onRefresh: _reload,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              // Wrap, not Row: never an overflow with very large text.
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final f in ClubsEventsFilter.values) _FilterChip(key: Key('clubs-filter-${f.name}'), label: f.label, selected: _filter == f, onTap: () => _pick(f))],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: _SearchBox(controller: _search, onChanged: (v) => setState(() => _query = v), onClear: _clearSearch),
            ),
          ),
          ...slivers,
          // Clear of the floating tab bar.
          SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.clearance(context))),
        ],
      ),
    );
  }

  bool _keepClub(Club c) => switch (_filter) {
    ClubsEventsFilter.official => c.isOfficial,
    ClubsEventsFilter.underground => !c.isOfficial,
    _ => true,
  };

  Widget _empty(List<Club> allClubs, List<Event> allMeets) {
    if (_query.trim().isNotEmpty) {
      return EmptyState(titi: TitiPose.binoculars, title: 'Nothing matches "${_query.trim()}"', subtitle: 'Try a club name, a place or a meet.', actionLabel: 'Clear search', onAction: _clearSearch);
    }
    return switch (_filter) {
      ClubsEventsFilter.official => EmptyState(
        titi: TitiPose.trophy,
        title: 'No official clubs yet',
        subtitle: 'Official clubs get meet notifications, a gold badge and no member limit.',
        actionLabel: allClubs.isEmpty ? null : 'See all clubs',
        onAction: allClubs.isEmpty ? null : () => _pick(ClubsEventsFilter.all),
      ),
      ClubsEventsFilter.underground => EmptyState(
        titi: TitiPose.flag,
        title: 'No underground clubs yet',
        subtitle: 'Start one and bring your crew.',
        actionLabel: 'Start a car club',
        onAction: () => context.push(Routes.clubApply),
      ),
      ClubsEventsFilter.events => EmptyState(
        titi: TitiPose.calendar,
        title: 'No meets coming up',
        subtitle: 'Plan one and your friends will come.',
        actionLabel: 'Plan a meet',
        onAction: () => context.push(Routes.createEvent),
      ),
      ClubsEventsFilter.all => EmptyState(
        art: AppArt.flag,
        title: 'No clubs or meets yet',
        subtitle: 'Start a car club or plan a meet, and it shows up here.',
        actionLabel: 'Plan a meet',
        onAction: () => context.push(Routes.createEvent),
      ),
    };
  }
}

// ------------------------------------------------------------- ordering ---

/// Official clubs first, then the biggest, then by name.
List<Club> sortClubsForList(Iterable<Club> clubs) {
  final list = clubs.toList()
    ..sort((a, b) {
      if (a.isOfficial != b.isOfficial) return a.isOfficial ? -1 : 1;
      final m = b.memberCount.compareTo(a.memberCount);
      return m != 0 ? m : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return list;
}

/// Under way right now (started, not over yet).
bool eventIsOn(Event e, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return !e.startsAt.isAfter(n) && e.closesAt.isAfter(n);
}

/// Live first; then day by day; inside a day the nearest first when
/// [origin] (the member) is known, else the soonest.
List<Event> sortEventsForList(Iterable<Event> events, {LatLng? origin, DateTime? now}) {
  final n = now ?? DateTime.now();
  final list = events.where((e) => !e.isCancelled && e.closesAt.isAfter(n)).toList();
  DateTime day(Event e) => DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
  list.sort((a, b) {
    final la = eventIsOn(a, n), lb = eventIsOn(b, n);
    if (la != lb) return la ? -1 : 1;
    if (!la) {
      final d = day(a).compareTo(day(b));
      if (d != 0) return d;
    }
    if (origin != null) {
      final k = distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng));
      if (k != 0) return k;
    }
    return a.startsAt.compareTo(b.startsAt);
  });
  return list;
}

/// The heading an event sits under on the Events filter.
String eventGroupOf(Event e, [DateTime? now]) {
  final n = now ?? DateTime.now();
  if (eventIsOn(e, n)) return 'LIVE NOW';
  final today = DateTime(n.year, n.month, n.day);
  if (e.startsAt.isBefore(today.add(const Duration(days: 1)))) return 'TODAY';
  if (e.startsAt.isBefore(today.add(const Duration(days: 7)))) return 'THIS WEEK';
  return 'LATER';
}

// ----------------------------------------------------------------- clubs ---

/// Crest, name with the Official badge, "state · N members", and Join /
/// Request / Joined on the right. Tap: the club page.
class ClubListRow extends StatelessWidget {
  const ClubListRow({super.key, required this.club, required this.isMember});
  final Club club;
  final bool isMember;

  @override
  Widget build(BuildContext context) {
    final c = club;
    final state = c.homeState?.trim() ?? '';
    final n = c.memberCount;
    final meta = [state.isNotEmpty ? state : '@${c.handle}', '$n member${n == 1 ? '' : 's'}'].join(' · ');
    return InkWell(
      key: Key('club-row-${c.id}'),
      onTap: () => context.push(Routes.club(c.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            UserAvatar(url: c.avatarUrl, name: c.name, size: 52, borderColor: c.isOfficial ? officialGold() : null, fallbackAsset: crestAsset(c.id)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ),
                      if (c.isOfficial) ...[const SizedBox(width: 6), const OfficialBadge()],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ClubJoinPill(club: c, isMember: isMember),
          ],
        ),
      ),
    );
  }
}

/// Join (public: in at once), Request (private: ask, the officers decide),
/// Requested, or Joined (opens the club).
class ClubJoinPill extends ConsumerStatefulWidget {
  const ClubJoinPill({super.key, required this.club, required this.isMember});
  final Club club;
  final bool isMember;

  @override
  ConsumerState<ClubJoinPill> createState() => _ClubJoinPillState();
}

class _ClubJoinPillState extends ConsumerState<ClubJoinPill> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(communityActionsProvider).joinClub(widget.club.id);
    ref.invalidate(friendPinsProvider); // clubmates on the map
    messenger.showSnackBar(SnackBar(content: Text("You're in. Welcome to ${widget.club.name}.")));
  });

  Future<void> _request() async {
    final message = await askClubJoinMessage(context, widget.club.name);
    if (message == null || !mounted) return;
    await _run(() async {
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(communityActionsProvider).requestClubJoin(widget.club.id, message);
      messenger.showSnackBar(const SnackBar(content: Text('Request sent. You\'ll hear back in Activity.')));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.club;
    void open() => context.push(Routes.club(c.id));
    if (widget.isMember) return _Pill(key: Key('club-joined-${c.id}'), label: 'Joined', icon: AppIcons.check, onTap: open);
    if (c.isPublic) return _Pill(key: Key('club-join-${c.id}'), label: 'Join', filled: true, busy: _busy, onTap: _busy ? null : _join);
    final status = ref.watch(myClubRequestProvider(c.id)).value;
    if (status == 'pending') return _Pill(key: Key('club-requested-${c.id}'), label: 'Requested', icon: AppIcons.clock, onTap: open);
    return _Pill(key: Key('club-request-${c.id}'), label: 'Request', icon: AppIcons.lock, filled: true, busy: _busy, onTap: _busy ? null : _request);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.onTap, this.icon, this.filled = false, this.busy = false});
  final String label;
  final IconData? icon;
  final bool filled;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.textPrimary;
    return Semantics(
      button: true,
      child: Material(
        color: filled ? AppColors.brand : AppColors.surfaceGray,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                  else ...[
                    if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- events ---

/// Cover, title, when (Live now in red) and how far, where and how many
/// are going, and the host with its badge (official club / partner /
/// organizer, like the map's pins). Tap: the event page.
class EventListRow extends StatelessWidget {
  const EventListRow({super.key, required this.event, required this.host, this.km});
  final Event event;
  final String host;

  /// Null when we don't know where the member is.
  final double? km;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final small = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    final badge = HostBadge.of(e);
    return InkWell(
      key: Key('event-row-${e.id}'),
      onTap: () => context.push(Routes.event(e.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 64,
                height: 64,
                child: e.bundledCover != null
                    ? Image.asset(e.bundledCover!, fit: BoxFit.cover, cacheWidth: 192)
                    : ThumbImage(
                        e.coverUrl!,
                        placeholder: ColoredBox(
                          color: AppColors.surfaceGray,
                          child: Center(child: ArtIcon(e.type.art, size: 36)),
                        ),
                        error: Image.asset(e.defaultCover, fit: BoxFit.cover, cacheWidth: 192),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (eventIsOn(e))
                          const TextSpan(
                            text: 'Live now',
                            style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700),
                          )
                        else
                          TextSpan(text: formatEventDateFriendly(e.startsAt)),
                        if (km != null) TextSpan(text: ' · ${formatDistance(km!)}'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                  const SizedBox(height: 1),
                  // A long venue gives way; how many are going always shows.
                  Row(
                    children: [
                      Flexible(
                        child: Text(e.venueName, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                      ),
                      Text(' · ${e.attendeeCount} going', maxLines: 1, style: small),
                    ],
                  ),
                  if (host.isNotEmpty || badge != null) ...[
                    const SizedBox(height: 3),
                    // A long host name gives way; the badge always shows.
                    Row(
                      children: [
                        if (host.isNotEmpty)
                          Flexible(
                            child: Text(
                              host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: small.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                          ),
                        if (badge != null) ...[if (host.isNotEmpty) const SizedBox(width: 6), badge],
                      ],
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

/// The host's badge on an event row, the map's way: gold OFFICIAL for an
/// official club's meet (or an official event), gold ORGANIZER for an
/// approved organizer, ink PARTNER for a partner shop's event.
class HostBadge extends StatelessWidget {
  const HostBadge._({required this.text, required this.icon, required this.gold});
  final String text;
  final IconData icon;
  final bool gold;

  /// Null for a member's own meet.
  static HostBadge? of(Event e) {
    if (e.isOfficialClubEvent || e.type == EventType.official) return const HostBadge._(text: 'OFFICIAL', icon: AppIcons.sealCheck, gold: true);
    if (e.vendorId != null) return const HostBadge._(text: 'PARTNER', icon: AppIcons.storefront, gold: false);
    if (e.hostIsOrganizer) return const HostBadge._(text: 'ORGANIZER', icon: AppIcons.megaphone, gold: true);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final fg = gold ? officialGold() : AppColors.bg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: gold ? officialGoldTint() : AppColors.textPrimary, borderRadius: BorderRadius.circular(5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            text,
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Gold "OFFICIAL" beside an official club's name.
class OfficialBadge extends StatelessWidget {
  const OfficialBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final gold = officialGold();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: officialGoldTint(), borderRadius: BorderRadius.circular(5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.sealCheck, size: 11, color: gold),
          const SizedBox(width: 3),
          Text(
            'OFFICIAL',
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: gold),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- pieces ---

class _FilterChip extends StatelessWidget {
  const _FilterChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: selected ? AppColors.textPrimary : AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
        child: Text(
          label,
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: selected ? AppColors.bg : AppColors.textPrimary),
        ),
      ),
    ),
  );
}

/// Narrows the list by club name, place or meet. Local: no extra queries.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged, required this.onClear});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('clubs-search'),
    controller: controller,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    style: TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
    decoration: InputDecoration(
      isDense: true,
      hintText: 'Search clubs and meets',
      prefixIcon: Icon(AppIcons.magnifyingGlass, size: 18, color: AppColors.textSecondary),
      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 38),
      suffixIcon: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, v, _) => v.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Clear',
                icon: Icon(AppIcons.xCircle, size: 18, color: AppColors.textSecondary),
                onPressed: onClear,
              ),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      filled: true,
      fillColor: AppColors.surfaceGray,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary),
    ),
  );
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const Key('clubs-see-all'),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brand),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(AppIcons.caretRight, size: 14, color: AppColors.brand),
        ],
      ),
    ),
  );
}

/// All, with clubs but no meets: one line instead of a big empty state.
class _NoEventsLine extends StatelessWidget {
  const _NoEventsLine({required this.onPlan});
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text('No meets coming up.', style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
        GestureDetector(
          onTap: onPlan,
          child: const Text(
            'Plan one',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.brand),
          ),
        ),
      ],
    ),
  );
}
