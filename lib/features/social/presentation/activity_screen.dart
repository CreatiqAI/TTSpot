import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../friends/application/friends_providers.dart';
import '../application/notification_providers.dart';
import '../domain/notification.dart';

/// Full-screen activity (deep links); the Chats tab embeds [ActivityList].
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Activity'),
      ),
      body: const ActivityList(),
    );
  }
}

/// Likes, comments, joins, friend requests, TT-now pings, badges, reminders.
/// Marks everything read when shown.
class ActivityList extends ConsumerStatefulWidget {
  const ActivityList({super.key});

  @override
  ConsumerState<ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends ConsumerState<ActivityList> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(notificationActionsProvider).markAllRead());
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(notificationsProvider);
    final badges = ref.watch(allBadgesProvider).value ?? const <AppBadge>[];
    final me = ref.watch(currentUserIdProvider);

    return RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future);
          await ref.read(notificationActionsProvider).markAllRead();
        },
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (items) => items.isEmpty
              ? LayoutBuilder(
                  builder: (_, c) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: c.maxHeight,
                      child: const EmptyState(art: AppArt.bell, title: 'No activity yet', subtitle: 'Likes, comments, joins and badges land here.'),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => _Row(n: items[i], badges: badges, me: me),
                ),
        ),
    );
  }
}

/// Partner notifications carry `applied:<name>` (to admins, with an actor),
/// `approved:<name>` or `rejected:<reason>` (to the applicant, no actor).
(String, String?) _partnerText(AppNotification n) {
  final body = n.body ?? '';
  if (body.startsWith('applied-club:')) return ('applied to run a car club: ${body.substring(13)}', Routes.adminPartners);
  if (body.startsWith('approved-club:')) return ('You can now run ${body.substring(14)} on TT Spot. Create the club and start inviting members.', Routes.createClub);
  if (body.startsWith('rejected-club:')) return ('Your car club application was not approved: ${body.substring(14)}', Routes.clubApply);
  if (body.startsWith('applied:')) return ('applied to be a partner: ${body.substring(8)}', Routes.adminPartners);
  if (body.startsWith('approved:')) return ('${body.substring(9)} is now a TT Spot partner. Open your dashboard to publish vouchers.', Routes.vendor);
  if (body.startsWith('rejected:')) return ('Your partner application was not approved: ${body.substring(9)}', Routes.partnerApply);
  return (body, null);
}

class _Row extends ConsumerWidget {
  const _Row({required this.n, required this.badges, required this.me});
  final AppNotification n;
  final List<AppBadge> badges;
  final String? me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = n.actor?.username ?? 'Someone';
    final badge = n.badgeId == null ? null : badges.where((b) => b.id == n.badgeId).firstOrNull;
    final (text, route) = switch (n.type) {
      NotificationType.follow => ('started following you.', Routes.profile(n.actor?.id ?? '')),
      NotificationType.postLike => ('liked your post.', n.postId == null ? null : Routes.post(n.postId!)),
      NotificationType.postComment => ('commented: ${n.body ?? ''}', n.postId == null ? null : Routes.post(n.postId!)),
      NotificationType.eventJoin => ('joined ${n.eventTitle ?? 'your meet'}.', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.eventComment => ('commented on ${n.eventTitle ?? 'your meet'}: ${n.body ?? ''}', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.eventReminder => ('${n.eventTitle ?? 'A meet you joined'} is within 24 hours. See you there!', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.eventCancelled => ('cancelled ${n.eventTitle ?? 'a meet you joined'}.', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.spottedClaim => ('claimed the car you spotted.', n.postId == null ? null : Routes.post(n.postId!)),
      NotificationType.badge => ('You earned the ${badge?.name ?? 'a new'} badge ${badge?.emoji ?? '🏅'}', me == null ? null : Routes.badges(me!)),
      NotificationType.carOfWeek => (n.body ?? 'Your build is Car of the Week!', n.postId == null ? null : Routes.post(n.postId!)),
      NotificationType.clubJoin => (n.body == 'admin' ? 'now helps run ${n.clubName ?? 'your club'}.' : 'joined ${n.clubName ?? 'your club'}.', n.clubId == null ? null : Routes.club(n.clubId!)),
      NotificationType.friendRequest => ('wants to be friends.', Routes.friends),
      NotificationType.friendAccepted => ('accepted your friend request. You\'ll see each other on the map.', Routes.profile(n.actor?.id ?? '')),
      NotificationType.ttNow => ('started TT now${n.body == null ? '' : ' @ ${n.body}'}. Otw?', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.checkin => ('checked in at ${n.eventTitle ?? 'your meet'}.', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.referral => ('joined with your code and checked in. +${n.body ?? ''} points for you.', Routes.points),
      NotificationType.points => (n.body ?? 'You earned points.', Routes.points),
      NotificationType.partner => _partnerText(n),
      NotificationType.voucher => ((n.body ?? '').startsWith('redeemed:') ? 'Voucher used: ${n.body!.substring(9)}' : (n.body ?? 'Voucher update.'), Routes.myVouchers),
      NotificationType.clubInvite => (
          (n.body ?? '').startsWith('admin:')
              ? 'wants you to help run ${n.clubName ?? n.body!.substring(6)} as an admin. Open the club to accept.'
              : 'invited you to join ${n.clubName ?? n.body ?? 'their club'}. Open the club to accept.',
          n.clubId == null ? null : Routes.club(n.clubId!)
        ),
      NotificationType.unknown => ('did something.', null),
    };
    final systemMessage = n.type == NotificationType.badge ||
        n.type == NotificationType.carOfWeek ||
        n.type == NotificationType.eventReminder ||
        (n.type == NotificationType.partner && n.actor == null) ||
        (n.type == NotificationType.points && n.actor == null) ||
        n.type == NotificationType.voucher;

    return InkWell(
      onTap: route == null ? null : () => context.push(route),
      child: Container(
        color: n.read ? null : AppColors.primary.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (systemMessage)
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
                child: ArtIcon.emoji(
                  switch (n.type) {
                    NotificationType.badge => badge?.emoji ?? '🏅',
                    NotificationType.carOfWeek => '🏆',
                    NotificationType.partner => '🤝',
                    NotificationType.voucher => '☕',
                    NotificationType.points => '⭐',
                    _ => '⏰',
                  },
                  size: 26,
                ),
              )
            else
              GestureDetector(
                onTap: n.actor == null ? null : () => context.push(Routes.profile(n.actor!.id)),
                child: UserAvatar(url: n.actor?.avatarUrl, name: n.actor?.displayName ?? actor, size: 44),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.35),
                  children: [
                    if (!systemMessage) TextSpan(text: '$actor ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: text),
                    TextSpan(text: '  ${timeAgo(n.createdAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            ),
            if (n.type == NotificationType.friendRequest && n.actor != null) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => ref.read(friendActionsProvider).accept(n.actor!.id),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                child: const Text('Accept'),
              ),
            ],
            if (n.type == NotificationType.ttNow && n.eventId != null) ...[
              const SizedBox(width: 8),
              const ArtIcon(AppArt.coffee, size: 28),
            ],
            if (n.postCover != null) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(n.postCover!, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 44)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
