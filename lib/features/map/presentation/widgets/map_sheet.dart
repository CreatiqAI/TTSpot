import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_art.dart';
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
import 'map_filter_sheet.dart';

/// Draggable dark sheet over the map. Content follows the map mode:
/// Now → friends, live meets, moments · Upcoming → meets · Spots → places to check in.
class MapSheet extends ConsumerWidget {
  const MapSheet({super.key, required this.controller, required this.onFocus});
  final DraggableScrollableController controller;
  final void Function(LatLng target) onFocus;

  static const peek = 0.17;
  static const half = 0.5;
  static const full = 0.92;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(mapModeProvider);
    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: peek,
      minChildSize: peek,
      maxChildSize: full,
      snap: true,
      snapSizes: const [peek, half, full],
      builder: (context, scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.mapSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, -6))],
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
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(2))),
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
          title: 'Friends & club on the map',
          count: list.length,
          action: 'Add friends',
          onAction: () => context.push(Routes.friends),
        ),
        if (pins.isLoading && list.isEmpty)
          const _Hint('Finding your crew…')
        else if (list.isEmpty)
          _Hint(friendCount == 0
              ? 'No friends yet. Add your crew and see them here when they open the app.'
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
                      border: Border.all(color: AppColors.mapSurface, width: 2),
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
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.mapText, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('$where · $ago · ${formatDistance(distanceKm)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.mapTextSecondary, fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Message',
              icon: const Icon(AppIcons.chatCircle, color: AppColors.mapTextSecondary, size: 20),
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
                    Image.network(m.photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: Colors.white10)),
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
                      : _Message(title: 'No meets planned here yet', subtitle: 'Plan one and the crew will come.', actionLabel: 'Plan a meet', onAction: () => context.push(Routes.createEvent)),
                )
              : SliverPadding(
                  padding: const EdgeInsets.only(bottom: 24),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => Divider(height: 1, indent: 88, color: Colors.white.withValues(alpha: 0.06)),
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

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _SearchField(hint: 'Spots to check in: mamak, touge, viewpoint…', onTap: expand),
          ),
        ),
        places.when(
          loading: () => const SliverToBoxAdapter(child: _Hint('Finding spots…')),
          error: (e, _) => SliverToBoxAdapter(
            child: _Message(title: 'Couldn\'t load spots', subtitle: 'Check your connection.', actionLabel: 'Retry', onAction: () => ref.invalidate(spotsProvider)),
          ),
          data: (list) => list.isEmpty
              ? const SliverToBoxAdapter(child: _Message(title: 'No spots around here yet', subtitle: 'Post a moment at a place and it becomes a spot.'))
              : SliverPadding(
                  padding: const EdgeInsets.only(bottom: 24),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => Divider(height: 1, indent: 92, color: Colors.white.withValues(alpha: 0.06)),
                    itemBuilder: (_, i) => SpotRow(
                      place: list[i],
                      distanceKm: distanceKm(origin, list[i].latLng),
                      dark: true,
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
    final fg = dark ? AppColors.mapText : AppColors.textPrimary;
    final fg2 = dark ? AppColors.mapTextSecondary : AppColors.textSecondary;
    final tile = dark ? Colors.white.withValues(alpha: 0.08) : AppColors.surfaceGray;
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
                      Image.network(
                        p.coverUrl!,
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
          Text(title, style: const TextStyle(color: AppColors.mapText, fontSize: 15, fontWeight: FontWeight.w700)),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 6),
            Text('$count', style: const TextStyle(color: AppColors.mapTextSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
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
        child: Text(text, style: const TextStyle(color: AppColors.mapTextSecondary, fontSize: 14, height: 1.4)),
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
        style: const TextStyle(color: AppColors.mapText, fontSize: 15),
        cursorColor: AppColors.mapText,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: AppColors.mapTextSecondary, fontSize: 15),
          prefixIcon: const Icon(AppIcons.magnifyingGlass, color: AppColors.mapTextSecondary, size: 22),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(AppIcons.x, color: AppColors.mapTextSecondary, size: 20),
                  onPressed: () {
                    _ctrl.clear();
                    ref.read(mapSearchProvider.notifier).set('');
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.08),
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
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.slidersHorizontal, size: 18, color: active ? Colors.black : AppColors.mapText),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: active ? Colors.black : AppColors.mapText, fontSize: 13.5, fontWeight: FontWeight.w600)),
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
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mapText, fontSize: 17, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mapTextSecondary, fontSize: 14, height: 1.4)),
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
