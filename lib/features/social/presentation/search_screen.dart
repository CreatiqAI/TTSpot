import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/profile.dart';
import '../../map/presentation/widgets/place_card.dart' show showPlaceOnMap;
import '../application/community_providers.dart';
import '../application/social_providers.dart';
import '../application/tags_providers.dart';
import '../data/social_repository.dart';
import '../domain/club.dart';
import '../domain/tags.dart';
import 'widgets/masonry_grid.dart';
import 'widgets/seen_tracker.dart';

final _peopleSearchProvider = FutureProvider.family<List<Profile>, String>((ref, q) => ref.watch(socialRepositoryProvider).searchProfiles(q));

/// Tags, people, clubs, places and posts in one search, Instagram style.
/// Typing settles for 300 ms before anything is asked of the server.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _debounceTime = Duration(milliseconds: 300);
  /// Rows per section before "Show all".
  static const _fold = 5;

  final _ctrl = TextEditingController();
  final _seen = GlobalKey<SeenScopeState>();
  String _q = '';
  Timer? _debounce;
  final _open = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    final next = v.trim();
    _debounce?.cancel();
    if (next.isEmpty) {
      setState(() => _q = '');
      return;
    }
    // Rebuild now for the clear button; search once typing settles.
    setState(() {});
    _debounce = Timer(_debounceTime, () {
      if (mounted) _set(next);
    });
  }

  void _set(String q) {
    if (q == _q) return;
    _seen.currentState?.reset();
    setState(() {
      _q = q;
      _open.clear();
    });
  }

  PostQuery get _postQuery => (kind: PostQueryKind.search, text: _q);

  bool _onScroll(ScrollNotification n) {
    if (_q.isNotEmpty && n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 900) {
      ref.read(pagedPostsProvider(_postQuery).notifier).loadMore();
    }
    return false;
  }

  /// The first [_fold] of [list], or all of it once "Show all" was tapped.
  Iterable<T> _folded<T>(String section, List<T> list) => _open.contains(section) ? list : list.take(_fold);

  Widget? _showAll(String section, int count) => count <= _fold || _open.contains(section)
      ? null
      : _ShowAll(label: 'Show all $count', onTap: () => setState(() => _open.add(section)));

  @override
  Widget build(BuildContext context) {
    final searching = _q.isNotEmpty;
    final people = !searching ? const AsyncValue<List<Profile>>.data([]) : ref.watch(_peopleSearchProvider(_q));
    final clubs = ref.watch(clubsProvider(_q));
    final places = !searching ? const AsyncValue<List<Place>>.data([]) : ref.watch(placeSearchProvider(_q));
    // '' = popular tags, for the empty screen.
    final tags = ref.watch(tagSearchProvider(_q));
    final posts = !searching ? const AsyncValue<PagedPostsState>.data(PagedPostsState(items: [], done: true)) : ref.watch(pagedPostsProvider(_postQuery));

    final tagList = tags.value ?? const <TagCount>[];
    final postState = posts.value;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        titleSpacing: 0,
        title: SizedBox(
          height: 40,
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (v) {
              _debounce?.cancel();
              _set(v.trim());
            },
            decoration: InputDecoration(
              hintText: 'Search posts, people, clubs',
              prefixIcon: const Icon(AppIcons.magnifyingGlass, size: 20),
              contentPadding: EdgeInsets.zero,
              isDense: true,
              fillColor: AppColors.surfaceGray,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
              suffixIcon: _ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(AppIcons.x, size: 18),
                      onPressed: () {
                        _debounce?.cancel();
                        _ctrl.clear();
                        _set('');
                      },
                    ),
            ),
          ),
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: SeenScope(
        key: _seen,
        onSeen: ref.read(feedSignalsProvider).seen,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              // Nothing typed: popular tags to browse, then clubs.
              if (!searching && tagList.isNotEmpty) ...[
                const _Section('POPULAR TAGS'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final t in tagList.take(10)) _TagChip(tag: t, onTap: () => context.push(Routes.tag(t.tag)))],
                  ),
                ),
              ],
              if (!searching)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('CLUBS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
                ),
              if (searching && tagList.isNotEmpty) ...[
                const _Section('TAGS'),
                for (final t in _folded('tags', tagList))
                  ListTile(
                    leading: CircleAvatar(backgroundColor: AppColors.surfaceGray, child: Icon(AppIcons.hash, color: AppColors.textPrimary)),
                    title: Text('#${t.tag}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(postCountLabel(t.posts)),
                    onTap: () => context.push(Routes.tag(t.tag)),
                  ),
                ?_showAll('tags', tagList.length),
              ],
              ...people.maybeWhen(
                data: (list) => list.isEmpty
                    ? const []
                    : [
                        const _Section('PEOPLE'),
                        for (final p in _folded('people', list))
                          ListTile(
                            leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, seed: p.id, size: 44),
                            title: Text(p.username ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([p.displayName, p.homeState].where((s) => (s ?? '').isNotEmpty).join(' · ')),
                            onTap: () => context.push(Routes.profile(p.id)),
                          ),
                        ?_showAll('people', list.length),
                      ],
                orElse: () => const [],
              ),
              ...clubs.maybeWhen(
                data: (list) => [
                  if (searching && list.isNotEmpty) const _Section('CLUBS'),
                  for (final c in searching ? _folded('clubs', list) : list)
                    ListTile(
                      leading: UserAvatar(url: c.avatarUrl, name: c.name, size: 44, fallbackAsset: crestAsset(c.id)),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('@${c.handle} · ${c.memberCount} member${c.memberCount == 1 ? '' : 's'}'),
                      onTap: () => context.push(Routes.club(c.id)),
                    ),
                  if (searching) ?_showAll('clubs', list.length),
                  if (!searching)
                    ListTile(
                      leading: CircleAvatar(backgroundColor: AppColors.surfaceGray, child: Icon(AppIcons.plus, color: AppColors.textPrimary)),
                      title: const Text('Start a car club', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Apply to run one. Owners invite members and share the map.'),
                      onTap: () => context.push(Routes.clubApply),
                    ),
                ],
                orElse: () => const [],
              ),
              ...places.maybeWhen(
                data: (list) => list.isEmpty
                    ? const []
                    : [
                        const _Section('PLACES'),
                        for (final p in _folded('places', list))
                          ListTile(
                            leading: CircleAvatar(backgroundColor: AppColors.surfaceGray, child: ArtIcon(p.kindIcon, size: 26)),
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(p.kindLabel),
                            // The map, zoomed in on it with its card up; the card links to the page.
                            onTap: () => showPlaceOnMap(context, ref, p),
                          ),
                        ?_showAll('places', list.length),
                      ],
                orElse: () => const [],
              ),
              if (searching && postState != null && postState.items.isNotEmpty) ...[
                const _Section('POSTS'),
                MasonryGrid(items: postState.items),
                if (!postState.done) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              ],
              if (searching &&
                  tagList.isEmpty &&
                  (people.value?.isEmpty ?? true) &&
                  (clubs.value?.isEmpty ?? true) &&
                  (places.value?.isEmpty ?? true) &&
                  (postState?.items.isEmpty ?? true) &&
                  !people.isLoading &&
                  !clubs.isLoading &&
                  !tags.isLoading &&
                  !posts.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: EmptyState(titi: TitiPose.binoculars, title: 'No results.'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

class _ShowAll extends StatelessWidget {
  const _ShowAll({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
          child: Text(label),
        ),
      );
}

/// "#myvi 12" as a pill.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.onTap});
  final TagCount tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text('#${tag.tag}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              const SizedBox(width: 6),
              Text(compactCount(tag.posts), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
}
