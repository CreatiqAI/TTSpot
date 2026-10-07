part of 'event_details_screen.dart';

// A big, official event (any Expo module): a header, the role switch for
// members with an extra role, then a pinned tab bar with one tab per module.
// Every tab is slivers in one CustomScrollView, so the header scrolls away
// and the tabs stay on top. See docs/expo-mode-plan.md.

/// The page's actions, run by the page's State (busy flags included).
class _PageActions {
  const _PageActions({
    required this.rsvp,
    required this.bookmark,
    required this.checkIn,
    required this.chat,
    this.rsvpBusy = false,
    this.bookmarkBusy = false,
    this.checkInBusy = false,
  });
  final VoidCallback rsvp;
  final VoidCallback bookmark;
  final VoidCallback checkIn;
  final VoidCallback chat;
  final bool rsvpBusy;
  final bool bookmarkBusy;
  final bool checkInBusy;
}

/// One tab: a stable id and its label.
class _Tab {
  const _Tab(this.id, this.label);
  final String id;
  final String label;
}

class _BigEventBody extends ConsumerStatefulWidget {
  const _BigEventBody({required this.detail, required this.hub, required this.guide, required this.actions});
  final EventDetail detail;
  final EventHub hub;
  final EventGuideKeys guide;
  final _PageActions actions;

  @override
  ConsumerState<_BigEventBody> createState() => _BigEventBodyState();
}

class _BigEventBodyState extends ConsumerState<_BigEventBody> with TickerProviderStateMixin {
  final _scroll = ScrollController();

  /// The header (and the role switch): the tabs pin right under it.
  final _topKey = GlobalKey();
  TabController? _tabs;
  String? _sig;
  List<_Tab> _tabList = const [];
  EventView _view = EventView.attendee;

  /// The last tab per view, so switching views and back keeps my place.
  final Map<EventView, String> _picked = {};

  String get _id => widget.detail.event.id;

  @override
  void dispose() {
    _tabs?.removeListener(_onTab);
    _tabs?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A new controller whenever the view or its set of tabs changes.
  void _syncTabs(EventView view, List<_Tab> tabs) {
    final sig = '${view.name}:${tabs.map((t) => t.id).join(',')}';
    if (sig == _sig) return;
    _sig = sig;
    _view = view;
    _tabList = tabs;
    final old = _tabs;
    final at = tabs.indexWhere((t) => t.id == _picked[view]);
    _tabs = TabController(length: tabs.length, vsync: this, initialIndex: at < 0 ? 0 : at)..addListener(_onTab);
    if (old != null) {
      old.removeListener(_onTab);
      // The old TabBar lets go of it in this frame; dispose after.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _onTab() {
    final c = _tabs;
    if (c == null || c.index >= _tabList.length) return;
    final id = _tabList[c.index].id;
    if (_picked[_view] == id) return;
    setState(() => _picked[_view] = id);
    _toTabTop();
  }

  /// A new tab starts at its top, right under the pinned tabs, not halfway
  /// down where the last tab was.
  void _toTabTop() {
    if (!_scroll.hasClients) return;
    final box = _topKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.size.height;
    if (_scroll.offset > top) _scroll.jumpTo(top);
  }

  Future<void> _refresh() async {
    final id = _id;
    ref.invalidate(eventDetailProvider(id));
    ref.invalidate(myEventRoleProvider(id));
    ref.invalidate(myDrawStatusProvider(id));
    ref.invalidate(floorLevelsProvider(id));
    ref.invalidate(myEventPositionProvider(id));
    ref.invalidate(eventExhibitorsProvider(id));
    ref.invalidate(eventAgendaProvider(id));
    ref.invalidate(myStampsProvider(id));
    ref.invalidate(currentContestIdProvider(id));
    ref.invalidate(expoDashboardProvider(id));
    ref.invalidate(eventDrawsProvider(id));
    for (final b in widget.hub.myBooths) {
      ref.invalidate(exhibitorLeadsProvider(b.id));
    }
    await ref.read(eventDetailProvider(id).future).catchError((_) => null);
  }

  List<_Tab> _tabsFor(EventView view, EventRole role, EventHub h) => switch (view) {
        EventView.attendee => [for (final m in eventModulesFor(h)) _Tab(m.name, m.label)],
        EventView.organizer => role.tools ? [for (final g in organizerGroupsFor(role)) _Tab(g.name, g.label)] : const [_Tab('verify', 'Organizer')],
        EventView.booth => [for (final b in h.myBooths) _Tab(b.id, h.myBooths.length == 1 ? 'My booth' : b.name)],
      };

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final h = widget.hub;
    final id = _id;
    final role = ref.watch(myEventRoleProvider(id)).value ?? EventRole.none;
    final views = eventViewsFor(role: role, hub: h);
    final view = currentEventView(ref.watch(eventViewChoiceProvider), id, views);
    final tabs = _tabsFor(view, role, h);
    _syncTabs(view, tabs);
    final current = tabs[_tabs!.index.clamp(0, tabs.length - 1)];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              key: _topKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BigHeader(detail: d),
                if (views.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: EventRoleSwitch(
                      key: const ValueKey('event-role-switch'),
                      views: views,
                      current: view,
                      onChanged: (v) => ref.read(eventViewChoiceProvider.notifier).set(id, v),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          if (tabs.length > 1)
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabsHeader(controller: _tabs!, tabs: tabs),
            ),
          ..._content(view, current, role, d, h),
          const SliverToBoxAdapter(child: SafeArea(top: false, child: SizedBox(height: 16))),
        ],
      ),
    );
  }

  List<Widget> _content(EventView view, _Tab tab, EventRole role, EventDetail d, EventHub h) {
    final id = _id;
    switch (view) {
      case EventView.attendee:
        return switch (tab.id) {
          'floorPlan' => [SliverToBoxAdapter(child: FloorplanPreview(eventId: id))],
          'exhibitors' => [ExhibitorsBody(eventId: id)],
          'schedule' => [ScheduleBody(eventId: id)],
          'activities' => [
              if (h.stampStops > 0) StampsBody(eventId: id, scanButton: true),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList.list(
                  children: [
                    if (h.contestId != null) ...[_VoteCard(eventId: id, hub: h), const SizedBox(height: 12)],
                    LuckyDrawCard(eventId: id),
                  ],
                ),
              ),
            ],
          _ => [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList.list(children: _overview(d, h)),
              ),
            ],
        };
      case EventView.organizer:
        if (tab.id == 'verify') return [SliverToBoxAdapter(child: _VerifyPitch(eventId: id))];
        final group = OrganizerGroup.values.firstWhere((g) => g.name == tab.id, orElse: () => OrganizerGroup.door);
        if (group == OrganizerGroup.dashboard) return [ExpoDashboardBody(key: ValueKey('dash-$id'), eventId: id)];
        final draws = ref.watch(eventDrawsProvider(id)).value ?? const <LuckyDraw>[];
        final tools = organizerTools(group, eventId: id, role: role, event: d.event, draws: draws);
        // The small print sits with what it's about: crew under the door
        // tools, the draw rules under the program.
        final note = (role.isCrewOnly && group == OrganizerGroup.door) || (!role.isCrewOnly && group == OrganizerGroup.program);
        return [
          SliverList.list(
            children: [
              const SizedBox(height: 4),
              for (final t in tools) OrganizerToolTile(tool: t),
              if (note)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Text(organizerFootnote(role), style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
                ),
            ],
          ),
        ];
      case EventView.booth:
        final booth = h.myBooths.firstWhere((b) => b.id == tab.id, orElse: () => h.myBooths.first);
        return [
          SliverToBoxAdapter(child: _BoothHeader(eventId: id, booth: booth, onPlan: h.levels > 0)),
          LeadsBody(key: ValueKey('leads-${booth.id}'), eventId: id, exhibitorId: booth.id, boothName: booth.name),
        ];
    }
  }

  /// Overview: my status (pass or how to check in), Join, the lucky draw,
  /// the event chat, about, the map and who's going.
  List<Widget> _overview(EventDetail d, EventHub h) {
    final e = d.event;
    final a = widget.actions;
    final me = ref.watch(currentUserIdProvider);
    final host = e.organizerId == me;
    final open = !e.isPast && !e.isCancelled;
    final nudge = h.registration.open && h.registration.required && (h.checkedIn || d.isAttending);
    const gap = SizedBox(height: 12);
    return [
      if (h.checkedIn)
        _PassStrip(eventId: e.id, hub: h)
      else if (e.isLive)
        _CheckInCard(key: widget.guide.checkIn, detail: d, busy: a.checkInBusy, onCheckIn: a.checkIn, big: true)
      else if (open)
        const _HowToCheckIn(),
      if (nudge) ...[gap, RegistrationNudge(eventId: e.id, questions: h.registration.questions)],
      if (open) ...[
        gap,
        Row(
          children: [
            Expanded(child: _RsvpButton(key: widget.guide.rsvp, detail: d, busy: a.rsvpBusy, onPressed: a.rsvp)),
            const SizedBox(width: 8),
            _BookmarkButton(on: d.isBookmarked, onTap: a.bookmarkBusy ? null : a.bookmark),
          ],
        ),
        if (d.isAttending) BringingCarRow(eventId: e.id),
      ],
      gap,
      LuckyDrawCard(eventId: e.id),
      if (d.isAttending || host) ...[
        SecondaryButton(key: widget.guide.chat, label: 'Event chat', icon: AppIcons.chatCircle, onPressed: a.chat),
        gap,
      ],
      if ((e.description ?? '').trim().isNotEmpty) ...[
        const _SectionLabel('About'),
        const SizedBox(height: 6),
        Text(e.description!.trim(), style: const TextStyle(fontSize: 15, height: 1.5)),
        const SizedBox(height: 20),
      ],
      GestureDetector(
        onTap: () => openDirections(context, lat: e.lat, lng: e.lng, label: e.venueName),
        child: _MapPreview(event: e),
      ),
      const SizedBox(height: 16),
      _Attendees(detail: d),
      const SizedBox(height: 8),
    ];
  }
}

/// Cover, kind badge, name, dates, venue (tap: directions), organizer.
class _BigHeader extends ConsumerWidget {
  const _BigHeader({required this.detail});
  final EventDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = detail.event;
    final km = distanceKm(ref.watch(mapOriginProvider), e.latLng);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Cover(event: e, aspectRatio: 16 / 9),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Badges(event: e, big: true),
              const SizedBox(height: 10),
              Text(e.title, style: AppText.sectionTitle.copyWith(fontSize: 24, height: 1.15)),
              const SizedBox(height: 12),
              _InfoRow(icon: AppIcons.calendarBlank, text: formatEventSpan(e.startsAt, e.endsAt)),
              const SizedBox(height: 8),
              InkWell(
                key: const ValueKey('event-venue'),
                onTap: () => openDirections(context, lat: e.lat, lng: e.lng, label: e.venueName),
                onLongPress: () => openDirections(context, lat: e.lat, lng: e.lng, label: e.venueName, choose: true),
                child: _InfoRow(
                  icon: AppIcons.mapPin,
                  text: '${e.venueName} · ${formatDistance(km)}',
                  trailing: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(AppIcons.navigationArrow, size: 18, color: AppColors.textSecondary, semanticLabel: 'Directions'),
                  ),
                ),
              ),
              if (e.address != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 2, 0, 0),
                  child: Text(e.address!, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
                ),
              if (e.clubId != null) ...[
                const SizedBox(height: 8),
                _ClubRow(clubId: e.clubId!),
              ],
              if (e.vendorName != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: e.vendorId == null ? null : () => context.push(Routes.partner(e.vendorId!)),
                  child: _InfoRow(icon: AppIcons.storefront, text: 'Hosted by ${e.vendorName}', trailing: Icon(AppIcons.caretRight, size: 20, color: AppColors.textMuted)),
                ),
              ],
              const SizedBox(height: 12),
              _OrganizerTile(organizer: detail.organizer),
            ],
          ),
        ),
      ],
    );
  }
}

/// The pinned tab strip. Scrolls sideways when the tabs don't fit.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader({required this.controller, required this.tabs});
  final TabController controller;
  final List<_Tab> tabs;

  static const height = 48.0;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: height,
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      child: TabBar(
        key: const ValueKey('event-tabs'),
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.brand,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 2.5,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        tabs: [for (final t in tabs) Tab(key: ValueKey('tab-${t.id}'), text: t.label)],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.controller != controller || old.tabs != tabs;
}

/// Checked in: my entry number and the way to my pass.
class _PassStrip extends ConsumerWidget {
  const _PassStrip({required this.eventId, required this.hub});
  final String eventId;
  final EventHub hub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final car = hub.car?.title;
    return Container(
      key: const ValueKey('pass-strip'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(AppIcons.ticket, size: 18, color: Colors.white70),
              const SizedBox(width: 6),
              const Expanded(
                child: Text("YOU'RE IN", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white70)),
              ),
              const Icon(AppIcons.checkCircleFill, size: 18, color: AppColors.success),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hub.entry ?? 'Checked in',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: AppFonts.display, fontSize: 40, height: 1.05, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          Text(
            car == null ? 'Your entry and lucky draw number' : 'Entry and lucky draw number · $car',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.3),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
            onPressed: () => context.push(ExpoRoutes.pass(eventId)),
            icon: const Icon(AppIcons.qrCode, size: 18),
            label: const Text('Show pass'),
          ),
        ],
      ),
    );
  }
}

/// Before the day: how checking in works.
class _HowToCheckIn extends StatelessWidget {
  const _HowToCheckIn();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('how-to-check-in'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(AppIcons.scan, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('How to check in', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    'On the day, scan the QR at the entrance with TT Spot. You get your pass and a lucky draw number.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Activities: the open show car vote.
class _VoteCard extends StatelessWidget {
  const _VoteCard({required this.eventId, required this.hub});
  final String eventId;
  final EventHub hub;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          leading: const Icon(AppIcons.trophy),
          title: Text(hub.contestTitle ?? 'Show car vote', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('Show car vote. One vote per checked-in member.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          trailing: const Icon(AppIcons.caretRight),
          onTap: () => context.push(ExpoRoutes.vote(eventId, contestId: hub.contestId)),
        ),
      );
}

/// Booth view: my booth's name, scan a pass, find it on the plan.
class _BoothHeader extends StatelessWidget {
  const _BoothHeader({required this.eventId, required this.booth, required this.onPlan});
  final String eventId;
  final HubBooth booth;
  final bool onPlan;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(booth.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 12),
            PrimaryButton(label: 'Scan a pass', icon: AppIcons.scan, onPressed: () => context.push(Routes.scan)),
            if (onPlan) ...[
              const SizedBox(height: 8),
              SecondaryButton(label: 'My booth on the floor plan', icon: AppIcons.mapTrifold, onPressed: () => context.push(ExpoRoutes.floorplanAt(eventId, booth.id))),
            ],
          ],
        ),
      );
}

/// Organizer view while the host isn't a verified organizer yet.
class _VerifyPitch extends StatelessWidget {
  const _VerifyPitch({required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TitiSays('Organizer tools are for verified organizers. Apply once and they unlock on every event you host.', pose: TitiPose.thumbsUp),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Apply to be an organizer', onPressed: () => context.push(Routes.organizerApply)),
          ],
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700));
}
