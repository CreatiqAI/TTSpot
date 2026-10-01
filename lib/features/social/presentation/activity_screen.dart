import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/thumb_image.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/presentation/friend_request_buttons.dart';
import '../application/chat_providers.dart';
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
  /// Friend requests answered here. Their rows stay put, showing what
  /// happened, until the member leaves: the server drops an answered
  /// request's notification, so [_kept] holds the row meanwhile.
  final _answers = FriendRequestAnswers();
  final _kept = <String, AppNotification>{};

  @override
  void initState() {
    super.initState();
    _answers.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(notificationActionsProvider).markAllRead());
  }

  @override
  void dispose() {
    _answers.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _snack(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }

  /// Accept or Delete: the row changes at once and goes back if it fails.
  Future<void> _answer(AppNotification n, RequestAnswer a) async {
    final from = n.actor?.id;
    if (from == null) return;
    _kept[n.id] = n;
    final actions = ref.read(friendActionsProvider);
    try {
      // Keyed by the notification: a new request from the same person is a new row.
      await _answers.answer(n.id, a, () => a == RequestAnswer.accepted ? actions.accept(from) : actions.decline(from));
    } catch (e) {
      _snack(e);
    }
  }

  Future<void> _message(String userId) async {
    try {
      final conv = await ref.read(chatActionsProvider).openDm(userId);
      if (mounted) context.push(Routes.chat(conv));
    } catch (e) {
      _snack(e);
    }
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
          data: (fresh) {
            final items = keepAnsweredRows(fresh, _kept.values, id: (n) => n.id, newerFirst: (a, b) => b.createdAt.compareTo(a.createdAt));
            return items.isEmpty
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
                    itemBuilder: (_, i) {
                      final n = items[i];
                      final from = n.type == NotificationType.friendRequest ? n.actor?.id : null;
                      return _Row(
                        n: n,
                        badges: badges,
                        me: me,
                        answer: from == null ? null : _answers.of(n.id),
                        onAnswer: from == null ? null : (a) => _answer(n, a),
                        onMessage: from == null ? null : () => _message(from),
                      );
                    },
                  );
          },
        ),
    );
  }
}

/// Partner notifications carry `applied:<name>` (to admins, with an actor),
/// `approved:<name>` or `rejected:<reason>` (to the applicant, no actor).
(String, String?) _partnerText(AppNotification n) {
  final body = n.body ?? '';
  if (body.startsWith('applied-organizer:')) return ('applied to be a verified organizer: ${body.substring(18)}', Routes.adminPartners);
  if (body.startsWith('approved-organizer:')) return ('You\'re a verified organizer. Open any meet you host and tap Organizer tools.', Routes.meets);
  if (body.startsWith('rejected-organizer:')) return ('Your organizer application was not approved: ${body.substring(19)}', Routes.organizerApply);
  if (body.startsWith('applied-club:')) return ('applied to run a car club: ${body.substring(13)}', Routes.adminPartners);
  if (body.startsWith('approved-club:')) return ('You can now run ${body.substring(14)} on TT Spot. Create the club and start inviting members.', Routes.createClub);
  if (body.startsWith('rejected-club:')) return ('Your car club application was not approved: ${body.substring(14)}', Routes.clubApply);
  if (body.startsWith('applied:')) return ('applied to be a partner: ${body.substring(8)}', Routes.adminPartners);
  if (body.startsWith('approved:')) return ('${body.substring(9)} is now a TT Spot partner. Open your dashboard to publish vouchers.', Routes.vendor);
  if (body.startsWith('rejected:')) return ('Your partner application was not approved: ${body.substring(9)}', Routes.partnerApply);
  return (body, null);
}

/// Card notifications carry `trade:<id>` (an offer, with an actor),
/// `accepted:<id>` / `declined:<id>` (their answer) or `redeemed:<title>` (no actor).
(String, String?) _cardsText(AppNotification n) {
  final body = n.body ?? '';
  if (body.startsWith('trade:')) return ('sent you a card trade offer. Open Trades to accept or decline.', Routes.cardTrades);
  if (body.startsWith('accepted:')) return ('accepted your trade. The cards are in your collection.', Routes.cards);
  if (body.startsWith('declined:')) return ('passed on your trade offer this time.', Routes.cardTrades);
  if (body.startsWith('redeemed:')) return ('Prize handed over: ${body.substring(9)}', Routes.cardPrizes);
  return (body.isEmpty ? 'Something new in Cards.' : body, Routes.cards);
}

class _Row extends ConsumerWidget {
  const _Row({required this.n, required this.badges, required this.me, this.answer, this.onAnswer, this.onMessage});
  final AppNotification n;
  final List<AppBadge> badges;
  final String? me;

  /// Friend requests: what the member did with it on this visit (null: waiting).
  final RequestAnswer? answer;
  final ValueChanged<RequestAnswer>? onAnswer;
  final VoidCallback? onMessage;

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
      NotificationType.badge => (
          badgeAsset(n.badgeId) != null ? 'You earned the ${badge?.name ?? 'a new'} badge.' : 'You earned the ${badge?.name ?? 'a new'} badge ${badge?.emoji ?? '🏅'}',
          me == null ? null : Routes.badges(me!)
        ),
      NotificationType.carOfWeek => (n.body ?? 'Your build is Car of the Week!', n.postId == null ? null : Routes.post(n.postId!)),
      NotificationType.clubJoin => (n.body == null ? 'joined ${n.clubName ?? 'your club'}.' : 'is now ${n.body == 'vp' ? 'Vice President' : n.body == 'secretary' ? 'Secretary' : 'an officer'} of ${n.clubName ?? 'your club'}.', n.clubId == null ? null : Routes.club(n.clubId!)),
      NotificationType.friendRequest => answer == RequestAnswer.accepted
          ? ('is now your friend.', Routes.profile(n.actor?.id ?? ''))
          : ('wants to be friends.', Routes.friends),
      NotificationType.friendAccepted => ('accepted your friend request. You\'ll see each other on the map.', Routes.profile(n.actor?.id ?? '')),
      NotificationType.ttNow => ('started TT now${n.body == null ? '' : ' @ ${n.body}'}. Otw?', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.checkin => ('checked in at ${n.eventTitle ?? 'your meet'}.', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.referral => ('joined with your code and checked in. +${n.body ?? ''} points for you.', Routes.points),
      NotificationType.points => (n.body ?? 'You earned points.', Routes.points),
      NotificationType.partner => _partnerText(n),
      NotificationType.voucher => ((n.body ?? '').startsWith('redeemed:') ? 'Voucher used: ${n.body!.substring(9)}' : (n.body ?? 'Voucher update.'), Routes.myVouchers),
      NotificationType.clubInvite => (
          (n.body ?? '').startsWith('vp:') || (n.body ?? '').startsWith('secretary:') || (n.body ?? '').startsWith('admin:')
              ? 'wants you as ${n.body!.startsWith('secretary:') ? 'Secretary' : 'Vice President'} of ${n.clubName ?? n.body!.substring(n.body!.indexOf(':') + 1)}. Open the club to accept.'
              : 'invited you to join ${n.clubName ?? n.body ?? 'their club'}. Open the club to accept.',
          n.clubId == null ? null : Routes.club(n.clubId!)
        ),
      NotificationType.clubRequest => (
          switch (n.body) {
            'approved' => 'let you into ${n.clubName ?? 'the club'}. Welcome!',
            'declined' => 'said not this time for ${n.clubName ?? 'the club'}.',
            _ => 'wants to join ${n.clubName ?? 'your club'}${(n.body ?? '').length > 4 ? ': “${n.body!.substring(4)}”' : ''}. Open the club to decide.',
          },
          n.clubId == null ? null : Routes.club(n.clubId!)
        ),
      NotificationType.clubEvent => ('scheduled ${n.eventTitle ?? 'a meet'} for ${n.body ?? n.clubName ?? 'your club'}.', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.partnerEvent => ('${n.body ?? 'A partner'} is hosting ${n.eventTitle ?? 'an event'}. Have a look.', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.garage => ('just pulled up at ${n.body ?? 'the garage'}${n.clubName == null ? '' : ' (${n.clubName})'}.', n.clubId == null ? null : Routes.club(n.clubId!)),
      NotificationType.clubOfficial => (
          switch ((n.body ?? '').split(':').first) {
            'requested' => 'wants ${n.body!.substring(10)} to go official.',
            'approved' => '${n.clubName ?? n.body!.substring(9)} is now an official club. Notifications, gold badge, no limits.',
            'expired' => '${n.clubName ?? n.body!.substring(8)} is back to underground. Renew to stay official.',
            'ended' => '${n.clubName ?? n.body!.substring(6)} is back to underground.',
            _ => n.body ?? 'Club status changed.',
          },
          n.clubId == null ? null : Routes.club(n.clubId!)
        ),
      NotificationType.cards => _cardsText(n),
      NotificationType.portrait => ('Your car portrait is ready. Tap to see it.', n.body == null ? Routes.myGarage : Routes.car(n.body!)),
      NotificationType.meetStart => ('${n.eventTitle ?? 'Your meet'} is on. Open TT Spot when you arrive to check in.', n.eventId == null ? null : Routes.event(n.eventId!)),
      NotificationType.announcement => (
          'in ${n.eventTitle ?? 'your meet'}: ${(n.body ?? '').replaceFirst('\n', ' · ')}',
          n.eventId == null ? null : Routes.event(n.eventId!)
        ),
      NotificationType.luckyDraw => (n.body ?? 'Lucky draw update.', n.eventId == null ? null : Routes.event(n.eventId!)),
      // Road tax / insurance running out; the body is the whole sentence.
      NotificationType.carDoc => (n.body ?? 'A car document runs out soon.', Routes.myGarage),
      NotificationType.unknown => ('did something.', null),
    };
    final systemMessage = n.type == NotificationType.badge ||
        n.type == NotificationType.carOfWeek ||
        n.type == NotificationType.eventReminder ||
        n.type == NotificationType.meetStart ||
        n.type == NotificationType.luckyDraw ||
        (n.type == NotificationType.announcement && n.actor == null) ||
        (n.type == NotificationType.partner && n.actor == null) ||
        (n.type == NotificationType.points && n.actor == null) ||
        (n.type == NotificationType.clubOfficial && n.actor == null) ||
        n.type == NotificationType.voucher ||
        (n.type == NotificationType.cards && n.actor == null) ||
        n.type == NotificationType.portrait ||
        n.type == NotificationType.carDoc;

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
                decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
                child: n.type == NotificationType.badge && badgeAsset(n.badgeId) != null
                    ? BadgeImage(id: n.badgeId!, size: 36)
                    : n.type == NotificationType.points
                    ? const PointsCoin(size: 28)
                    : ArtIcon.emoji(
                  switch (n.type) {
                    NotificationType.badge => badge?.emoji ?? '🏅',
                    NotificationType.carOfWeek => '🏆',
                    NotificationType.partner => '🤝',
                    NotificationType.voucher => '☕',
                    NotificationType.points => '⭐',
                    NotificationType.cards => '🎁',
                    NotificationType.portrait => '✨',
                    NotificationType.meetStart => '🏁',
                    NotificationType.luckyDraw => '🎉',
                    NotificationType.announcement => '📣',
                    NotificationType.carDoc => '📅',
                    _ => '⏰',
                  },
                  size: 26,
                ),
              )
            else
              GestureDetector(
                onTap: n.actor == null ? null : () => context.push(Routes.profile(n.actor!.id)),
                child: UserAvatar(url: n.actor?.avatarUrl, name: n.actor?.displayName ?? actor, seed: n.actor?.id, size: 44),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.35),
                  children: [
                    if (!systemMessage) TextSpan(text: '$actor ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: text),
                    TextSpan(text: '  ${timeAgo(n.createdAt)}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            ),
            if (n.type == NotificationType.friendRequest && n.actor != null && onAnswer != null) ...[
              const SizedBox(width: 8),
              FriendRequestButtons(
                answer: answer,
                onAccept: () => onAnswer!(RequestAnswer.accepted),
                onDelete: () => onAnswer!(RequestAnswer.removed),
                onMessage: onMessage ?? () {},
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
                child: ThumbImage(n.postCover!, width: 44, height: 44, error: const SizedBox(width: 44, height: 44)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
