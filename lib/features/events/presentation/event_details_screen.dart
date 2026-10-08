import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/open_external.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../map/presentation/widgets/static_pin_map.dart';

import '../../../core/config/features.dart';
import '../../../core/directions/directions.dart';
import '../../../core/guide/guide.dart';
import '../../../core/guide/guide_controller.dart';
import '../../../core/guide/guide_on_first_view.dart';
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
import '../../guides/map_guides.dart';
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
import '../application/on_my_way.dart' show onMyWayWindowOpen;
import '../domain/event.dart';
import '../domain/event_detail.dart';
import '../../profile/presentation/widgets/car_picker_sheet.dart';
import 'end_event.dart';
import 'event_car_widgets.dart';
import 'on_my_way_button.dart';
import 'whos_here_sheet.dart';
import '../../expo/door/presentation/event_hub_card.dart';
import '../../floorplan/presentation/floorplan_entry.dart';
import '../../organizer/presentation/widgets/lucky_draw_card.dart';
import '../../organizer/presentation/widgets/organizer_badge.dart';
import '../../organizer/presentation/widgets/organizer_tools_entry.dart';
import '../../../core/router/pop_or_home.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/share_links.dart';
import '../../../core/widgets/share_options_sheet.dart';
import '../../../core/widgets/thumb_image.dart';
import '../../expo/contest/application/contest_providers.dart';
import '../../expo/dashboard/application/dashboard_providers.dart';
import '../../expo/dashboard/presentation/expo_dashboard_screen.dart' show ExpoDashboardBody;
import '../../expo/door/application/door_providers.dart';
import '../../expo/door/domain/door_models.dart';
import '../../expo/exhibitors/application/exhibitors_providers.dart';
import '../../expo/exhibitors/presentation/exhibitors_screen.dart' show ExhibitorsBody;
import '../../expo/expo_routes.dart';
import '../../expo/schedule/application/agenda_providers.dart';
import '../../expo/schedule/presentation/schedule_screen.dart' show ScheduleBody;
import '../../expo/stamps/application/stamps_providers.dart';
import '../../expo/stamps/presentation/leads_screen.dart' show LeadsBody;
import '../../expo/stamps/presentation/stamps_screen.dart' show StampsBody;
import '../../floorplan/application/floorplan_providers.dart';
import '../../floorplan/presentation/floorplan_preview.dart';
import '../../organizer/application/organizer_providers.dart';
import '../../organizer/data/organizer_repository.dart';
import '../../organizer/domain/organizer_models.dart';
import '../../organizer/presentation/organizer_groups.dart';
import '../../share/share_card_renderer.dart';
import '../application/event_view.dart';
import '../domain/event_kind.dart';
import 'event_role_switch.dart';

part 'event_page_big.dart';

class EventDetailsScreen extends ConsumerStatefulWidget {
  const EventDetailsScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends ConsumerState<EventDetailsScreen> {
  /// What TiTi's first-meet tour spotlights.
  final _guide = EventGuideKeys();
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
    // Joining with 2+ cars: which one? (Closing the sheet cancels the join.)
    final car = d.isAttending ? null : await chooseOutingCar(context, ref, title: 'Which car are you bringing?');
    if ((car?.cancelled ?? false) || !mounted) return;
    setState(() => _rsvpBusy = true);
    try {
      final actions = ref.read(eventActionsProvider);
      if (d.isAttending) {
        await actions.leave(d.event.id);
      } else {
        await actions.join(d.event.id, carId: car?.car?.id);
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
    final car = await chooseCheckinCar(context, ref, d.event.id); // asks only with 2+ cars
    if (car.cancelled || !mounted) return;
    setState(() => _checkInBusy = true);
    try {
      await ref.read(eventActionsProvider).checkIn(d.event.id, carId: car.car?.id);
      if (!mounted) return;
      final shareCar = car.car ?? myShareCar(ref);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('Checked in. You\'re on the record.'),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => showShareCardSheet(
              context,
              CheckinShareSpec(
                placeName: d.event.title,
                at: DateTime.now(),
                carCover: shareCar?.cover,
                carBodyStyle: shareCar?.bodyStyle,
                carTitle: shareCar?.title,
              ),
            ),
          ),
        ));
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

  /// The host circle (organizer, co-hosts, club officers, admins), as the
  /// server's is_meet_host sees it. The role is usually loaded already
  /// (the Organizer tools row watches it).
  Future<bool> _isHost(Event e) async {
    if (ref.read(currentUserIdProvider) == e.organizerId) return true;
    final role = ref.read(myEventRoleProvider(e.id)).value;
    if (role != null) return role.isHostCircle;
    try {
      return (await ref.read(organizerRepositoryProvider).myEventRole(e.id)).isHostCircle;
    } catch (_) {
      return false;
    }
  }

  Future<void> _menu(EventDetail d) async {
    final me = ref.read(currentUserIdProvider);
    final isOrganizer = me == d.event.organizerId;
    // An official, big event or a public listing is an "event", not a "meet".
    final noun = d.event.isListing || (ref.read(eventHubProvider(d.event.id)).value?.isBig ?? false) ? 'event' : 'meet';
    // End it while it runs, cancel it before the start. Not a listing: it
    // isn't ours to end.
    final listing = d.event.isListing;
    final close = !listing && await _isHost(d.event) ? eventCloseAction(d.event, DateTime.now()) : null;
    if (!mounted) return;
    if (isOrganizer && close == null) {
      // Nothing left to do with my own meet once it's over.
      _snack(d.event.isCancelled ? 'This $noun was cancelled.' : 'This $noun has ended.');
      return;
    }
    final action = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (close != null)
              ListTile(
                key: const ValueKey('menu-close-event'),
                leading: Icon(eventCloseIcon(close), color: AppColors.danger),
                title: Text(eventCloseLabel(close, noun: noun), style: const TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'close'),
              ),
            if (!isOrganizer) ...[
              ListTile(
                leading: const Icon(AppIcons.flag),
                title: Text('Report $noun'),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
              if (!listing)
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
      case 'close':
        await closeEventFlow(context, d.event, noun: noun);
      case 'report':
        await showReportSheet(context, target: ReportTarget.event, targetId: d.event.id);
      case 'block':
        final blocked = await confirmBlockUser(
          context,
          ref,
          userId: d.event.organizerId,
          displayName: d.organizer?.displayName ?? 'this organizer',
        );
        if (blocked && mounted) popOrHome(context);
    }
  }

  /// TiTi's tour of a meet, built from what the page shows right now.
  Guide _buildGuide() {
    final d = ref.read(eventDetailProvider(widget.eventId)).value;
    if (d == null) return eventGuide(_guide, attending: false);
    final host = d.event.organizerId == ref.read(currentUserIdProvider);
    if (d.event.isListing) {
      // A public listing: Going, the official page, location check-in.
      return eventGuide(
        _guide,
        attending: d.isAttending,
        full: d.event.isFull,
        live: d.event.isLive,
        onMyWay: d.isAttending && !d.event.isCancelled && onMyWayWindowOpen(startsAt: d.event.startsAt, closesAt: d.event.closesAt, now: DateTime.now()),
        chat: d.isAttending,
        listing: true,
        officialPage: d.event.officialPage != null,
      );
    }
    final hub = ref.read(eventHubProvider(widget.eventId)).value;
    if (hub != null && hub.isBig) {
      // A big event opens on its Overview tab: the check-in card (until I'm
      // checked in), Join and the event chat. No "I'm on my way" there.
      return eventGuide(
        _guide,
        attending: d.isAttending,
        full: d.event.isFull,
        live: d.event.isLive && !hub.checkedIn,
        chat: d.isAttending || host,
        big: true,
      );
    }
    return eventGuide(
      _guide,
      attending: d.isAttending,
      full: d.event.isFull,
      live: d.event.isLive,
      // Same rules as the page: "I'm on my way" from 3 h before the start,
      // the meet chat for those going.
      onMyWay: (d.isAttending || host) && !d.event.isCancelled && onMyWayWindowOpen(startsAt: d.event.startsAt, closesAt: d.event.closesAt, now: DateTime.now()),
      chat: d.isAttending || host,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(eventDetailProvider(widget.eventId));
    final loaded = detail.value;
    // The hub says whether this is a big event (any Expo module). Wait for
    // it on the first load, so a big event doesn't flash the meet layout.
    final hubAsync = ref.watch(eventHubProvider(widget.eventId));
    final hub = hubAsync.value;
    final hubPending = hubAsync.isLoading && !hubAsync.hasValue && !hubAsync.hasError;
    // A listing always gets the one-page layout: the big-event tabs are
    // for events run in TT Spot.
    final big = (hub?.isBig ?? false) && !(loaded?.event.isListing ?? false);
    // First meet page of someone who isn't its host, while it's still on.
    final guideReady = loaded != null &&
        !hubPending &&
        loaded.event.organizerId != ref.watch(currentUserIdProvider) &&
        !loaded.event.isCancelled &&
        !loaded.event.isPast &&
        ref.watch(guideJourneyProvider) == null;

    return HomeOnBack(
      child: GuideOnFirstView(
      id: GuideIds.event,
      ready: guideReady,
      build: _buildGuide,
      child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(loaded == null || hubPending ? '' : eventPageTitle(loaded.event, big: big)),
        actions: [
          if (detail.value != null) ...[
            IconButton(tooltip: 'Share', icon: const Icon(AppIcons.shareFat), onPressed: () => showEventShareOptions(context, detail.value!.event)),
            if (!detail.value!.event.isListing || detail.value!.event.organizerId != ref.watch(currentUserIdProvider))
              IconButton(icon: const Icon(AppIcons.dotsThreeVertical), onPressed: () => _menu(detail.value!)),
          ],
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => _ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(eventDetailProvider(widget.eventId))),
        data: (d) {
          if (d == null) {
            return const _ErrorView(message: 'This meet no longer exists.');
          }
          if (hubPending) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          if (hub != null && big) {
            return _BigEventBody(
              detail: d,
              hub: hub,
              guide: _guide,
              actions: _PageActions(
                rsvp: () => _toggleRsvp(d),
                bookmark: () => _toggleBookmark(d),
                checkIn: () => _checkIn(d),
                chat: () => _openChat(d),
                rsvpBusy: _rsvpBusy,
                bookmarkBusy: _bookmarkBusy,
                checkInBusy: _checkInBusy,
              ),
            );
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
                            _InfoRow(icon: AppIcons.calendarBlank, text: formatEventSpan(d.event.startsAt, d.event.endsAt)),
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
                            _QuickActions(
                              event: d.event,
                              onMyWayKey: _guide.onMyWay,
                              onMyWay: (d.isAttending || d.event.organizerId == ref.watch(currentUserIdProvider)) &&
                                  !d.event.isCancelled &&
                                  onMyWayWindowOpen(startsAt: d.event.startsAt, closesAt: d.event.closesAt, now: DateTime.now()),
                            ),
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
                            ..._hostRows(d, officialKey: _guide.officialPage),
                            const SizedBox(height: 12),
                            _Attendees(detail: d),
                            const SizedBox(height: 16),
                            if (d.event.isLive) ...[
                              _CheckInCard(key: _guide.checkIn, detail: d, busy: _checkInBusy, onCheckIn: () => _checkIn(d)),
                              const SizedBox(height: 8),
                            ],
                            // A listing has no host here: no door hub, no draw.
                            if (!d.event.isListing) ...[
                              EventHubCard(eventId: d.event.id),
                              LuckyDrawCard(eventId: d.event.id),
                            ],
                            Row(
                              children: [
                                Expanded(child: _RsvpButton(key: _guide.rsvp, detail: d, busy: _rsvpBusy, onPressed: () => _toggleRsvp(d))),
                                if (!d.event.isPast && !d.event.isCancelled) ...[
                                  const SizedBox(width: 8),
                                  _BookmarkButton(on: d.isBookmarked, onTap: _bookmarkBusy ? null : () => _toggleBookmark(d)),
                                ],
                              ],
                            ),
                            if (d.isAttending && !d.event.isPast && !d.event.isCancelled) BringingCarRow(eventId: d.event.id),
                            if (d.isAttending || d.event.organizerId == ref.watch(currentUserIdProvider)) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: SecondaryButton(key: _guide.chat, label: d.event.isListing ? 'Event chat' : 'Meet chat', icon: AppIcons.chatCircle, onPressed: () => _openChat(d))),
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
                            FloorplanEntry(eventId: d.event.id),
                            if (d.event.isPast || d.event.checkinCount > 0) ...[
                              _RecapCard(event: d.event),
                              const SizedBox(height: 20),
                            ],
                            if (!d.event.isListing) OrganizerToolsEntry(event: d.event),
                            if (!d.event.isListing &&
                                d.event.organizerId == ref.watch(currentUserIdProvider) &&
                                (d.event.isLive || (d.event.isPast && DateTime.now().difference(d.event.closesAt) < const Duration(hours: 24)))) ...[
                              Material(
                                color: AppColors.surfaceGray,
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                                  leading: const Icon(AppIcons.listChecks),
                                  title: const Text('Who\'s here', style: TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    d.event.checkinCount == 0 ? 'Confirm arrivals as they check in.' : '${d.event.checkinCount} checked in. Confirm who really came.',
                                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                  ),
                                  trailing: const Icon(AppIcons.caretRight),
                                  onTap: () => showWhosHereSheet(context, d.event),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (!d.event.isListing && (d.event.isLive || d.event.isPast) && d.event.organizerId == ref.watch(currentUserIdProvider)) ...[
                              Material(
                                color: AppColors.surfaceGray,
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                                  leading: const Icon(AppIcons.chartBar),
                                  title: const Text('Turnout report', style: TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('Verified check-ins, cars by make, arrivals. Share it with sponsors.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                                  trailing: const Icon(AppIcons.caretRight),
                                  onTap: () => context.push(Routes.eventReport(d.event.id)),
                                ),
                              ),
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
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------- pieces ---

class _Cover extends StatelessWidget {
  const _Cover({required this.event, this.aspectRatio = 4 / 3});
  final Event event;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      // A preset (or no cover) shows the bundled file; an uploaded photo loads.
      child: event.bundledCover != null
          ? Image.asset(event.bundledCover!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(
                color: AppColors.surfaceGray,
                child: Center(child: ArtIcon(event.type.art, size: 110)),
              ),
            )
          : Image(image: CachedNetworkImageProvider(event.coverUrl!),
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : ColoredBox(color: AppColors.surfaceGray),
              errorBuilder: (_, _, _) => Image.asset(event.defaultCover, fit: BoxFit.cover),
            ),
    );
  }
}

/// The kind pill ("Expo", "Official event", "Meet"…; a blue seal when an
/// official club or a verified organizer hosts it) and the state pills.
class _Badges extends ConsumerWidget {
  const _Badges({required this.event, this.big = false});
  final Event event;
  final bool big;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = eventKindOf(event, big: big);
    final verified = !event.isListing && (event.isOfficialClubEvent || event.hostIsOrganizer || (ref.watch(isOrganizerProvider(event.organizerId)).value ?? false));
    Widget pill(String text, {Color? bg, Color? fg, String? art, bool seal = false, Key? key}) => Container(
          key: key,
          padding: EdgeInsets.fromLTRB(art == null ? 10 : 6, 4, 10, 4),
          decoration: BoxDecoration(color: bg ?? AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (art != null) ...[ArtIcon(art, size: 18), const SizedBox(width: 5)],
              Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg ?? AppColors.textPrimary))),
              if (seal) ...[
                const SizedBox(width: 4),
                const Icon(AppIcons.sealCheck, size: 15, color: OrganizerBadge.color, semanticLabel: 'Verified'),
              ],
            ],
          ),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        pill(kind.badge, art: big ? null : (kind == EventKind.official ? EventType.official.art : event.type.art), seal: verified, key: const ValueKey('event-kind')),
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
            UserAvatar(url: o?.avatarUrl, name: name, seed: o?.id, size: 40),
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
                        WidgetSpan(alignment: PlaceholderAlignment.middle, child: OrganizerBadge(userId: o?.id)),
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

/// Who runs it: the organizer tile, or for a listing "Public event · by X",
/// "Listed by TiTi" and the Official page button.
List<Widget> _hostRows(EventDetail d, {Key? officialKey}) {
  final e = d.event;
  if (!e.isListing) return [_OrganizerTile(organizer: d.organizer)];
  final page = e.officialPage;
  return [
    _ListingHostTile(event: e, lister: d.organizer),
    if (page != null) ...[
      const SizedBox(height: 10),
      _OfficialPageButton(key: officialKey, url: page.toString()),
    ],
  ];
}

/// A listing's host line: the real organiser (not tappable: they aren't on
/// TT Spot) and, small, the account that listed it (tap: its profile).
class _ListingHostTile extends StatelessWidget {
  const _ListingHostTile({required this.event, required this.lister});
  final Event event;
  final Profile? lister;

  @override
  Widget build(BuildContext context) {
    final by = lister?.displayName ?? lister?.username ?? 'TiTi';
    final l = lister;
    return Row(
      key: const ValueKey('listing-host'),
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
          child: Icon(AppIcons.globe, size: 22, color: AppColors.textPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.listingLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 1),
              InkWell(
                key: const ValueKey('listed-by'),
                onTap: l == null ? null : () => context.push(Routes.profile(l.id)),
                borderRadius: BorderRadius.circular(6),
                child: Text('Listed by $by', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens a listing's official page in the browser.
class _OfficialPageButton extends StatelessWidget {
  const _OfficialPageButton({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: SecondaryButton(label: 'Official page', icon: AppIcons.arrowSquareOut, onPressed: () => openExternal(context, url)),
      );
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
            seeds: preview.map((p) => p.id).toList(),
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
          final cars = ref.watch(eventCarsProvider(e.id)).value ?? const {};
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
                          final host = !e.isListing && p.id == e.organizerId;
                          final car = cars[p.id];
                          final status = Text(
                            [if (host) 'Host', if (here) 'Checked in', '@${p.username ?? ''}'].join(' · '),
                            style: TextStyle(fontSize: 12, color: here ? AppColors.success : AppColors.textSecondary),
                          );
                          return ListTile(
                            leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, seed: p.id, size: 42),
                            title: Text(p.displayName ?? '@${p.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: car?.title == null
                                ? status
                                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [status, EventCarLine(title: car!.title!, cover: car.cover, bodyStyle: car.bodyStyle)]),
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
  const _RsvpButton({super.key, required this.detail, required this.busy, required this.onPressed});
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
      return ElevatedButton(onPressed: null, child: Text(e.isListing ? 'This event has ended' : 'This meet has ended'));
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
    return FilledButton(onPressed: busy ? null : onPressed, child: busy ? spinner : Text(e.isListing ? 'Going' : 'Join'));
  }
}

/// Save the meet: a reminder before it starts.
class _BookmarkButton extends StatelessWidget {
  const _BookmarkButton({required this.on, required this.onTap});
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: on ? 'Saved · reminder on' : 'Save · remind me before it starts',
        child: Material(
          color: on ? AppColors.textPrimary : AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: SizedBox(width: 50, height: 46, child: Icon(on ? AppIcons.bookmarkSimpleFill : AppIcons.bookmarkSimple, size: 22, color: on ? AppColors.onInk : AppColors.textPrimary)),
          ),
        ),
      );
}

/// The map on the event page is a platform view, which widget tests can't
/// build. Tests switch it off; it stays on in the app.
@visibleForTesting
bool debugEventPageMaps = true;

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context) {
    if (!debugEventPageMaps) return SizedBox(height: 160, child: ColoredBox(color: AppColors.surfaceGray));
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 160,
        child: Stack(
          children: [
            StaticPinMap(points: [event.latLng], zoom: 14.5),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Text(event.venueName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF101010))),
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
            UserAvatar(url: comment.author?.avatarUrl, name: comment.author?.displayName ?? name, seed: comment.author?.id, size: 32),
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
              UserAvatar(url: me?.avatarUrl, name: me?.displayName ?? me?.username, seed: me?.id, size: 32),
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
  const _CheckInCard({super.key, required this.detail, required this.busy, required this.onCheckIn, this.big = false});
  final EventDetail detail;
  final bool busy;
  final VoidCallback onCheckIn;

  /// A big event: you check in with the door QR.
  final bool big;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = detail.event;
    final mine = ref.watch(myCheckinsProvider).value ?? const <String>{};
    final here = ref.watch(eventCheckedInProvider(e.id)).value ?? const <Profile>[];
    final checkedIn = mine.contains(e.id);
    // A listing has no host to show a QR: location check-in only.
    final listing = e.isListing;
    final isOrganiser = !listing && e.organizerId == ref.watch(currentUserIdProvider);
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
              Expanded(
                child: Text('Live now · ${e.checkinCount} here', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              if (here.isNotEmpty) AvatarStack(urls: here.map((p) => p.avatarUrl).toList(), names: here.map((p) => p.displayName ?? p.username).toList(), seeds: here.map((p) => p.id).toList(), size: 26, max: 4),
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
              if (!checkedIn && !listing) ...[
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
              child: Text(
                big
                    ? 'Scan the QR at the entrance with TT Spot. You get your pass and a lucky draw number.'
                    : listing
                        ? "Be at the event with location on, then tap I'm here. Earns points."
                        : 'Be at the meet with location on, then scan the organiser\'s QR (works within 300 m). Earns points.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
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
                          ThumbImage(m.photoUrl, error: ColoredBox(color: AppColors.surfaceGray)),
                          Positioned(left: 6, bottom: 6, child: UserAvatar(url: m.author?.avatarUrl, name: m.author?.username, seed: m.author?.id, size: 22, borderColor: Colors.white)),
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
                AvatarStack(urls: here.map((p) => p.avatarUrl).toList(), names: here.map((p) => p.displayName ?? p.username).toList(), seeds: here.map((p) => p.id).toList(), size: 28, max: 6),
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
                    avatar: c.photoUrl == null ? null : CircleAvatar(backgroundImage: CachedNetworkImageProvider(c.photoUrl!)),
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


/// Directions (the remembered app, or the chooser; long-press always asks)
/// and Share, side by side. For members and the host from 3 h before the
/// start until the end, "I'm on my way" takes Share's place (Share stays in
/// the app bar).
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.event, this.onMyWay = false, this.onMyWayKey});
  final Event event;
  final bool onMyWay;

  /// TiTi's tour spotlights "I'm on my way" by this.
  final Key? onMyWayKey;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: SecondaryButton(
              label: 'Directions',
              icon: AppIcons.navigationArrow,
              onPressed: () => openDirections(context, lat: event.lat, lng: event.lng, label: event.venueName),
              onLongPress: () => openDirections(context, lat: event.lat, lng: event.lng, label: event.venueName, choose: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: onMyWay
                ? OnMyWayButton(key: onMyWayKey, event: event)
                : SecondaryButton(label: 'Share', icon: AppIcons.shareFat, onPressed: () => showEventShareOptions(context, event)),
          ),
        ],
      );
}

/// "Title · venue · when" plus Waze and the TT Spot link, for WhatsApp and
/// the plain link share.
String _eventShareText(Event event) {
  final when = event.isInstant ? 'now until ${formatTime(event.closesAt)}' : formatEventDateFriendly(event.startsAt);
  final official = event.isListing ? event.officialPage : null;
  return '${event.title} · ${event.venueName} · $when\nWaze: ${wazeUrl(event.lat, event.lng)}\nJoin on TT Spot: ${shareLink('event', event.id)}${official == null ? '' : '\nOfficial page: $official'}';
}

/// Share a meet: send it in a TT Spot chat (as the meet card), WhatsApp,
/// the link, or a story image (with the host's invite link or my referral).
Future<void> showEventShareOptions(BuildContext context, Event event) {
  final me = ProviderScope.containerOf(context, listen: false).read(currentUserIdProvider);
  return showShareOptions(
    context,
    ShareItem(type: 'event', id: event.id, title: event.title, text: _eventShareText(event), eventId: event.id),
    extras: [
      ShareExtra(
        icon: AppIcons.image,
        label: 'Story image',
        subtitle: 'A card for Instagram or WhatsApp status',
        onTap: () => showShareCardSheet(context, MeetInviteShareSpec(event: event, hostInvite: !event.isListing && me != null && me == event.organizerId)),
      ),
    ],
  );
}
