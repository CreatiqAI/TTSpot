import 'dart:ui' show ImageFilter;

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
import '../../../core/utils/open_external.dart';
import '../../../core/widgets/primary_button.dart';
import '../../events/domain/event.dart';
import '../../social/application/chat_providers.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/post.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';
import 'widgets/hours_editor.dart';
import 'widgets/product_sheet.dart';

/// A partner's page for members. Cover + logo on top, then sections you can
/// jump to from the sticky chip bar: Info · Products · Vouchers · Posts ·
/// Events. Everything a member needs to visit, buy or message the shop.
class PartnerScreen extends ConsumerWidget {
  const PartnerScreen({super.key, required this.vendorId});
  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendor = ref.watch(vendorPublicProvider(vendorId));
    final me = ref.watch(currentUserIdProvider);
    return Scaffold(
      body: vendor.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (v) => v == null ? const Center(child: Text('This partner is no longer on TT Spot.')) : _Body(v: v, me: me),
      ),
    );
  }
}

enum _Section { info, products, vouchers, posts, events }

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.v, required this.me});
  final PublicVendor v;
  final String? me;
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _scroll = ScrollController();
  final _viewKey = GlobalKey();
  final _keys = {for (final s in _Section.values) s: GlobalKey()};
  _Section _active = _Section.info;
  bool _jumping = false;
  static const _chipBar = 52.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  double? _topOf(_Section s) {
    final ctx = _keys[s]!.currentContext;
    final view = _viewKey.currentContext?.findRenderObject();
    if (ctx == null || view == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: view).dy;
  }

  double get _stickyBottom => MediaQuery.paddingOf(context).top + kToolbarHeight + _chipBar;

  void _onScroll() {
    if (_jumping) return;
    _Section current = _Section.info;
    for (final s in _Section.values) {
      final top = _topOf(s);
      if (top != null && top <= _stickyBottom + 24) current = s;
    }
    if (current != _active) setState(() => _active = current);
  }

  Future<void> _jump(_Section s) async {
    final top = _topOf(s);
    if (top == null) return;
    setState(() { _active = s; _jumping = true; });
    final target = (_scroll.offset + top - _stickyBottom - 8).clamp(0.0, _scroll.position.maxScrollExtent);
    await _scroll.animateTo(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    if (mounted) setState(() => _jumping = false);
  }

  Future<void> _message() async {
    try {
      final id = await ref.read(chatActionsProvider).openVendorDm(widget.v.id);
      if (mounted) context.push(Routes.chat(id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    ref.watch(partnerViewedProvider(v.id));
    final hours = OpeningHours.fromJson(v.hoursJson);
    final status = hours.status();
    final open = status != null && status.startsWith('Open');
    final posts = ref.watch(postsWhereProvider((column: 'vendor_id', value: v.id))).value ?? const <FeedPost>[];
    final products = ref.watch(partnerProductsProvider(v.id)).value ?? const <Product>[];
    final vouchers = (ref.watch(shopVouchersProvider).value ?? const <Voucher>[]).where((x) => x.vendorId == v.id).toList();
    final events = ref.watch(vendorEventsProvider(v.id)).value ?? const <Event>[];
    final hasLocation = v.lat != null && v.lng != null;
    final digits = (v.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    return CustomScrollView(
      key: _viewKey,
      controller: _scroll,
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 220,
          backgroundColor: AppColors.bg,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _RoundButton(icon: AppIcons.arrowLeft, onTap: () => context.pop()),
          ),
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: _Cover(v: v),
          ),
        ),

        // ---- identity: logo, name, chips, actions
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                            ? const ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.storefront, size: 30, color: AppColors.textSecondary))
                            : Image.network(v.logoUrl!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.name, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w700, height: 1)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _Chip(icon: AppIcons.storefront, text: businessTypeLabel(v.type)),
                              const _Chip(icon: AppIcons.sealCheck, text: 'Partner', red: true),
                              if (status != null) _Chip(icon: AppIcons.clock, text: open ? 'Open now' : 'Closed', green: open),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: PrimaryButton(label: 'Message', onPressed: v.ownerIsMe(widget.me) ? null : _message)),
                    if (digits.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(child: SecondaryButton(label: 'WhatsApp', icon: AppIcons.whatsappLogo, onPressed: () => openExternal(context, 'whatsapp://send?phone=$digits', fallbackUrl: 'https://wa.me/$digits', appName: 'WhatsApp'))),
                    ],
                    if (hasLocation) ...[
                      const SizedBox(width: 8),
                      Material(
                        color: AppColors.surfaceGray,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          onTap: () => openExternal(context, 'waze://?ll=${v.lat},${v.lng}&navigate=yes', fallbackUrl: wazeUrl(v.lat!, v.lng!), appName: 'Waze'),
                          child: const SizedBox(width: 52, height: 48, child: Icon(AppIcons.navigationArrow, size: 20)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // ---- sticky section chips
        SliverPersistentHeader(
          pinned: true,
          delegate: _ChipBar(
            height: _chipBar,
            active: _active,
            counts: {_Section.products: products.length, _Section.vouchers: vouchers.length, _Section.posts: posts.length, _Section.events: events.length},
            onTap: _jump,
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- INFO
                _SectionCard(
                  key: _keys[_Section.info],
                  title: 'About',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((v.description ?? '').trim().isNotEmpty) ...[
                        Text(v.description!.trim(), style: const TextStyle(fontSize: 14.5, height: 1.5)),
                        const Divider(height: 22),
                      ],
                      if (v.address != null) _InfoRow(icon: AppIcons.mapPin, title: v.address!),
                      if (hasLocation)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 6, 0, 4),
                          child: Row(
                            children: [
                              _MiniButton(label: 'Waze', icon: AppIcons.navigationArrow, onTap: () => openExternal(context, 'waze://?ll=${v.lat},${v.lng}&navigate=yes', fallbackUrl: wazeUrl(v.lat!, v.lng!), appName: 'Waze')),
                              const SizedBox(width: 8),
                              _MiniButton(label: 'Google Maps', icon: AppIcons.mapTrifold, onTap: () => openExternal(context, 'comgooglemaps://?daddr=${v.lat},${v.lng}', fallbackUrl: googleMapsUrl(v.lat!, v.lng!), appName: 'Google Maps')),
                            ],
                          ),
                        ),
                      if (v.address != null) const SizedBox(height: 8),
                      if (hours.isEmpty)
                        const _InfoRow(icon: AppIcons.clock, title: 'Hours not listed yet')
                      else
                        _HoursRow(hours: hours, status: status!, open: open),
                      if (v.placeId != null) ...[
                        const SizedBox(height: 8),
                        _InfoRow(
                          icon: AppIcons.checkCircle,
                          title: 'Check in when you visit',
                          subtitle: 'Earn points and show up under "recently here".',
                          trailing: _MiniButton(label: 'Check in', onTap: () => context.push(Routes.place(v.placeId!))),
                        ),
                      ],
                    ],
                  ),
                ),

                // ---- PRODUCTS
                _SectionCard(
                  key: _keys[_Section.products],
                  title: 'Products',
                  count: products.length,
                  child: products.isEmpty
                      ? const _Muted('Nothing listed yet. Message the shop for what they stock.')
                      : GridView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 12, childAspectRatio: 0.6),
                          itemCount: products.length,
                          itemBuilder: (_, i) => ProductCard(
                            product: products[i],
                            voucherCount: vouchers.where((x) => x.productId == products[i].id).length,
                            onTap: () => showProductSheet(context, product: products[i], vendor: v),
                          ),
                        ),
                ),

                // ---- VOUCHERS
                _SectionCard(
                  key: _keys[_Section.vouchers],
                  title: 'Vouchers',
                  count: vouchers.length,
                  action: vouchers.isEmpty ? null : ('Rewards', () => context.push(Routes.rewards)),
                  child: vouchers.isEmpty
                      ? const _Muted('No vouchers right now. Check back after the next meet.')
                      : Column(
                          children: [
                            for (final x in vouchers)
                              _Tile(
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                                  child: const Center(child: ArtIcon(AppArt.ticket, size: 26)),
                                ),
                                title: '${x.headline} · ${x.title}',
                                subtitle: '${x.pointsCost == 0 ? 'Free to claim' : '${x.pointsCost} points'}${x.productName == null ? '' : ' · for ${x.productName}'}',
                                onTap: () => context.push(Routes.rewards),
                              ),
                          ],
                        ),
                ),

                // ---- POSTS
                _SectionCard(
                  key: _keys[_Section.posts],
                  title: 'Posts',
                  count: posts.length,
                  child: posts.isEmpty
                      ? const _Muted('Nothing posted yet.')
                      : SizedBox(
                          height: 110,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: posts.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final f = posts[i];
                              return GestureDetector(
                                onTap: () => context.push(Routes.post(f.post.id)),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 110,
                                    height: 110,
                                    child: f.post.photoUrls.isEmpty
                                        ? Container(
                                            color: AppColors.surfaceGray,
                                            padding: const EdgeInsets.all(10),
                                            alignment: Alignment.bottomLeft,
                                            child: Text(f.post.title ?? f.post.caption ?? 'Post', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                          )
                                        : Image.network(f.post.photoUrls.first, fit: BoxFit.cover),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),

                // ---- EVENTS
                _SectionCard(
                  key: _keys[_Section.events],
                  title: 'Events',
                  count: events.length,
                  child: events.isEmpty
                      ? const _Muted('Nothing planned here yet.')
                      : Column(
                          children: [
                            for (final e in events)
                              _Tile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(width: 44, height: 44, child: e.coverUrl == null ? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(e.type.art, size: 24))) : Image.network(e.coverUrl!, fit: BoxFit.cover)),
                                ),
                                title: e.title,
                                subtitle: '${formatEventDateFriendly(e.startsAt)} · ${e.venueName}',
                                onTap: () => context.push(Routes.event(e.id)),
                              ),
                          ],
                        ),
                ),
                // Room so the last sections can scroll up under the chip bar.
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.45),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Cover: shop photos as a swipeable strip; without photos, the logo blurred
/// big behind a dark wash so the top never looks empty.
class _Cover extends StatelessWidget {
  const _Cover({required this.v});
  final PublicVendor v;
  @override
  Widget build(BuildContext context) {
    if (v.photoUrls.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          PageView(children: [for (final u in v.photoUrls) Image.network(u, fit: BoxFit.cover)]),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x55000000), Color(0x00000000), Color(0x22000000)])),
            ),
          ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (v.logoUrl != null) ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: Image.network(v.logoUrl!, fit: BoxFit.cover))
        else const ColoredBox(color: AppColors.ink),
        const DecoratedBox(decoration: BoxDecoration(color: Color(0x66000000))),
        Center(child: Icon(AppIcons.storefront, size: 44, color: Colors.white.withValues(alpha: 0.35))),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Center(
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 1,
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 20))),
        ),
      );
}

/// The pinned row of section chips.
class _ChipBar extends SliverPersistentHeaderDelegate {
  _ChipBar({required this.height, required this.active, required this.counts, required this.onTap});
  final double height;
  final _Section active;
  final Map<_Section, int> counts;
  final ValueChanged<_Section> onTap;

  static const _labels = {_Section.info: 'Info', _Section.products: 'Products', _Section.vouchers: 'Vouchers', _Section.posts: 'Posts', _Section.events: 'Events'};

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        height: height,
        decoration: const BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          children: [
            for (final s in _Section.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(counts[s] == null || counts[s] == 0 ? _labels[s]! : '${_labels[s]} · ${counts[s]}'),
                  selected: active == s,
                  onSelected: (_) => onTap(s),
                  showCheckmark: false,
                  selectedColor: AppColors.textPrimary,
                  backgroundColor: AppColors.surfaceGray,
                  side: BorderSide.none,
                  labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active == s ? Colors.white : AppColors.textPrimary),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ),
          ],
        ),
      );

  @override
  double get maxExtent => height;
  @override
  double get minExtent => height;
  @override
  bool shouldRebuild(_ChipBar old) => old.active != active || old.counts != counts;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({super.key, required this.title, required this.child, this.count, this.action});
  final String title;
  final Widget child;
  final int? count;
  final (String, VoidCallback)? action;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
                    child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
                  ),
                ],
                const Spacer(),
                if (action != null) TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: action!.$2, child: Text(action!.$1)),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary));
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
                Text(title, style: const TextStyle(fontSize: 14, height: 1.4)),
                if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      );
}

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
  Widget build(BuildContext context) => GestureDetector(
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
                      Text(widget.hours.summary, maxLines: _expanded ? null : 1, overflow: _expanded ? null : TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
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
                          children: [
                            SizedBox(width: 44, child: Text(kDayLabels[d]!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                            Text(widget.hours.days[d] == null ? 'Closed' : '${OpeningHours.fmt(widget.hours.days[d]!.open)} – ${OpeningHours.fmt(widget.hours.days[d]!.close)}', style: TextStyle(fontSize: 13.5, color: widget.hours.days[d] == null ? AppColors.textSecondary : AppColors.textPrimary)),
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

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
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
                if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 5)],
                Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
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
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
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
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
