import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/guide/guide.dart';
import '../../../core/guide/guide_controller.dart';
import '../../../core/guide/guide_on_first_view.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../social/application/chat_providers.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/follow.dart';
import '../../social/presentation/widgets/follow_button.dart';
import '../../guides/map_guides.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';
import 'widgets/partner_tabs.dart';

/// A partner's page for members: cover, identity, then a pinned tab bar over
/// five swipeable pages: Info · Products · Vouchers · Posts · Events.
/// Everything a member needs to visit, buy or message the shop.
class PartnerScreen extends ConsumerWidget {
  const PartnerScreen({super.key, required this.vendorId, this.initialTab});
  final String vendorId;

  /// Opens on this tab: 'info' | 'products' | 'vouchers' | 'posts' | 'events'
  /// (the route's `?tab=`). Anything else opens on Info.
  final String? initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendor = ref.watch(vendorPublicProvider(vendorId));
    final v = vendor.value;
    return Scaffold(
      appBar: v == null ? AppBar() : null,
      body: v != null
          ? _PartnerLive(v: v, initialTab: initialTab)
          : vendor.isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(vendor.hasError ? friendlyError(vendor.error!) : 'This partner is no longer on TT Spot.', textAlign: TextAlign.center),
                  ),
                ),
    );
  }
}

/// Feeds [PartnerPageView] from the providers and handles Message and
/// pull-to-refresh.
class _PartnerLive extends ConsumerStatefulWidget {
  const _PartnerLive({required this.v, required this.initialTab});
  final PublicVendor v;
  final String? initialTab;

  @override
  ConsumerState<_PartnerLive> createState() => _PartnerLiveState();
}

class _PartnerLiveState extends ConsumerState<_PartnerLive> {
  /// What TiTi's first-partner tour spotlights.
  final _guide = PartnerGuideKeys();

  Future<void> _message() async {
    try {
      final id = await ref.read(chatActionsProvider).openVendorDm(widget.v.id);
      if (mounted) context.push(Routes.chat(id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _refresh(PartnerTab tab) async {
    final id = widget.v.id;
    try {
      switch (tab) {
        case PartnerTab.info:
          ref.invalidate(vendorPublicProvider(id));
          ref.invalidate(followerCountProvider((kind: FollowKind.partner, id: id)));
          await ref.read(vendorPublicProvider(id).future);
        case PartnerTab.products:
          ref.invalidate(partnerProductsProvider(id));
          ref.invalidate(shopVouchersProvider);
          await Future.wait([ref.read(partnerProductsProvider(id).future), ref.read(shopVouchersProvider.future)]);
        case PartnerTab.vouchers:
          ref.invalidate(shopVouchersProvider);
          await ref.read(shopVouchersProvider.future);
        case PartnerTab.posts:
          final key = (column: 'vendor_id', value: id);
          ref.invalidate(postsWhereProvider(key));
          await ref.read(postsWhereProvider(key).future);
        case PartnerTab.events:
          ref.invalidate(vendorEventsProvider(id));
          await ref.read(vendorEventsProvider(id).future);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  /// Null while loading; a failed load reads as empty rather than spinning forever.
  List<T>? _list<T>(AsyncValue<List<T>> a) => a.hasValue ? a.value : (a.hasError ? <T>[] : null);

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    ref.watch(partnerViewedProvider(v.id));
    final me = ref.watch(currentUserIdProvider);
    final shop = _list(ref.watch(shopVouchersProvider));
    // Everyone but the shop's own owner can follow it.
    final mine = v.ownerIsMe(me);
    final FollowTarget follow = (kind: FollowKind.partner, id: v.id);
    return GuideOnFirstView(
      id: GuideIds.partner,
      // Anyone but the shop's owner, once Follow knows where it stands.
      ready: !mine && ref.watch(followProvider(follow)).hasValue && ref.watch(guideJourneyProvider) == null,
      build: () => partnerGuide(_guide, hasLocation: widget.v.lat != null && widget.v.lng != null, hasSpot: widget.v.placeId != null),
      child: PartnerPageView(
      guideKeys: _guide,
      vendor: v,
      initialTab: widget.initialTab,
      products: _list(ref.watch(partnerProductsProvider(v.id))),
      vouchers: shop?.where((x) => x.vendorId == v.id).toList(),
      posts: _list(ref.watch(postsWhereProvider((column: 'vendor_id', value: v.id)))),
      events: _list(ref.watch(vendorEventsProvider(v.id))),
      onMessage: mine ? null : _message,
      onRefresh: _refresh,
      following: mine ? null : ref.watch(followProvider(follow)).value,
      followers: ref.watch(followerCountProvider(follow)).value,
      onFollow: mine ? null : () => tapFollow(context, ref, follow, name: v.name),
      ),
    );
  }
}
