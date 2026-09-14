import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/event_list_tile.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../events/application/event_providers.dart';
import '../../map/application/map_providers.dart';
import '../application/community_providers.dart';
import '../application/social_providers.dart';
import '../domain/club.dart';
import '../domain/post.dart';
import 'story_viewer_screen.dart';
import 'widgets/masonry_grid.dart';

/// A spot: cover, what it is, check in (打卡), who has been, the album, meets
/// held here and posts about it.
class PlaceScreen extends ConsumerStatefulWidget {
  const PlaceScreen({super.key, required this.placeId});
  final String placeId;

  @override
  ConsumerState<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends ConsumerState<PlaceScreen> {
  static const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  bool _busy = false;

  String get id => widget.placeId;

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _checkIn() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(communityActionsProvider).checkInAtPlace(id);
      _snack(r.isNew ? 'Checked in. That\'s ${r.total} for this spot.' : 'Already checked in here today.');
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = ref.watch(placeProvider(id));
    final events = ref.watch(placeEventsProvider(id)).value ?? const [];
    final moments = ref.watch(placeMomentsProvider(id)).value ?? const <Story>[];
    final posts = kSocialFeed ? (ref.watch(postsWhereProvider((column: 'place_id', value: id))).value ?? const <FeedPost>[]) : const <FeedPost>[];
    final regulars = ref.watch(placeRegularsProvider(id)).value ?? const <PlaceRegular>[];
    final visitors = ref.watch(placeRecentVisitorsProvider(id)).value ?? const <PlaceVisit>[];
    final busyDays = ref.watch(placeBusyDaysProvider(id)).value ?? const <int, int>{};
    final checkedToday = ref.watch(myPlaceCheckinTodayProvider(id)).value ?? false;
    final myCheckins = ref.watch(myCheckinsProvider).value ?? const <String>{};
    final origin = ref.watch(mapOriginProvider);
    final me = ref.watch(currentUserIdProvider);
    final upcoming = events.where((e) => !e.isPast && !e.isCancelled).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = events.where((e) => e.isPast && !e.isCancelled).toList();
    final days = (busyDays.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(2).where((e) => e.value > 0).map((e) => _days[e.key]).toList();

    return Scaffold(
      body: place.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (p) {
          if (p == null) return const Center(child: Text('This spot no longer exists.'));
          final cover = p.coverUrl ?? (moments.isNotEmpty ? moments.first.photoUrl : null);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(placeProvider(id));
              ref.invalidate(placeEventsProvider(id));
              ref.invalidate(placeMomentsProvider(id));
              ref.invalidate(placeRegularsProvider(id));
              ref.invalidate(placeRecentVisitorsProvider(id));
              await ref.read(placeProvider(id).future);
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 260,
                  pinned: true,
                  leading: Padding(
                    padding: const EdgeInsets.all(6),
                    child: _Circle(child: IconButton(icon: const Icon(AppIcons.arrowLeft, color: Colors.white), onPressed: () => context.pop())),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: _Circle(
                        child: IconButton(
                          tooltip: 'Show on map',
                          icon: const Icon(AppIcons.mapTrifold, color: Colors.white),
                          onPressed: () {
                            ref.read(mapModeProvider.notifier).set(MapMode.spots);
                            ref.read(mapListViewProvider.notifier).set(false);
                            context.go(Routes.map);
                          },
                        ),
                      ),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover != null)
                          Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceGray))
                        else
                          ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(p.kindArt, size: 110))),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66000000), Colors.transparent, Color(0x99000000)]),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ArtIcon(p.kindArt, size: 18),
                                  const SizedBox(width: 5),
                                  Text(p.kindLabel, style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  if (p.recommended) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(999)),
                                      child: const Text('★ Recommended', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(p.name, maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.1)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildListDelegate([
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _Stat(value: '${p.totalCheckins}', label: 'check-ins'),
                              _Stat(value: '${p.pastMeets}', label: 'meets'),
                              _Stat(value: formatDistance(distanceKm(origin, p.latLng)), label: 'away'),
                            ],
                          ),
                          if (p.tags.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [for (final t in p.tags) _Tag(t)],
                            ),
                          ],
                          if ((p.description ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(p.description!.trim(), style: const TextStyle(fontSize: 15, height: 1.45)),
                          ],
                          if (days.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('Meets usually on ${days.join(' & ')}', style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: checkedToday
                                    ? ElevatedButton.icon(
                                        onPressed: null,
                                        icon: const Icon(AppIcons.checkCircleFill, size: 18, color: AppColors.success),
                                        label: const Text('Checked in today', style: TextStyle(color: AppColors.textPrimary)),
                                      )
                                    : PrimaryButton(label: 'Check in here', loading: _busy, onPressed: _busy ? null : _checkIn),
                              ),
                              const SizedBox(width: 8),
                              Expanded(flex: 2, child: SecondaryButton(label: 'Moment', icon: AppIcons.camera, onPressed: () => context.push(Routes.createMoment(placeId: id)))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text('Check-ins need your location, within 300 m of the spot.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          if (p.recommended) ...[
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () => context.push(Routes.scan),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: AppColors.warnColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.md)),
                                child: const Row(
                                  children: [
                                    ArtIcon(AppArt.star, size: 28),
                                    SizedBox(width: 10),
                                    Expanded(child: Text('Find the TT Spot sticker here and scan it with a photo of your car for a verified check-in worth more points.', style: TextStyle(fontSize: 13, height: 1.35))),
                                    Icon(AppIcons.scan, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (visitors.isNotEmpty) ...[
                      const _Section('RECENTLY HERE'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            AvatarStack(urls: visitors.map((v) => v.profile.avatarUrl).toList(), names: visitors.map((v) => v.profile.username).toList(), size: 30, max: 6),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${visitors.first.profile.username ?? 'someone'} ${timeAgo(visitors.first.at)}${visitors.length > 1 ? ' · ${visitors.length - 1} more' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (regulars.isNotEmpty) ...[
                      const _Section('REGULARS'),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: regulars.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemBuilder: (_, i) {
                            final r = regulars[i];
                            return GestureDetector(
                              onTap: () => context.push(Routes.profile(r.profile.id)),
                              child: SizedBox(
                                width: 64,
                                child: Column(
                                  children: [
                                    UserAvatar(url: r.profile.avatarUrl, name: r.profile.displayName ?? r.profile.username, size: 52),
                                    const SizedBox(height: 4),
                                    Text(r.profile.username ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                                    Text('${r.visits}×', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (upcoming.isNotEmpty) ...[
                      const _Section('UPCOMING HERE'),
                      for (final e in upcoming) EventListTile(event: e, isOrganiser: e.organizerId == me, onTap: () => context.push(Routes.event(e.id))),
                    ],
                    _Section('ALBUM${moments.isEmpty ? '' : ' · ${moments.length}'}'),
                    if (moments.isEmpty)
                      const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No moments here yet. Snap one when you check in.', style: TextStyle(color: AppColors.textSecondary)))
                    else
                      _Album(moments: moments),
                    if (kSocialFeed) ...[
                      _Section('POSTS${posts.isEmpty ? '' : ' · ${posts.length}'}'),
                      if (posts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Row(
                            children: [
                              const Expanded(child: Text('Parking tips? Best table? Write it up.', style: TextStyle(color: AppColors.textSecondary))),
                              TextButton(onPressed: () => context.push(Routes.createPost(PostKind.post, placeId: id)), child: const Text('Write a post')),
                            ],
                          ),
                        )
                      else
                        MasonryGrid(items: posts),
                    ],
                    if (past.isNotEmpty) ...[
                      const _Section('PAST MEETS'),
                      for (final e in past.take(20))
                        EventListTile(
                          event: e,
                          isOrganiser: e.organizerId == me,
                          onTap: () => context.push(Routes.event(e.id)),
                          trailing: myCheckins.contains(e.id) ? const _Went() : null,
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                      child: SecondaryButton(label: 'Plan a meet here', icon: AppIcons.flagCheckered, onPressed: () => context.push(Routes.createEvent)),
                    ),
                  ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
        child: child,
      );
}

class _Album extends StatelessWidget {
  const _Album({required this.moments});
  final List<Story> moments;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 1.5, crossAxisSpacing: 1.5, childAspectRatio: 0.8),
      itemCount: moments.length,
      itemBuilder: (_, i) {
        final m = moments[i];
        return GestureDetector(
          onTap: () {
            final author = m.author;
            if (author == null) return;
            context.push(Routes.stories, extra: StoryViewerArgs(groups: [StoryGroup(author: author, stories: [m], allSeen: true)], initialGroup: 0));
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(m.photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceGray)),
              Positioned(left: 6, bottom: 6, child: UserAvatar(url: m.author?.avatarUrl, name: m.author?.username, size: 22, borderColor: Colors.white)),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
        child: Text('#$text', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      );
}

class _Went extends StatelessWidget {
  const _Went();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: const Text('Went ✓', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.success)),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
