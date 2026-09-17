import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../../core/utils/open_external.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/features.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/profile.dart';
import '../../map/application/map_providers.dart';
import '../../safety/data/safety_repository.dart';
import '../../safety/presentation/report_sheet.dart';
import '../../social/application/chat_providers.dart';
import '../../social/application/community_providers.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/post.dart';
import '../../social/presentation/story_viewer_screen.dart';
import '../../social/presentation/widgets/masonry_grid.dart';
import '../application/event_providers.dart';
import '../domain/event.dart';
import '../domain/event_detail.dart';

class EventDetailsScreen extends ConsumerStatefulWidget {
  const EventDetailsScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends ConsumerState<EventDetailsScreen> {
  bool _rsvpBusy = false;
  bool _bookmarkBusy = false;
  bool _postBusy = false;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleBookmark(EventDetail d) async {
    setState(() => _bookmarkBusy = true);
    try {
      final on = await ref.read(eventActionsProvider).toggleBookmark(d.event.id);
      _snack(on ? 'Saved. We\'ll remind you within 24 hours of the start.' : 'Removed from your saved meets.');
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _bookmarkBusy = false);
    }
  }

  Future<void> _toggleRsvp(EventDetail d) async {
    setState(() => _rsvpBusy = true);
    try {
      final actions = ref.read(eventActionsProvider);
      if (d.isAttending) {
        await actions.leave(d.event.id);
      } else {
        await actions.join(d.event.id);
      }
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _rsvpBusy = false);
    }
  }

  Future<void> _post() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _postBusy = true);
    try {
      await ref.read(eventActionsProvider).addComment(widget.eventId, text);
      _comment.clear();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _postBusy = false);
    }
  }

  bool _checkInBusy = false;

  Future<void> _checkIn(EventDetail d) async {
    setState(() => _checkInBusy = true);
    try {
      await ref.read(eventActionsProvider).checkIn(d.event.id);
      _snack('Checked in. You\'re on the record.');
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _checkInBusy = false);
    }
  }

  Future<void> _openChat(EventDetail d) async {
    try {
      final conv = await ref.read(chatActionsProvider).openMeetChat(d.event.id);
      if (mounted) context.push(Routes.chat(conv));
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _menu(EventDetail d) async {
    final me = ref.read(currentUserIdProvider);
    final isOrganizer = me == d.event.organizerId;
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOrganizer && !d.event.isCancelled)
              ListTile(
                leading: const Icon(AppIcons.xCircle, color: AppColors.danger),
                title: const Text('Cancel this meet', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'cancel'),
              ),
            if (!isOrganizer) ...[
              ListTile(
                leading: const Icon(AppIcons.flag),
                title: const Text('Report meet'),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
              ListTile(
                leading: const Icon(AppIcons.prohibit, color: AppColors.danger),
                title: Text('Block ${d.organizer?.displayName ?? 'organizer'}', style: const TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'block'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'cancel':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancel this meet?'),
            content: const Text('Everyone who joined will see it as cancelled. This can\'t be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel meet', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        );
        if (ok == true) {
          try {
            await ref.read(eventActionsProvider).cancel(d.event.id);
          } catch (e) {
            _snack(friendlyError(e));
          }
        }
      case 'report':
        await showReportSheet(context, target: ReportTarget.event, targetId: d.event.id);
      case 'block':
        final blocked = await confirmBlockUser(
          context,
          ref,
          userId: d.event.organizerId,
          displayName: d.organizer?.displayName ?? 'this organizer',
        );
        if (blocked && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(eventDetailProvider(widget.eventId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(detail.value?.event.type.label ?? ''),
        actions: [
          if (detail.value != null)
            IconButton(icon: const Icon(AppIcons.dotsThreeVertical), onPressed: () => _menu(detail.value!)),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => _ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(eventDetailProvider(widget.eventId))),
        data: (d) {
          if (d == null) {
            return const _ErrorView(message: 'This meet no longer exists.');
          }
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(eventDetailProvider(widget.eventId));
                    ref.invalidate(eventCommentsProvider(widget.eventId));
                    await ref.read(eventDetailProvider(widget.eventId).future);
                  },
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _Cover(event: d.event),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Badges(event: d.event),
                            const SizedBox(height: 10),
                            Text(d.event.title, style: AppText.sectionTitle.copyWith(fontSize: 24, height: 1.15)),
                            const SizedBox(height: 14),
                            _InfoRow(icon: AppIcons.calendarBlank, text: formatEventDateFriendly(d.event.startsAt)),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: d.event.placeId == null ? null : () => context.push(Routes.place(d.event.placeId!)),
                              child: _InfoRow(
                                icon: AppIcons.mapPin,
                                text: '${d.event.venueName} · ${formatDistance(distanceKm(ref.watch(mapOriginProvider), d.event.latLng))}',
                                trailing: d.event.placeId == null ? null : Icon(AppIcons.caretRight, size: 20, color: AppColors.textMuted),
                              ),
                            ),
                            if (d.event.address != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(30, 2, 0, 0),
                                child: Text(d.event.address!, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
                              ),
                            const SizedBox(height: 10),
                            _QuickActions(event: d.event),
                            if (d.event.clubId != null) ...[
                              const SizedBox(height: 8),
                              _ClubRow(clubId: d.event.clubId!),
                            ],
                            if (d.event.vendorName != null) ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: d.event.vendorId == null ? null : () => context.push(Routes.partner(d.event.vendorId!)),
                                child: _InfoRow(icon: AppIcons.storefront, text: 'Hosted by ${d.event.vendorName}', trailing: Icon(AppIcons.caretRight, size: 20, color: AppColors.textMuted)),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _OrganizerTile(organizer: d.organizer),
                            const SizedBox(height: 12),
                            _Attendees(detail: d),
                            const SizedBox(height: 16),
                            if (d.event.isLive) ...[
                              _CheckInCard(detail: d, busy: _checkInBusy, onCheckIn: () => _checkIn(d)),
                              const SizedBox(height: 8),
                            ],
                            Row(
                              children: [
                                Expanded(child: _RsvpButton(detail: d, busy: _rsvpBusy, onPressed: () => _toggleRsvp(d))),
                                if (!d.event.isPast && !d.event.isCancelled) ...[
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: d.isBookmarked ? 'Saved · reminder on' : 'Save · remind me before it starts',
                                    child: Material(
                                      color: d.isBookmarked ? AppColors.textPrimary : AppColors.surfaceGray,
                                      borderRadius: BorderRadius.circular(AppRadius.md),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(AppRadius.md),
                                        onTap: _bookmarkBusy ? null : () => _toggleBookmark(d),
                                        child: SizedBox(width: 50, height: 46, child: Icon(d.isBookmarked ? AppIcons.bookmarkSimpleFill : AppIcons.bookmarkSimple, size: 22, color: d.isBookmarked ? AppColors.onInk : AppColors.textPrimary)),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (d.isAttending || d.event.organizerId == ref.watch(currentUserIdProvider)) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: SecondaryButton(label: 'Meet chat', icon: AppIcons.chatCircle, onPressed: () => _openChat(d))),
                                  if (d.event.isLive && d.event.type == EventType.convoy) ...[
                                    const SizedBox(width: 8),
                                    Expanded(child: SecondaryButton(label: 'Convoy live', icon: AppIcons.broadcast, onPressed: () => context.push(Routes.convoy(d.event.id)))),
                                  ],
                                ],
                              ),
                            ],
                            if ((d.event.description ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Text(d.event.description!.trim(), style: const TextStyle(fontSize: 15, height: 1.5)),
                            ],
                            const SizedBox(height: 20),
                            _MapPreview(event: d.event),
                            const SizedBox(height: 20),
                            if (d.event.isPast || d.event.checkinCount > 0) ...[
                              _RecapCard(event: d.event),
                              const SizedBox(height: 20),
                            ],
                            _Moments(detail: d),
                            if (kSocialFeed) ...[
                              const SizedBox(height: 20),
                              _PhotoWall(detail: d),
                            ],
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 12),
                            _Comments(eventId: widget.eventId),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _CommentComposer(controller: _comment, busy: _postBusy, onPost: _post),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- pieces ---

class _Cover extends StatelessWidget {
  const _Cover({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: event.coverUrl == null
          ? ColoredBox(
              color: AppColors.surfaceGray,
              child: Center(child: ArtIcon(event.type.art, size: 110)),
            )
          : Image.network(
              event.coverUrl!,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : ColoredBox(color: AppColors.surfaceGray),
              errorBuilder: (_, _, _) => ColoredBox(
                color: AppColors.surfaceGray,
                child: Center(child: ArtIcon(event.type.art, size: 110)),
              ),
            ),
    );
  }
}

class _Badges extends StatelessWidget {
  const _Badges({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context) {
    Widget pill(String text, {Color? bg, Color? fg, String? art}) => Container(
          padding: EdgeInsets.fromLTRB(art == null ? 10 : 6, 4, 10, 4),
          decoration: BoxDecoration(color: bg ?? AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (art != null) ...[ArtIcon(art, size: 18), const SizedBox(width: 5)],
              Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg ?? AppColors.textPrimary)),
            ],
          ),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        pill(event.type.label, art: event.type.art),
        if (event.isCancelled) pill('Cancelled', bg: const Color(0xFFFDE8EA), fg: AppColors.danger),
        if (!event.isCancelled && event.isLive) pill('LIVE', fg: AppColors.danger),
        if (!event.isCancelled && event.isInstant) pill('TT now', fg: AppColors.warnColor),
        if (!event.isCancelled && event.isPast) pill('Ended', fg: AppColors.textSecondary),
        if (!event.isCancelled && !event.isPast && event.isFull) pill('Full', fg: AppColors.textSecondary),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.trailing});
  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ?trailing,
      ],
    );
  }
}

class _ClubRow extends ConsumerWidget {
  const _ClubRow({required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubProvider(clubId)).value;
    if (club == null) return const SizedBox.shrink();
    return InkWell(
      onTap: () => context.push(Routes.club(clubId)),
      child: _InfoRow(icon: club.isOfficial ? AppIcons.sealCheck : AppIcons.shield, text: '${club.name}${club.isOfficial ? ' · Official club' : ''} · @${club.handle}', trailing: Icon(AppIcons.caretRight, size: 20, color: AppColors.textMuted)),
    );
  }
}

/// Photos posted to this meet by people who were there.
class _PhotoWall extends ConsumerWidget {
  const _PhotoWall({required this.detail});
  final EventDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final posts = ref.watch(postsWhereProvider((column: 'event_id', value: detail.event.id))).value ?? const <FeedPost>[];
    final canPost = detail.isAttending || detail.event.organizerId == me;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Photo wall${posts.isEmpty ? '' : ' (${posts.length})'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            if (canPost)
              TextButton.icon(
                onPressed: () => context.push(Routes.createPost(PostKind.post, eventId: detail.event.id)),
                icon: const Icon(AppIcons.cameraPlus, size: 18),
                label: const Text('Add photos'),
              ),
          ],
        ),
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              canPost ? 'Nothing here yet. Post your shots from the meet.' : 'Photos from people who joined will show up here.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          )
        else
          MasonryGrid(items: posts, padding: const EdgeInsets.only(top: 4)),
      ],
    );
  }
}

class _OrganizerTile extends StatelessWidget {
  const _OrganizerTile({required this.organizer});
  final Profile? organizer;

  @override
  Widget build(BuildContext context) {
    final o = organizer;
    final name = o?.displayName ?? o?.username ?? 'Unknown';
    final username = o?.username;
    return InkWell(
      onTap: o == null ? null : () => context.push(Routes.profile(o.id)),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            UserAvatar(url: o?.avatarUrl, name: name, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      children: [
                        const TextSpan(text: 'Organised by '),
                        TextSpan(text: name, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                  if (username != null)
                    Text('@$username', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(AppIcons.caretRight, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Attendees extends StatelessWidget {
  const _Attendees({required this.detail});
  final EventDetail detail;

  @override
  Widget build(BuildContext context) {
    final e = detail.event;
    final preview = detail.attendeesPreview;
    final capacity = e.maxAttendees == null ? '' : ' of ${e.maxAttendees}';
    return InkWell(
      onTap: e.attendeeCount == 0 ? null : () => _showGoing(context, e),
      borderRadius: BorderRadius.circular(10),
      child: Row(
      children: [
        if (preview.isNotEmpty) ...[
          AvatarStack(
            urls: preview.map((p) => p.avatarUrl).toList(),
            names: preview.map((p) => p.displayName ?? p.username).toList(),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            e.attendeeCount == 0
                ? 'No one has joined yet. Be the first.'
                : '${e.attendeeCount} going$capacity${detail.isAttending ? ' · including you' : ''}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: e.attendeeCount == 0 ? FontWeight.w400 : FontWeight.w600,
              color: e.attendeeCount == 0 ? AppColors.textSecondary : AppColors.textPrimary,
            ),
          ),
        ),
        if (e.attendeeCount > 0) Icon(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
      ],
    ),
    );
  }

  Future<void> _showGoing(BuildContext context, Event e) {
    return showModalBottomSheet<void>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (ctx, ref, _) {
          final going = ref.watch(eventAttendeesProvider(e.id));
          final checked = ref.watch(eventCheckedInProvider(e.id)).value?.map((p) => p.id).toSet() ?? const <String>{};
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.6,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('Going · ${e.attendeeCount}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  Expanded(
                    child: going.when(
                      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (err, _) => Center(child: Text(friendlyError(err))),
                      data: (list) => ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final p = list[i];
                          final here = checked.contains(p.id);
                          final host = p.id == e.organizerId;
                          return ListTile(
                            leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, size: 42),
                            title: Text(p.displayName ?? '@${p.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              [if (host) 'Host', if (here) 'Checked in', '@${p.username ?? ''}'].join(' · '),
                              style: TextStyle(fontSize: 12, color: here ? AppColors.success : AppColors.textSecondary),
                            ),
                            trailing: host ? const Icon(AppIcons.crown, size: 18, color: AppColors.warnColor) : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              context.push(Routes.profile(p.id));
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RsvpButton extends StatelessWidget {
  const _RsvpButton({required this.detail, required this.busy, required this.onPressed});
  final EventDetail detail;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final e = detail.event;
    final spinner = SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: detail.isAttending ? AppColors.textPrimary : Colors.white),
    );
    if (e.isCancelled) {
      return ElevatedButton(onPressed: null, child: const Text('Cancelled'));
    }
    if (e.isPast) {
      return ElevatedButton(onPressed: null, child: const Text('This meet has ended'));
    }
    if (detail.isAttending) {
      return ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy ? spinner : const Icon(AppIcons.check, size: 20),
        label: const Text('Going · tap to leave'),
      );
    }
    if (e.isFull) {
      return ElevatedButton(onPressed: null, child: const Text('Full'));
    }
    return FilledButton(onPressed: busy ? null : onPressed, child: busy ? spinner : const Text('Join'));
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 160,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: event.latLng, zoom: 14.5),
              liteModeEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
              markers: {Marker(markerId: MarkerId(event.id), position: event.latLng)},
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Text(event.venueName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Comments extends ConsumerWidget {
  const _Comments({required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(eventCommentsProvider(eventId));
    final me = ref.watch(currentUserIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comments${comments.value == null ? '' : ' (${comments.value!.length})'}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        comments.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (e, _) => Text(friendlyError(e), style: TextStyle(color: AppColors.textSecondary)),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No comments yet. Ask about parking, timing, anything.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                )
              : Column(
                  children: [
                    for (final c in list) _CommentTile(comment: c, isMine: c.userId == me, eventId: eventId),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment, required this.isMine, required this.eventId});
  final EventComment comment;
  final bool isMine;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = comment.author?.username ?? 'someone';
    return InkWell(
      onLongPress: () async {
        final action = await showModalBottomSheet<String>(
          useRootNavigator: true, // above the shell tab bar
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMine)
                  ListTile(
                    leading: const Icon(AppIcons.trash, color: AppColors.danger),
                    title: const Text('Delete comment', style: TextStyle(color: AppColors.danger)),
                    onTap: () => Navigator.pop(ctx, 'delete'),
                  )
                else ...[
                  ListTile(
                    leading: const Icon(AppIcons.flag),
                    title: const Text('Report comment'),
                    onTap: () => Navigator.pop(ctx, 'report'),
                  ),
                  ListTile(
                    leading: const Icon(AppIcons.prohibit, color: AppColors.danger),
                    title: Text('Block @$name', style: const TextStyle(color: AppColors.danger)),
                    onTap: () => Navigator.pop(ctx, 'block'),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (!context.mounted || action == null) return;
        switch (action) {
          case 'delete':
            try {
              await ref.read(eventActionsProvider).deleteComment(eventId, comment.id);
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
            }
          case 'report':
            await showReportSheet(context, target: ReportTarget.comment, targetId: comment.id);
          case 'block':
            await confirmBlockUser(context, ref, userId: comment.userId, displayName: '@$name');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(url: comment.author?.avatarUrl, name: comment.author?.displayName ?? name, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                      children: [
                        TextSpan(text: '$name  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(text: comment.body),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(_ago(comment.createdAt), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return formatDate(t);
  }
}

class _CommentComposer extends ConsumerWidget {
  const _CommentComposer({required this.controller, required this.busy, required this.onPost});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentProfileProvider).value;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              UserAvatar(url: me?.avatarUrl, name: me?.displayName ?? me?.username, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Add a comment…',
                    counterText: '',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              TextButton(
                onPressed: busy ? null : onPost,
                child: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Post'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ location layer ---

/// Shown while the meet is live: who's here, check in, add a moment.
class _CheckInCard extends ConsumerWidget {
  const _CheckInCard({required this.detail, required this.busy, required this.onCheckIn});
  final EventDetail detail;
  final bool busy;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = detail.event;
    final mine = ref.watch(myCheckinsProvider).value ?? const <String>{};
    final here = ref.watch(eventCheckedInProvider(e.id)).value ?? const <Profile>[];
    final checkedIn = mine.contains(e.id);
    final isOrganiser = e.organizerId == ref.watch(currentUserIdProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ArtIcon(AppArt.redDot, size: 14),
              const SizedBox(width: 6),
              Text('Live now · ${e.checkinCount} here', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (here.isNotEmpty) AvatarStack(urls: here.map((p) => p.avatarUrl).toList(), names: here.map((p) => p.username).toList(), size: 26, max: 4),
            ],
          ),
          const SizedBox(height: 12),
          if (isOrganiser) ...[
            PrimaryButton(label: 'Show check-in QR', onPressed: () => context.push(Routes.eventQr(e.id))),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: checkedIn
                    ? ElevatedButton.icon(onPressed: null, icon: const Icon(AppIcons.checkCircleFill, size: 18, color: AppColors.success), label: Text('You\'re here', style: TextStyle(color: AppColors.textPrimary)))
                    : PrimaryButton(label: 'I\'m here · check in', loading: busy, onPressed: busy ? null : onCheckIn),
              ),
              if (!checkedIn) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  child: ElevatedButton(
                    onPressed: () => context.push(Routes.scan),
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(46, 46)),
                    child: const Icon(AppIcons.scan, size: 20),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                child: ElevatedButton(
                  onPressed: () => context.push(Routes.createMoment(eventId: e.id)),
                  style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(46, 46)),
                  child: const Icon(AppIcons.camera, size: 20),
                ),
              ),
            ],
          ),
          if (!checkedIn)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Be at the meet with location on, then scan the organiser\'s QR (works within 300 m). Earns points.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
        ],
      ),
    );
  }
}

/// The album of a meet: moments taken here, kept after the map forgets them.
class _Moments extends ConsumerWidget {
  const _Moments({required this.detail});
  final EventDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = detail.event;
    final me = ref.watch(currentUserIdProvider);
    final moments = ref.watch(eventMomentsProvider(e.id)).value ?? const <Story>[];
    final canPost = !e.isPast && (detail.isAttending || e.organizerId == me);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Moments${moments.isEmpty ? '' : ' (${moments.length})'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            if (canPost)
              TextButton.icon(
                onPressed: () => context.push(Routes.createMoment(eventId: e.id)),
                icon: const Icon(AppIcons.cameraPlus, size: 18),
                label: const Text('Add'),
              ),
          ],
        ),
        if (moments.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              canPost ? 'Snap the scene. Moments stay in this meet\'s album.' : 'Moments from people who were here show up here.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          )
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: moments.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final m = moments[i];
                return GestureDetector(
                  onTap: () {
                    final author = m.author;
                    if (author == null) return;
                    context.push(Routes.stories, extra: StoryViewerArgs(groups: [StoryGroup(author: author, stories: [m], allSeen: true)], initialGroup: 0));
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 104,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(m.photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray)),
                          Positioned(left: 6, bottom: 6, child: UserAvatar(url: m.author?.avatarUrl, name: m.author?.username, size: 22, borderColor: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// What happened: who went, which cars came, how many moments.
class _RecapCard extends ConsumerWidget {
  const _RecapCard({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(eventRecapProvider(event.id)).value;
    final here = ref.watch(eventCheckedInProvider(event.id)).value ?? const <Profile>[];
    if (recap == null) return const SizedBox.shrink();
    Widget stat(String v, String l) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(l, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ArtIcon(AppArt.flag, size: 22),
              const SizedBox(width: 6),
              Text(event.isPast ? 'Recap' : 'So far', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [stat('${recap.went}', 'went'), stat('${recap.cars.length}', 'cars'), stat('${recap.moments}', 'moments')]),
          if (here.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                AvatarStack(urls: here.map((p) => p.avatarUrl).toList(), names: here.map((p) => p.username).toList(), size: 28, max: 6),
                const SizedBox(width: 8),
                Expanded(child: Text(here.take(3).map((p) => p.username ?? '').join(', ') + (here.length > 3 ? ' and ${here.length - 3} more' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
              ],
            ),
          ],
          if (recap.cars.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in recap.cars.take(12))
                  ActionChip(
                    avatar: c.photoUrl == null ? null : CircleAvatar(backgroundImage: NetworkImage(c.photoUrl!)),
                    label: Text('${c.make} ${c.model}'),
                    onPressed: () => context.push(Routes.car(c.id)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


/// Waze · Google Maps · WhatsApp · Copy link. Until an app-launcher package is
/// approved, each copies the right link/text and says where to paste it.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.event});
  final Event event;

  String get _appLink => 'https://creatiqai.github.io/TTSpot/m.html?id=${event.id}';
  String get _waze => wazeUrl(event.lat, event.lng);
  String get _gmaps => googleMapsUrl(event.lat, event.lng);
  String get _whatsapp {
    final when = event.isInstant ? 'now until ${formatTime(event.closesAt)}' : formatEventDateFriendly(event.startsAt);
    return '${event.title} · ${event.venueName} · $when\nWaze: $_waze\nJoin on TT Spot: $_appLink';
  }

  Future<void> _copy(BuildContext context, String text, String where) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(where)));
  }

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, IconData icon, Color bg, Color fg, VoidCallback onTap) => Expanded(
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(children: [Icon(icon, size: 20, color: fg), const SizedBox(height: 3), Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg))]),
              ),
            ),
          ),
        );
    return Row(
      children: [
        btn('Waze', AppIcons.navigationArrow, const Color(0xFF33CCFF), const Color(0xFF062A3A), () => openExternal(context, 'waze://?ll=${event.lat},${event.lng}&navigate=yes', fallbackUrl: _waze, appName: 'Waze')),
        const SizedBox(width: 8),
        btn('Maps', AppIcons.mapTrifold, AppColors.surfaceGray, AppColors.textPrimary, () => openExternal(context, 'comgooglemaps://?daddr=${event.lat},${event.lng}', fallbackUrl: _gmaps, appName: 'Google Maps')),
        const SizedBox(width: 8),
        btn('WhatsApp', AppIcons.chatCircle, const Color(0xFF25D366), const Color(0xFF063D1D), () => openExternal(context, 'whatsapp://send?text=${Uri.encodeComponent(_whatsapp)}', fallbackUrl: whatsappUrl(_whatsapp), appName: 'WhatsApp')),
        const SizedBox(width: 8),
        btn('Copy link', AppIcons.link, AppColors.surfaceGray, AppColors.textPrimary, () => _copy(context, _appLink, 'Link copied.')),
      ],
    );
  }
}
