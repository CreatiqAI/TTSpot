import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/directions/directions.dart';
import '../../../../core/geo/latlng.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/open_external.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/share_options_sheet.dart';
import '../../../../core/widgets/thumb_image.dart';
import '../../../events/domain/event.dart';
import '../../../map/presentation/widgets/static_pin_map.dart';
import '../../../social/presentation/widgets/video_badge.dart';
import '../../../social/domain/follow.dart';
import '../../../social/domain/post.dart';
import '../../domain/vendor.dart';
import '../../../guides/map_guides.dart';
import 'hours_editor.dart';
import 'product_sheet.dart';

/// The pages of a partner's page, in tab order. `name` is the `?tab=` value.
enum PartnerTab {
  info('Info', AppIcons.info),
  products('Products', AppIcons.shoppingBag),
  vouchers('Vouchers', AppIcons.ticket),
  posts('Posts', AppIcons.images),
  events('Events', AppIcons.calendarBlank);

  const PartnerTab(this.label, this.icon);
  final String label;
  final IconData icon;

  /// 'info' | 'products' | 'vouchers' | 'posts' | 'events', else null.
  static PartnerTab? parse(String? name) => name == null ? null : PartnerTab.values.asNameMap()[name];
}

/// A partner's page: the cover collapses into a bar with the name, the shop's
/// identity (logo, chips, Message / WhatsApp / Directions) scrolls away, and
/// the tab bar pins under the bar. Each tab is its own swipeable page with
/// its own scroll, empty state and pull-to-refresh.
///
/// Pure view: [PartnerScreen] feeds it from the providers. A null list means
/// it is still loading.
class PartnerPageView extends StatefulWidget {
  const PartnerPageView({
    super.key,
    required this.vendor,
    required this.products,
    required this.vouchers,
    required this.posts,
    required this.events,
    this.initialTab,
    this.onMessage,
    this.onRefresh,
    this.following,
    this.followers,
    this.onFollow,
    this.guideKeys,
  });

  final PublicVendor vendor;
  final List<Product>? products;

  /// This partner's vouchers only.
  final List<Voucher>? vouchers;
  final List<FeedPost>? posts;
  final List<Event>? events;

  /// See [PartnerTab.parse].
  final String? initialTab;

  /// Null disables Message (the owner looking at their own page).
  final VoidCallback? onMessage;

  /// Pull-to-refresh on a tab; completes when that tab's data is fresh.
  final Future<void> Function(PartnerTab tab)? onRefresh;

  /// Am I following the shop? Null while that loads (Follow is greyed out).
  final bool? following;

  /// How many follow the shop; shown as a chip once there are any.
  final int? followers;

  /// Follow / Following beside Message. Null hides it (the partner's own
  /// page).
  final VoidCallback? onFollow;

  /// What TiTi's first-visit tour spotlights (Follow, the tabs, Directions).
  final PartnerGuideKeys? guideKeys;

  @override
  State<PartnerPageView> createState() => _PartnerPageViewState();
}

class _PartnerPageViewState extends State<PartnerPageView> with TickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: PartnerTab.values.length, vsync: this, initialIndex: (PartnerTab.parse(widget.initialTab) ?? PartnerTab.info).index);
  }

  @override
  void didUpdateWidget(covariant PartnerPageView old) {
    super.didUpdateWidget(old);
    // Same page reopened on another tab (e.g. ?tab=vouchers): move there.
    final tab = PartnerTab.parse(widget.initialTab);
    if (old.initialTab != widget.initialTab && tab != null && tab.index != _tabs.index) _tabs.animateTo(tab.index);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  int _count(PartnerTab t) => switch (t) {
        PartnerTab.info => 0,
        PartnerTab.products => widget.products?.length ?? 0,
        PartnerTab.vouchers => widget.vouchers?.length ?? 0,
        PartnerTab.posts => widget.posts?.length ?? 0,
        PartnerTab.events => widget.events?.length ?? 0,
      };

  @override
  Widget build(BuildContext context) {
    final v = widget.vendor;
    // The tab bar grows with the text size so big labels never clip.
    final barExtent = math.max(48.0, MediaQuery.textScalerOf(context).scale(15) + 30);
    // What stays pinned over the pages: status bar + collapsed bar + tabs.
    final pinned = MediaQuery.paddingOf(context).top + kToolbarHeight + barExtent;

    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverOverlapAbsorber(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          sliver: _PinnedGroup(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 200,
                backgroundColor: AppColors.bg,
                surfaceTintColor: Colors.transparent,
                automaticallyImplyLeading: false,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _RoundButton(icon: AppIcons.arrowLeft, label: 'Back', onTap: () => context.pop()),
                ),
                title: _CollapsedTitle(v.name),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _RoundButton(icon: AppIcons.shareFat, label: 'Share', onTap: () => showShareOptions(context, ShareItem(type: 'partner', id: v.id, title: v.name))),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(collapseMode: CollapseMode.parallax, background: _Cover(v: v)),
              ),
              SliverToBoxAdapter(child: _Identity(v: v, onMessage: widget.onMessage, following: widget.following, followers: widget.followers, onFollow: widget.onFollow, guideKeys: widget.guideKeys)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  extent: barExtent,
                  bar: TabBar(
                    key: widget.guideKeys?.tabs,
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(width: 3, color: AppColors.brand),
                      borderRadius: BorderRadius.circular(3),
                      insets: const EdgeInsets.symmetric(horizontal: 1),
                    ),
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorWeight: 3,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    dividerColor: Colors.transparent,
                    dividerHeight: 0,
                    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                    splashFactory: NoSplash.splashFactory,
                    tabs: [
                      for (final t in PartnerTab.values) Tab(height: barExtent - 3, child: _TabLabel(label: t.label, count: _count(t))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final t in PartnerTab.values)
            _TabPage(
              tab: t,
              edgeOffset: pinned,
              onRefresh: () => widget.onRefresh?.call(t) ?? Future<void>.value(),
              slivers: switch (t) {
                PartnerTab.info => _info(context),
                PartnerTab.products => _products(context),
                PartnerTab.vouchers => _vouchers(context),
                PartnerTab.posts => _posts(context),
                PartnerTab.events => _events(context),
              },
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ pages

  Widget _bottom(BuildContext context) => SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24));

  Widget _loading() => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));

  Widget _empty(BuildContext context, PartnerTab tab, String text) => SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 24, 32, MediaQuery.paddingOf(context).bottom + 24),
          child: Center(child: _EmptyTab(icon: tab.icon, text: text)),
        ),
      );

  List<Widget> _info(BuildContext context) {
    final v = widget.vendor;
    final hours = OpeningHours.fromJson(v.hoursJson);
    final status = hours.status();
    final open = status != null && status.startsWith('Open');
    final hasLocation = v.lat != null && v.lng != null;
    final digits = _digits(v.phone);
    final about = (v.description ?? '').trim();
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
        sliver: SliverList.list(
          children: [
            if (about.isNotEmpty) _SectionCard(title: 'About', child: Text(about, style: TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textPrimary))),
            _SectionCard(
              title: 'Hours',
              child: hours.isEmpty
                  ? _InfoRow(icon: AppIcons.clock, title: 'Hours not listed yet', subtitle: 'Message the shop before you head over.')
                  : _HoursRow(hours: hours, status: status!, open: open),
            ),
            if (v.address != null || hasLocation)
              _SectionCard(
                title: 'Address',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (v.address != null) _InfoRow(icon: AppIcons.mapPin, title: v.address!),
                    if (hasLocation) ...[
                      if (v.address != null) const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: SizedBox(height: 150, child: StaticPinMap(points: [LatLng(v.lat!, v.lng!)], zoom: 15)),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MiniButton(label: 'Waze', icon: AppIcons.navigationArrow, onTap: () => launchDirections(context, DirectionsApp.waze, v.lat!, v.lng!)),
                          _MiniButton(label: 'Google Maps', icon: AppIcons.mapTrifold, onTap: () => launchDirections(context, DirectionsApp.google, v.lat!, v.lng!)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            _SectionCard(
              title: 'Contact',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (digits.isNotEmpty) ...[
                    _InfoRow(icon: AppIcons.phone, title: v.phone!.trim()),
                    const SizedBox(height: 10),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniButton(label: 'Message', icon: AppIcons.chatCircle, onTap: widget.onMessage),
                      if (digits.isNotEmpty) _MiniButton(label: 'WhatsApp', icon: AppIcons.whatsappLogo, onTap: () => _whatsApp(context, digits)),
                    ],
                  ),
                ],
              ),
            ),
            if (v.placeId != null)
              _SectionCard(
                child: _InfoRow(
                  icon: AppIcons.checkCircle,
                  title: 'Check in when you visit',
                  subtitle: 'Earn points and show up under "recently here".',
                  trailing: _MiniButton(label: 'Check in', onTap: () => context.push(Routes.place(v.placeId!))),
                ),
              ),
          ],
        ),
      ),
      _bottom(context),
    ];
  }

  List<Widget> _products(BuildContext context) {
    final list = widget.products;
    if (list == null) return [_loading()];
    if (list.isEmpty) return [_empty(context, PartnerTab.products, 'Nothing listed yet. Message the shop for what they stock.')];
    final vouchers = widget.vouchers ?? const <Voucher>[];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 12, childAspectRatio: 0.6),
          itemCount: list.length,
          itemBuilder: (context, i) => ProductCard(
            product: list[i],
            voucherCount: vouchers.where((x) => x.productId == list[i].id).length,
            onTap: () => showProductSheet(context, product: list[i], vendor: widget.vendor),
          ),
        ),
      ),
      _bottom(context),
    ];
  }

  List<Widget> _vouchers(BuildContext context) {
    final list = widget.vouchers;
    if (list == null) return [_loading()];
    if (list.isEmpty) return [_empty(context, PartnerTab.vouchers, 'No vouchers right now. Check back after the next meet.')];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _SectionCard(
            child: _Divided(
              children: [
                for (final x in list)
                  _Tile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: ArtIcon(kVoucherAsset, size: 26)),
                    ),
                    title: '${x.headline} · ${x.title}',
                    subtitle: '${x.pointsCost == 0 ? 'Free to claim' : '${x.pointsCost} points'}${x.productName == null ? '' : ' · for ${x.productName}'}',
                    onTap: () => context.push(Routes.rewards),
                  ),
              ],
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Center(child: TextButton(onPressed: () => context.push(Routes.rewards), child: const Text('See all in Rewards'))),
        ),
      ),
      _bottom(context),
    ];
  }

  List<Widget> _posts(BuildContext context) {
    final list = widget.posts;
    if (list == null) return [_loading()];
    if (list.isEmpty) return [_empty(context, PartnerTab.posts, 'Nothing posted yet.')];
    return [
      SliverPadding(
        padding: const EdgeInsets.only(top: 2),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final p = list[i].post;
            return GestureDetector(
              onTap: () => context.push(Routes.post(p.id)),
              child: p.photoUrls.isEmpty
                  ? Container(
                      color: AppColors.surfaceGray,
                      padding: const EdgeInsets.all(10),
                      alignment: Alignment.bottomLeft,
                      child: Text(p.title ?? p.caption ?? 'Post', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        ThumbImage(p.photoUrls.first),
                        if (p.isVideo) const Positioned(right: 6, top: 6, child: VideoBadge(compact: true)),
                      ],
                    ),
            );
          },
        ),
      ),
      _bottom(context),
    ];
  }

  List<Widget> _events(BuildContext context) {
    final list = widget.events;
    if (list == null) return [_loading()];
    if (list.isEmpty) return [_empty(context, PartnerTab.events, 'Nothing planned here yet.')];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _SectionCard(
            child: _Divided(
              children: [
                for (final e in list)
                  _Tile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(width: 44, height: 44, child: e.coverUrl == null ? Image.asset(e.defaultCover, fit: BoxFit.cover, cacheWidth: 150) : ThumbImage(e.coverUrl!)),
                    ),
                    title: e.title,
                    subtitle: '${formatEventDateFriendly(e.startsAt)} · ${e.venueName}',
                    onTap: () => context.push(Routes.event(e.id)),
                  ),
              ],
            ),
          ),
        ),
      ),
      _bottom(context),
    ];
  }
}

String _digits(String? phone) => (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

void _whatsApp(BuildContext context, String digits) => openExternal(context, 'whatsapp://send?phone=$digits', fallbackUrl: 'https://wa.me/$digits', appName: 'WhatsApp');

/// One tab's page: its own scroll (kept per tab), the pinned header's space,
/// and pull-to-refresh.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.tab, required this.edgeOffset, required this.onRefresh, required this.slivers});
  final PartnerTab tab;
  final double edgeOffset;
  final Future<void> Function() onRefresh;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (ctx) => RefreshIndicator(
          edgeOffset: edgeOffset,
          color: AppColors.brand,
          backgroundColor: AppColors.surface,
          onRefresh: onRefresh,
          child: CustomScrollView(
            key: PageStorageKey<String>('partner-${tab.name}'),
            primary: true,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx)),
              ...slivers,
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------- header

/// A [SliverMainAxisGroup] that reports the pinned bars inside it (the
/// collapsed app bar and the tab bar) as its scroll obstruction. Wrapped in
/// one [SliverOverlapAbsorber], the tab pages then start right under both
/// bars instead of sliding beneath the app bar.
class _PinnedGroup extends SliverMainAxisGroup {
  const _PinnedGroup({required super.slivers});

  @override
  RenderSliverMainAxisGroup createRenderObject(BuildContext context) => _RenderPinnedGroup();
}

class _RenderPinnedGroup extends RenderSliverMainAxisGroup {
  @override
  void performLayout() {
    super.performLayout();
    final g = geometry!;
    if (g.scrollOffsetCorrection != null) return;
    var pinned = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      pinned += c.geometry!.maxScrollObstructionExtent;
    }
    geometry = g.copyWith(maxScrollObstructionExtent: pinned);
  }
}

/// The partner's name in the bar, only once the cover has fully collapsed.
class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final collapsed = s != null && s.currentExtent <= s.minExtent + 1;
    return ExcludeSemantics(
      excluding: !collapsed,
      child: AnimatedOpacity(
        opacity: collapsed ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ),
    );
  }
}

/// Cover: shop photos as a swipeable strip; without photos, a stock photo for
/// the partner's type so the top never looks empty.
class _Cover extends StatelessWidget {
  const _Cover({required this.v});
  final PublicVendor v;

  static const _shade = IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x55000000), Color(0x00000000), Color(0x22000000)])),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (v.photoUrls.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          PageView(children: [for (final u in v.photoUrls) Image(image: CachedNetworkImageProvider(u), fit: BoxFit.cover)]),
          _shade,
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          partnerCoverAsset(v.type),
          fit: BoxFit.cover,
          cacheWidth: 1200,
          errorBuilder: (_, _, _) => v.logoUrl != null
              ? ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: Image(image: CachedNetworkImageProvider(v.logoUrl!), fit: BoxFit.cover))
              : const ColoredBox(color: AppColors.ink),
        ),
        _shade,
      ],
    );
  }
}

/// Logo, name, chips and the main actions. Grows with the text; nothing in
/// here has a fixed text height.
class _Identity extends StatelessWidget {
  const _Identity({required this.v, required this.onMessage, this.following, this.followers, this.onFollow, this.guideKeys});
  final PartnerGuideKeys? guideKeys;
  final PublicVendor v;
  final VoidCallback? onMessage;
  final bool? following;
  final int? followers;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final status = OpeningHours.fromJson(v.hoursJson).status();
    final open = status != null && status.startsWith('Open');
    final hasLocation = v.lat != null && v.lng != null;
    final digits = _digits(v.phone);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3))]),
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: v.logoUrl == null
                      ? ColoredBox(color: AppColors.surfaceGray, child: Padding(padding: const EdgeInsets.all(10), child: Image.asset(kindIconAsset(v.type), fit: BoxFit.contain)))
                      : Image(image: CachedNetworkImageProvider(v.logoUrl!), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.name, style: TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w700, height: 1, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(icon: AppIcons.storefront, text: businessTypeLabel(v.type)),
                        _Chip(icon: AppIcons.sealCheck, text: 'Partner', red: true),
                        if (status != null) _Chip(icon: AppIcons.clock, text: open ? 'Open now' : 'Closed', green: open),
                        if ((followers ?? 0) > 0) _Chip(icon: AppIcons.users, text: followersLabel(followers!)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (onFollow == null)
            PrimaryButton(label: 'Message', onPressed: onMessage)
          else
            // Follow is the red one; once followed both are grey, like Instagram.
            Row(
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: guideKeys?.follow,
                    child: following == true
                        ? SecondaryButton(label: 'Following', icon: AppIcons.check, onPressed: onFollow)
                        : PrimaryButton(label: 'Follow', icon: AppIcons.plus, onPressed: following == null ? null : onFollow),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: SecondaryButton(label: 'Message', icon: AppIcons.chatCircle, onPressed: onMessage)),
              ],
            ),
          if (digits.isNotEmpty || hasLocation) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (digits.isNotEmpty) Expanded(child: SecondaryButton(label: 'WhatsApp', icon: AppIcons.whatsappLogo, onPressed: () => _whatsApp(context, digits))),
                if (digits.isNotEmpty && hasLocation) const SizedBox(width: 8),
                if (hasLocation)
                  Expanded(
                    child: SecondaryButton(
                      key: guideKeys?.directions,
                      label: 'Directions',
                      icon: AppIcons.navigationArrow,
                      onPressed: () => openDirections(context, lat: v.lat!, lng: v.lng!, label: v.name),
                      onLongPress: () => openDirections(context, lat: v.lat!, lng: v.lng!, label: v.name, choose: true),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The pinned tab bar: page colour, hairline under it, height that follows
/// the text size.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate({required this.extent, required this.bar});
  final double extent;
  final Widget bar;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
          child: Align(alignment: Alignment.bottomLeft, child: bar),
        ),
      );

  // Counts and colours (AppColors flips with the theme) live in [bar].
  @override
  bool shouldRebuild(_TabBarDelegate old) => true;
}

/// "Vouchers 3": the count pill takes the label's current colour, so it
/// follows the selected / unselected animation.
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color ?? AppColors.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
            child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, height: 1.3, color: color)),
          ),
        ],
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: Colors.black.withValues(alpha: 0.45),
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 20, color: Colors.white))),
          ),
        ),
      );
}

// ---------------------------------------------------------------- pieces

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary)),
        ],
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({this.title, required this.child});
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      );
}

/// Rows with a hairline between them.
class _Divided extends StatelessWidget {
  const _Divided({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 9, thickness: 0.5, indent: 56, color: AppColors.divider),
            children[i],
          ],
        ],
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, this.subtitle, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 18, color: AppColors.textSecondary)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary)),
                if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      );
}

/// Today's status, and the whole week on tap.
class _HoursRow extends StatefulWidget {
  const _HoursRow({required this.hours, required this.status, required this.open});
  final OpeningHours hours;
  final String status;
  final bool open;

  @override
  State<_HoursRow> createState() => _HoursRowState();
}

class _HoursRowState extends State<_HoursRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final dayWidth = MediaQuery.textScalerOf(context).scale(44);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(AppIcons.clock, size: 18, color: widget.open ? AppColors.success : AppColors.textSecondary)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.status, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: widget.open ? AppColors.success : AppColors.textSecondary)),
                    Text(widget.hours.summary, maxLines: _expanded ? null : 1, overflow: _expanded ? null : TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(_expanded ? AppIcons.caretUp : AppIcons.caretDown, size: 16, color: AppColors.textMuted),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 0, 0),
              child: Column(
                children: [
                  for (final d in kDays)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(minWidth: dayWidth),
                            child: Text(kDayLabels[d]!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.hours.days[d] == null ? 'Closed' : '${OpeningHours.fmt(widget.hours.days[d]!.open)} – ${OpeningHours.fmt(widget.hours.days[d]!.close)}',
                              style: TextStyle(fontSize: 13.5, color: widget.hours.days[d] == null ? AppColors.textSecondary : AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Small grey pill button. Null [onTap] greys it out.
class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null ? AppColors.textMuted : AppColors.textPrimary;
    return Material(
      color: AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.leading, required this.title, required this.subtitle, required this.onTap});
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.textPrimary)),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.red = false, this.green = false});
  final IconData icon;
  final String text;
  final bool red;
  final bool green;

  @override
  Widget build(BuildContext context) {
    final color = red ? AppColors.brand : green ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: red || green ? color.withValues(alpha: 0.1) : AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
        ],
      ),
    );
  }
}
