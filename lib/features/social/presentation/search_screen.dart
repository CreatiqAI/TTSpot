import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/profile.dart';
import '../application/community_providers.dart';
import '../data/social_repository.dart';
import '../domain/club.dart';

final _peopleSearchProvider = FutureProvider.family<List<Profile>, String>((ref, q) => ref.watch(socialRepositoryProvider).searchProfiles(q));

/// People, clubs and places in one search, Instagram style.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = _q.isEmpty ? const AsyncValue<List<Profile>>.data([]) : ref.watch(_peopleSearchProvider(_q));
    final clubs = ref.watch(clubsProvider(_q));
    final places = _q.isEmpty ? const AsyncValue<List<Place>>.data([]) : ref.watch(placeSearchProvider(_q));

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
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search people, clubs, places',
              prefixIcon: const Icon(AppIcons.magnifyingGlass, size: 20),
              contentPadding: EdgeInsets.zero,
              isDense: true,
              fillColor: AppColors.surfaceGray,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(AppIcons.x, size: 18),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() => _q = '');
                      },
                    ),
            ),
          ),
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: ListView(
        children: [
          if (_q.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('CLUBS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
            ),
          ...people.maybeWhen(
            data: (list) => list.isEmpty
                ? const []
                : [
                    const _Section('PEOPLE'),
                    for (final p in list)
                      ListTile(
                        leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, size: 44),
                        title: Text(p.username ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([p.displayName, p.homeState].where((s) => (s ?? '').isNotEmpty).join(' · ')),
                        onTap: () => context.push(Routes.profile(p.id)),
                      ),
                  ],
            orElse: () => const [],
          ),
          ...clubs.maybeWhen(
            data: (list) => [
              if (_q.isNotEmpty && list.isNotEmpty) const _Section('CLUBS'),
              for (final c in list)
                ListTile(
                  leading: UserAvatar(url: c.avatarUrl, name: c.name, size: 44),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('@${c.handle} · ${c.memberCount} member${c.memberCount == 1 ? '' : 's'}'),
                  onTap: () => context.push(Routes.club(c.id)),
                ),
              if (_q.isEmpty)
                ListTile(
                  leading: const CircleAvatar(backgroundColor: AppColors.surfaceGray, child: Icon(AppIcons.plus, color: AppColors.textPrimary)),
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
                    for (final p in list)
                      ListTile(
                        leading: CircleAvatar(backgroundColor: AppColors.surfaceGray, child: ArtIcon(p.kindArt, size: 24)),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(p.kindLabel),
                        onTap: () => context.push(Routes.place(p.id)),
                      ),
                  ],
            orElse: () => const [],
          ),
          if (_q.isNotEmpty &&
              (people.value?.isEmpty ?? true) &&
              (clubs.value?.isEmpty ?? true) &&
              (places.value?.isEmpty ?? true) &&
              !people.isLoading &&
              !clubs.isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No results.', style: TextStyle(color: AppColors.textSecondary))),
            ),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
