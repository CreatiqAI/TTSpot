import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/event_list_tile.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../friends/application/friends_providers.dart';
import '../application/event_providers.dart';
import '../application/my_events_provider.dart';
import '../domain/event.dart';

/// The meets list. Lives inside the Map tab as its "list view" ([embedded]),
/// and is also a plain screen with a back arrow.
/// Upcoming: yours plus the ones friends are going to. Past: your record, with
/// a "Went" mark where you checked in.
class MyEventsScreen extends ConsumerWidget {
  const MyEventsScreen({super.key, this.embedded = false, this.onShowMap});
  final bool embedded;
  final VoidCallback? onShowMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final my = ref.watch(myEventsProvider);
    final me = ref.watch(currentUserIdProvider);
    final checkins = ref.watch(myCheckinsProvider).value ?? const <String>{};
    final friendsGoing = ref.watch(friendsGoingProvider).value ?? const [];
    final friends = ref.watch(friendsProvider).value ?? const [];

    Future<void> refresh() async {
      ref.invalidate(myEventsProvider);
      ref.invalidate(myCheckinsProvider);
      ref.invalidate(friendsGoingProvider);
      await ref.read(myEventsProvider.future);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: embedded
              ? IconButton(tooltip: 'Map view', icon: const Icon(AppIcons.mapTrifold), onPressed: onShowMap)
              : IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
          title: const Text('Meets'),
          actions: [
            IconButton(tooltip: 'Plan a meet', icon: const Icon(AppIcons.plusCircle), onPressed: () => context.push(Routes.createEvent)),
          ],
          bottom: const TabBar(
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.textPrimary,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 1.5,
            dividerColor: AppColors.border,
            labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            tabs: [Tab(text: 'Upcoming'), Tab(text: 'Past')],
          ),
        ),
        body: my.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(friendlyError(e), style: const TextStyle(color: AppColors.textSecondary)),
                TextButton(onPressed: refresh, child: const Text('Retry')),
              ],
            ),
          ),
          data: (data) {
            final mineIds = data.upcoming.map((e) => e.id).toSet();
            final others = friendsGoing.where((g) => !mineIds.contains(g.event.id) && !g.event.isPast).toList();
            return TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: refresh,
                  child: data.upcoming.isEmpty && others.isEmpty
                      ? _Fill(
                          child: EmptyState(
                            art: AppArt.calendar,
                            title: 'Nothing planned',
                            subtitle: 'Join a meet from the map, or hit TT now and make one.',
                            actionLabel: 'Open the map',
                            onAction: () => context.go(Routes.map),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            if (data.upcoming.isNotEmpty) ...[
                              const _Section('YOURS'),
                              for (final e in data.upcoming)
                                EventListTile(
                                  event: e,
                                  isOrganiser: e.organizerId == me,
                                  onTap: () => context.push(Routes.event(e.id)),
                                  trailing: e.isLive ? const _Live() : null,
                                ),
                            ],
                            if (others.isNotEmpty) ...[
                              const _Section('FRIENDS ARE GOING'),
                              for (final g in others)
                                EventListTile(
                                  event: g.event,
                                  onTap: () => context.push(Routes.event(g.event.id)),
                                  trailing: AvatarStack(
                                    urls: [for (final id in g.friendIds) friends.where((f) => f.id == id).firstOrNull?.avatarUrl],
                                    names: [for (final id in g.friendIds) friends.where((f) => f.id == id).firstOrNull?.username],
                                    size: 24,
                                    max: 3,
                                  ),
                                ),
                            ],
                          ],
                        ),
                ),
                RefreshIndicator(
                  onRefresh: refresh,
                  child: data.past.isEmpty
                      ? const _Fill(
                          child: EmptyState(
                            art: AppArt.flag,
                            title: 'No past meets yet',
                            subtitle: 'Check in at a meet and it becomes part of your record.',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: data.past.length,
                          separatorBuilder: (_, _) => const Divider(indent: 90),
                          itemBuilder: (_, i) => _PastTile(event: data.past[i], me: me, went: checkins.contains(data.past[i].id)),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PastTile extends StatelessWidget {
  const _PastTile({required this.event, required this.me, required this.went});
  final Event event;
  final String? me;
  final bool went;

  @override
  Widget build(BuildContext context) {
    return EventListTile(
      event: event,
      isOrganiser: event.organizerId == me,
      onTap: () => context.push(Routes.event(event.id)),
      trailing: went
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: const Text('Went ✓', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.success)),
            )
          : null,
    );
  }
}

class _Live extends StatelessWidget {
  const _Live();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: const Text('LIVE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.danger)),
      );
}

class _Fill extends StatelessWidget {
  const _Fill({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: c.maxHeight, child: child),
        ),
      );
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
