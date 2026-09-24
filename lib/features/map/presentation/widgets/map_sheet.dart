import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_art.dart';
import '../../../../core/places/places_service.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/geo.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../events/domain/event.dart';
import '../../../friends/application/friends_providers.dart';
import '../../../friends/domain/friend.dart';
import '../../../social/application/chat_providers.dart';
import '../../../social/domain/club.dart';
import '../../../social/domain/post.dart';
import '../../../social/presentation/story_viewer_screen.dart';
import '../../application/map_providers.dart';
import 'map_event_sheet.dart' show EventRow;
import 'car_marker.dart';
import '../../../friends/presentation/friend_colour_sheet.dart';
import 'map_filter_sheet.dart';

/// Draggable dark sheet over the map. Closed by default (the glass toolbar
/// stands in for it); a chip or a pull opens it. Content follows the map mode:
/// Now → friends, live meets, moments · Upcoming → meets · Spots → places to check in.
class MapSheet extends ConsumerWidget {
  const MapSheet({super.key, required this.controller, required this.onFocus});
  final DraggableScrollableController controller;
  final void Function(LatLng target) onFocus;

  static const closed = 0.0;
  static const half = 0.5;
  static const full = 0.92;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(mapModeProvider);
    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: closed,
      minChildSize: closed,
      maxChildSize: full,
      snap: true,
      snapSizes: const [half, full],
      builder: (context, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: MapPalette.of(context).surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: MapPalette.of(context).shadow, blurRadius: 24, offset: const Offset(0, -6))],
          ),
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              const SliverToBoxAdapter(child: _Handle()),
              switch (mode) {
                MapMode.now => _NowContent(onFocus: onFocus, expand: () => _expand(controller)),
                MapMode.upcoming => _UpcomingContent(expand: () => _expand(controller)),
                MapMode.spots => _SpotsContent(expand: () => _expand(controller), onFocus: onFocus),
              },
              // The glass tab bar floats over the sheet: leave room under the last row.
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 8)),
            ],
          ),
        );
      },
    );
  }

  static void _expand(DraggableScrollableController c) =>
      c.animateTo(full, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
}

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Center(
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: MapPalette.of(context).handle, borderRadius: BorderRadius.circular(2))),
        ),
      );
}

// ---------------------------------------------------------------------- now ---

class _NowContent extends ConsumerWidget {
  const _NowContent({required this.onFocus, required this.expand});
  final void Function(LatLng) onFocus;
  final VoidCallback expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(friendPinsProvider);
    final live = ref.watch(liveEventsProvider).value ?? const <Event>[];
    final moments = ref.watch(liveMomentsProvider).value ?? const <Story>[];
    final origin = ref.watch(mapOriginProvider);
    final friendCount = ref.watch(friendsProvider).value?.length ?? 0;
    final list = [...pins.value ?? const <FriendPin>[]]..sort((a, b) {
        if (a.isFresh != b.isFresh) return a.isFresh ? -1 : 1;
        return distanceKm(origin, a.latLng).compareTo(distanceKm(origin, b.latLng));
      });

    return SliverList(
      delegate: SliverChildListDelegate([
        _SectionHeader(
          title: 'On the map',
          count: list.length,
          action: 'Add friends',
          onAction: () => context.push(Routes.friends),
        ),
        if (pins.isLoading && list.isEmpty)
          const _Hint('Finding your friends…')
        else if (list.isEmpty)
          _Hint(friendCount == 0
              ? 'No friends yet. Add friends and see them here when they open the app.'
              : 'None of your $friendCount friend${friendCount == 1 ? '' : 's'} has opened the app in the last day. Ping them with TT now.')
        else
          for (final f in list) _FriendRow(pin: f, distanceKm: distanceKm(origin, f.latLng), onTap: () => onFocus(f.latLng)),
        if (live.isNotEmpty) ...[
          _SectionHeader(title: 'Happening now', count: live.length),
          for (final e in live)
            EventRow(event: e, distanceKm: distanceKm(origin, e.latLng), onTap: () => context.push(Routes.event(e.id)), live: true),
        ],
        if (moments.isNotEmpty) ...[
          _SectionHeader(title: 'Moments · last 24 h', count: moments.length),
          _MomentsStrip(moments: moments),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _FriendRow extends ConsumerWidget {
  const _FriendRow({required this.pin, required this.distanceKm, required this.onTap});
  final FriendPin pin;
  final double distanceKm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = pin;
    final name = f.user.displayName ?? f.user.username ?? '';
    final ago = timeAgo(f.updatedAt);
    var where = f.eventTitle != null
        ? 'At ${f.eventTitle}'
        : f.placeName != null
            ? (f.isFresh ? 'At ${f.placeName}' : 'Last seen at ${f.placeName}')
            : (f.isFresh ? 'On the move' : 'Last seen');
    if (f.viaClub && f.clubName != null) where = '$where · ${f.clubName}';
    return InkWell(
      onTap: onTap,
      onLongPress: () => context.push(Routes.profile(f.user.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                UserAvatar(url: f.user.avatarUrl, name: name, size: 46),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: f.isFresh ? AppColors.success : const Color(0xFF6B7280),
                      shape: BoxShape.circle,
                      border: Border.all(color: MapPalette.of(context).surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MapPalette.of(context).text, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('$where · $ago · ${formatDistance(distanceKm)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MapPalette.of(context).text2, fontSize: 13)),
                ],
              ),
            ),
            if (!f.isStranger)
              Tooltip(
                message: 'Colour on the map',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => showFriendColourSheet(context, ref, userId: f.user.id, name: name),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kTagColors[ref.watch(friendTagsProvider).value?[f.user.id]] ?? (f.viaClub ? kRelationClub : kRelationFriend),
                        border: Border.all(color: MapPalette.of(context).surface, width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Message',
              icon: Icon(AppIcons.chatCircle, color: MapPalette.of(context).text2, size: 20),
              onPressed: () async {
                try {
                  final conv = await ref.read(chatActionsProvider).openDm(f.user.id);
                  if (context.mounted) context.push(Routes.chat(conv));
                } catch (_) {}
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MomentsStrip extends StatelessWidget {
  const _MomentsStrip({required this.moments});
  final List<Story> moments;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: moments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final m = moments[i];
          return GestureDetector(
            onTap: () {
              final author = m.author;
              if (author == null) return;
              context.push(Routes.stories, extra: StoryViewerArgs(groups: [StoryGroup(author: author, stories: [m], allSeen: true)], initialGroup: 0));
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(image: CachedNetworkImageProvider(m.photoUrl), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: Colors.white10)),
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: Text(
                        m.whereLabel ?? m.author?.username ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6, color: Colors.black)]),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: UserAvatar(url: m.author?.avatarUrl, name: m.author?.username, size: 22, borderColor: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------- upcoming ---

class _UpcomingContent extends ConsumerWidget {
  const _UpcomingContent({required this.expand});
  final VoidCallback expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(visibleMapEventsProvider);
    final origin = ref.watch(mapOriginProvider);
    final filters = ref.watch(mapFiltersProvider);
    final hasSearch = ref.watch(mapSearchProvider).isNotEmpty;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(child: _SearchField(hint: 'Search meets or venues', onTap: expand)),
                const SizedBox(width: 8),
                _FilterChip(label: filters.label, active: !filters.isDefault, onTap: () => showMapFilterSheet(context)),
              ],
            ),
          ),
        ),
        events.when(
          loading: () => const SliverToBoxAdapter(child: _Hint('Loading meets…')),
          error: (e, _) => SliverToBoxAdapter(
            child: _Message(title: 'Couldn\'t load meets', subtitle: 'Check your connection.', actionLabel: 'Retry', onAction: () => ref.invalidate(mapEventsProvider)),
          ),
          data: (list) => list.isEmpty
              ? SliverToBoxAdapter(
                  child: hasSearch
                      ? const _Message(title: 'No matches', subtitle: 'Try a different name or venue.')
                      : _Message(title: 'No meets planned here yet', subtitle: 'Plan one and your friends will come.', actionLabel: 'Plan a meet', onAction: () => context.push(Routes.createEvent)),
                )
              : SliverPadding(
                  padding: const EdgeInsets.only(bottom: 24),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => Divider(height: 1, indent: 88, color: MapPalette.of(context).divider),
                    itemBuilder: (_, i) => EventRow(event: list[i], distanceKm: distanceKm(origin, list[i].latLng), onTap: () => context.push(Routes.event(list[i].id))),
                  ),
                ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- spots ---

class _SpotsContent extends ConsumerWidget {
  const _SpotsContent({required this.expand, required this.onFocus});
  final VoidCallback expand;
  final void Function(LatLng) onFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(visibleSpotsProvider);
    final origin = ref.watch(mapOriginProvider);
    final query = ref.watch(mapSearchProvider).trim();
    final searching = query.length >= 2;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _SearchField(hint: 'Search a spot, place or address', onTap: expand),
          ),
        ),
        if (searching) _GoogleSuggestions(query: query, origin: origin, onFocus: onFocus),
        if (!searching)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Text('SPOTS NEAR YOU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: MapPalette.of(context).text2)),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: () => context.push(Routes.suggestSpot),
                    icon: const Icon(AppIcons.mapPinPlus, size: 16),
                    label: const Text('Suggest a spot', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        places.when(
          loading: () => const SliverToBoxAdapter(child: _Hint('Finding spots…')),
          error: (e, _) => SliverToBoxAdapter(
            child: _Message(title: 'Couldn\'t load spots', subtitle: 'Check your connection.', actionLabel: 'Retry', onAction: () => ref.invalidate(spotsProvider)),
          ),
          data: (list) => list.isEmpty
              ? SliverToBoxAdapter(
                  child: searching
                      ? const _Hint('No check-in spots match. Pick a place above to jump there.')
                      : const _Message(title: 'No spots around here yet', subtitle: 'Check in or post a moment at a place, or suggest one above.'),
                )
              : SliverPadding(
                  padding: const EdgeInsets.only(bottom: 24),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => Divider(height: 1, indent: 92, color: MapPalette.of(context).divider),
                    itemBuilder: (_, i) => SpotRow(
                      place: list[i],
                      distanceKm: distanceKm(origin, list[i].latLng),
                      dark: !MapPalette.of(context).light,
                      onTap: () => context.push(Routes.place(list[i].id)),
                      onLongPress: () => onFocus(list[i].latLng),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Google Places matches for what's typed. Tap one: the map jumps there.
class _GoogleSuggestions extends ConsumerWidget {
  const _GoogleSuggestions({required this.query, required this.origin, required this.onFocus});
  final String query;
  final LatLng origin;
  final void Function(LatLng) onFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(placeSuggestionsProvider(PlaceQuery(query, lat: origin.latitude, lng: origin.longitude)));
    final list = items.value ?? const <PlaceSuggestion>[];
    if (list.isEmpty) {
      return SliverToBoxAdapter(child: items.isLoading ? const _Hint('Searching places…') : const SizedBox.shrink());
    }
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 8),
      sliver: SliverList.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final s = list[i];
          return ListTile(
            dense: true,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: MapPalette.of(context).tile, borderRadius: BorderRadius.circular(10)),
              child: Icon(AppIcons.mapPin, size: 18, color: MapPalette.of(context).text),
            ),
            title: Text(s.main, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MapPalette.of(context).text, fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(s.secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MapPalette.of(context).text2, fontSize: 12)),
            trailing: Icon(AppIcons.navigationArrow, size: 16, color: MapPalette.of(context).text2),
            onTap: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              try {
                final d = await ref.read(placesServiceProvider).details(s.placeId);
                onFocus(LatLng(d.lat, d.lng));
              } catch (_) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open that place.')));
              }
            },
          );
        },
      ),
    );
  }
}

/// One spot in a list: cover (or kind art), name, tags, check-ins, distance.
/// Used on the dark map sheet and the light feed tab.
class SpotRow extends StatelessWidget {
  const SpotRow({super.key, required this.place, required this.distanceKm, required this.onTap, this.onLongPress, this.dark = false});
  final Place place;
  final double distanceKm;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = place;
    final fg = dark ? MapPalette.of(context).text : AppColors.textPrimary;
    final fg2 = dark ? MapPalette.of(context).text2 : AppColors.textSecondary;
    final tile = dark ? MapPalette.of(context).tile : AppColors.surfaceGray;
    final tags = p.tags.take(3).join(' · ');
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (p.coverUrl != null)
                      Image(image: CachedNetworkImageProvider(p.coverUrl!),
                        fit: BoxFit.cover,
                        frameBuilder: (_, child, frame, sync) => frame == null && !sync ? ColoredBox(color: tile, child: Center(child: ArtIcon(p.kindArt, size: 30))) : child,
                        errorBuilder: (_, _, _) => ColoredBox(color: tile, child: Center(child: ArtIcon(p.kindArt, size: 30))),
                      )
                    else
                      ColoredBox(color: tile, child: Center(child: ArtIcon(p.kindArt, size: 34))),
                    if (p.recommended)
                      Positioned(
                        left: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(6)),
                          child: const Text('★', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    tags.isEmpty ? p.kindLabel : tags,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg2, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.totalCheckins} check-in${p.totalCheckins == 1 ? '' : 's'}${p.pastMeets > 0 ? ' · ${p.pastMeets} meet${p.pastMeets == 1 ? '' : 's'}' : ''} · ${formatDistance(distanceKm)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg2, fontSize: 13),
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

// ------------------------------------------------------------------ pieces ---

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count, this.action, this.onAction});
  final String title;
  final int? count;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 2),
      child: Row(
        children: [
          Text(title, style: TextStyle(color: MapPalette.of(context).text, fontSize: 15, fontWeight: FontWeight.w700)),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(color: MapPalette.of(context).text2, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
          const Spacer(),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Text(text, style: TextStyle(color: MapPalette.of(context).text2, fontSize: 14, height: 1.4)),
      );
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField({required this.hint, required this.onTap});
  final String hint;
  final VoidCallback onTap;

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _ctrl,
        onTap: widget.onTap,
        onChanged: (v) => ref.read(mapSearchProvider.notifier).set(v),
        textInputAction: TextInputAction.search,
        style: TextStyle(color: MapPalette.of(context).text, fontSize: 15),
        cursorColor: MapPalette.of(context).text,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: MapPalette.of(context).text2, fontSize: 15),
          prefixIcon: Icon(AppIcons.magnifyingGlass, color: MapPalette.of(context).text2, size: 22),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(AppIcons.x, color: MapPalette.of(context).text2, size: 20),
                  onPressed: () {
                    _ctrl.clear();
                    ref.read(mapSearchProvider.notifier).set('');
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: MapPalette.of(context).tile,
          contentPadding: EdgeInsets.zero,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? MapPalette.of(context).accentBg : MapPalette.of(context).tile,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.slidersHorizontal, size: 18, color: active ? MapPalette.of(context).accentFg : MapPalette.of(context).text),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: active ? MapPalette.of(context).accentFg : MapPalette.of(context).text, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.subtitle, this.actionLabel, this.onAction});
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center, style: TextStyle(color: MapPalette.of(context).text, fontSize: 17, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: MapPalette.of(context).text2, fontSize: 14, height: 1.4)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, style: FilledButton.styleFrom(minimumSize: const Size(160, 44)), child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
