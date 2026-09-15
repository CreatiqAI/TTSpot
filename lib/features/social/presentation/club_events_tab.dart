import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/empty_state.dart';
import '../../events/domain/event.dart';
import '../application/community_providers.dart';
import '../domain/club.dart';

/// Club account · Events tab: what the club is hosting, upcoming first.
class ClubEventsTab extends ConsumerWidget {
  const ClubEventsTab({super.key, required this.club});
  final Club club;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(clubEventsProvider(club.id));
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Events'),
        actions: [
          IconButton(tooltip: 'New event', icon: const Icon(AppIcons.plusCircle), onPressed: () => context.push(Routes.createEventAs(clubId: club.id))),
        ],
      ),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final upcoming = list.where((e) => e.startsAt.isAfter(now.subtract(const Duration(hours: 6)))).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          final past = list.where((e) => !upcoming.contains(e)).toList()..sort((a, b) => b.startsAt.compareTo(a.startsAt));
          if (list.isEmpty) {
            return EmptyState(
              art: AppArt.flag,
              title: 'No events yet',
              subtitle: 'Plan a meet, convoy or track day as ${club.name}. It shows on the map for everyone.',
              actionLabel: 'New event',
              onAction: () => context.push(Routes.createEventAs(clubId: club.id)),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (upcoming.isNotEmpty) const _Head('UPCOMING'),
              for (final e in upcoming) _EventTile(e: e),
              if (past.isNotEmpty) const _Head('PAST'),
              for (final e in past.take(30)) _EventTile(e: e, past: true),
            ],
          );
        },
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.e, this.past = false});
  final Event e;
  final bool past;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 52,
            height: 52,
            child: e.coverUrl == null ? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(e.type.art, size: 28))) : Image.network(e.coverUrl!, fit: BoxFit.cover),
          ),
        ),
        title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: past ? AppColors.textSecondary : AppColors.textPrimary)),
        subtitle: Text('${e.type.label} · ${formatEventDateFriendly(e.startsAt)} · ${e.venueName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.users, size: 16, color: AppColors.textSecondary),
            Text('${e.attendeeCount}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        onTap: () => context.push(Routes.event(e.id)),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
