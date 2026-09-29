import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/places/places_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/geo.dart';
import '../../../../core/utils/open_external.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/thumb_image.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../friends/application/friends_providers.dart';
import '../../../friends/domain/friend.dart';
import '../../../social/application/community_providers.dart';
import '../../../social/domain/club.dart';
import '../../../vendors/application/vendors_providers.dart';
import '../../../vendors/domain/vendor.dart';
import '../../../vendors/presentation/widgets/hours_editor.dart' show OpeningHours;
import '../../application/map_providers.dart';
import 'tt_now_sheet.dart';

/// Open the Map tab on [p] with its preview card up, on the Spots layer.
/// Search results and "Show on map" on a spot's page come here.
void showPlaceOnMap(BuildContext context, WidgetRef ref, Place p) {
  // Focus first: the Spots layer then skips its "nearest spots" view.
  ref.read(mapFocusProvider.notifier).preview(p);
  ref.read(mapModeProvider.notifier).set(MapMode.spots);
  ref.read(mapListViewProvider.notifier).set(false);
  context.go(Routes.map);
}

/// "TT here" on a card. Within 1 km of the place: the TT now sheet with the
/// place filled in. Further away TT now doesn't fit (it is for where you
/// are), so it offers to plan a TT session there instead.
Future<void> ttHere(BuildContext context, WidgetRef ref, Place p, String name) async {
  final here = ref.read(userLocationProvider).value;
  final km = here == null ? null : distanceKm(here, p.latLng);
  if (km != null && km <= 1) {
    final at = PlaceDetails(placeId: '', name: name, address: '', lat: p.lat, lng: p.lng, distanceM: (km * 1000).round());
    ref.read(ttPlaceProvider.notifier).set(at);
    await showTtNowSheet(context, at: at);
    return;
  }
  final plan = await confirmSheet(
    context,
    icon: AppIcons.flag,
    title: km == null ? 'Plan a TT session here?' : 'You\'re ${formatDistance(km)} away',
    body: km == null ? 'TT now needs your location. You can still plan a session at $name.' : 'TT now is for where you are. Plan a TT session at $name instead?',
    confirm: 'Plan a session',
  );
  if (plan && context.mounted) context.push(Routes.createEventAs(session: true, at: p.latLng, venue: name));
}

/// "Petaling Jaya" out of "12, Jalan SS 2/24, 47300 Petaling Jaya, Selangor":
/// the town after the postcode. Null when the address has no postcode.
String? areaOf(String? address) {
  final area = RegExp(r'\b\d{5}\s+([^,]+)').firstMatch(address ?? '')?.group(1)?.trim();
  return area == null || area.isEmpty ? null : area;
}

/// Friends on the map at [p] right now: checked in there, or within 150 m.
List<FriendPin> friendsAt(List<FriendPin> pins, Place p) => [
      for (final f in pins)
        if (!f.isStranger && f.isFresh && (f.placeId == p.id || distanceKm(f.latLng, p.latLng) <= 0.15)) f,
    ];

/// The card that slides up when a spot or a partner shop is picked on the
/// map (its pin, the list, Search, "Show on map"): what it is, how far, who
/// is there, and the next step. The full page is one tap away.
class PlacePreviewCard extends ConsumerWidget {
  const PlacePreviewCard({super.key, required this.place, required this.onClose});
  final Place place;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The full row (counts, partner fields). A search result only carries
    // the bare place; the spot's page reads the same provider.
    final p = ref.watch(placeProvider(place.id)).value ?? place;
    final pal = MapPalette.of(context);
    final here = ref.watch(userLocationProvider).value;
    final km = here == null ? null : distanceKm(here, p.latLng);
    final vendor = p.isPartner ? ref.watch(vendorPublicProvider(p.vendorId!)).value : null;
    final name = p.isPartner ? (vendor?.name ?? p.vendorName ?? p.name) : p.name;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: pal.light ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: pal.light ? 0.14 : 0.45), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grab bar: the card swipes down to close.
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: pal.handle, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 8),
          if (p.isPartner)
            _PartnerBody(place: p, vendor: vendor, name: name, km: km, onClose: onClose)
          else
            _SpotBody(place: p, km: km, onClose: onClose),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: PrimaryButton(label: 'Go now', icon: AppIcons.navigationArrow, onPressed: () => showDirectionsSheet(context, lat: p.lat, lng: p.lng, label: name))),
              const SizedBox(width: 8),
              Expanded(child: _OutlineButton(label: 'TT here', icon: AppIcons.flag, onPressed: () => ttHere(context, ref, p, name))),
            ],
          ),
          TextButton(
            onPressed: () => context.push(p.isPartner ? Routes.partner(p.vendorId!) : Routes.place(p.id)),
            style: TextButton.styleFrom(foregroundColor: pal.text, minimumSize: const Size.fromHeight(42)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.isPartner ? 'View shop' : 'View more', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Icon(AppIcons.caretRight, size: 14, color: pal.text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- spot ---

class _SpotBody extends ConsumerWidget {
  const _SpotBody({required this.place, required this.km, required this.onClose});
  final Place place;
  final double? km;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = place;
    final pal = MapPalette.of(context);
    final friends = friendsAt(ref.watch(friendPinsProvider).value ?? const <FriendPin>[], p);
    // Who checked in last: asked only when no friend is here right now.
    final visitors = friends.isEmpty ? (ref.watch(placeRecentVisitorsProvider(p.id)).value ?? const <PlaceVisit>[]) : const <PlaceVisit>[];
    final stats = <(IconData, String)>[
      if (p.totalCheckins > 0) (AppIcons.checkCircle, '${p.totalCheckins} check-in${p.totalCheckins == 1 ? '' : 's'}'),
      if (p.upcomingMeets > 0) (AppIcons.calendarBlank, '${p.upcomingMeets} meet${p.upcomingMeets == 1 ? '' : 's'} coming up'),
      if (p.momentCount > 0) (AppIcons.camera, '${p.momentCount} moment${p.momentCount == 1 ? '' : 's'}'),
    ].take(2);
    final fallback = ColoredBox(color: pal.tile, child: Center(child: ArtIcon(p.kindArt, size: 38)));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(width: 78, height: 78, child: p.coverUrl == null ? fallback : ThumbImage(p.coverUrl!, placeholder: fallback, error: fallback)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontSize: 17, fontWeight: FontWeight.w800, height: 1.2))),
                      if (p.recommended) ...[
                        const SizedBox(width: 6),
                        const _Tag(icon: AppIcons.starFill, text: 'TOP SPOT'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [p.kindLabel, if (km != null) '${formatDistance(km!)} away'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pal.text2, fontSize: 13),
                  ),
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final (icon, text) in stats) _StatChip(icon: icon, text: text)]),
                  ],
                ],
              ),
            ),
            _CloseButton(onTap: onClose),
          ],
        ),
        if (friends.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PeopleLine(
            urls: [for (final f in friends) f.user.avatarUrl],
            names: [for (final f in friends) f.user.displayName ?? f.user.username],
            seeds: [for (final f in friends) f.user.id],
            text: friends.length == 1 ? '${_first(friends.first)} is here now' : '${_first(friends.first)} and ${friends.length - 1} friend${friends.length == 2 ? '' : 's'} here now',
            live: true,
          ),
        ] else if (visitors.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PeopleLine(
            urls: [for (final v in visitors) v.profile.avatarUrl],
            names: [for (final v in visitors) v.profile.username],
            seeds: [for (final v in visitors) v.profile.id],
            text: 'Recently here · ${visitors.first.profile.username ?? 'someone'} ${timeAgo(visitors.first.at)}${visitors.length > 1 ? ' · ${visitors.length - 1} more' : ''}',
          ),
        ],
      ],
    );
  }

  static String _first(FriendPin f) => (f.user.displayName ?? f.user.username ?? 'A friend').split(' ').first;
}

// ----------------------------------------------------------------- partner ---

class _PartnerBody extends ConsumerWidget {
  const _PartnerBody({required this.place, required this.vendor, required this.name, required this.km, required this.onClose});
  final Place place;
  final PublicVendor? vendor;
  final String name;
  final double? km;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = MapPalette.of(context);
    final v = vendor;
    final logo = v?.logoUrl ?? place.vendorLogo;
    final status = v == null ? null : OpeningHours.fromJson(v.hoursJson).status();
    final open = status != null && status.startsWith('Open');
    final voucher = (ref.watch(shopVouchersProvider).value ?? const <Voucher>[])
        .where((x) => x.vendorId == place.vendorId && x.active && !x.ended && !x.soldOut)
        .firstOrNull;
    final meta = [v == null ? place.kindLabel : businessTypeLabel(v.type), ?areaOf(v?.address), if (km != null) '${formatDistance(km!)} away'].join(' · ');
    final noLogo = ColoredBox(color: pal.tile, child: Icon(AppIcons.storefront, size: 30, color: pal.text2));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 78,
              height: 78,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.divider)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: logo == null ? noLogo : Image(image: CachedNetworkImageProvider(logo), fit: BoxFit.cover, errorBuilder: (_, _, _) => noLogo),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontSize: 17, fontWeight: FontWeight.w800, height: 1.2))),
                      const SizedBox(width: 6),
                      const _Tag(icon: AppIcons.sealCheck, text: 'PARTNER'),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text2, fontSize: 13)),
                  if (status != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(AppIcons.clock, size: 14, color: open ? AppColors.success : pal.text2),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: open ? AppColors.success : pal.text2, fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _CloseButton(onTap: onClose),
          ],
        ),
        if (voucher != null) ...[
          const SizedBox(height: 12),
          _VoucherBox(voucher: voucher),
        ],
      ],
    );
  }
}

/// A live voucher at the shop, in a dashed red box. Tap: Rewards, to claim it.
class _VoucherBox extends StatelessWidget {
  const _VoucherBox({required this.voucher});
  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final pal = MapPalette.of(context);
    return CustomPaint(
      painter: const _DashedBorder(color: AppColors.brand, radius: 12),
      child: Material(
        color: AppColors.brand.withValues(alpha: pal.light ? 0.05 : 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(Routes.rewards),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                const Icon(AppIcons.ticket, size: 18, color: AppColors.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: voucher.title, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800)),
                      TextSpan(text: ' with TT Spot', style: TextStyle(color: pal.text2, fontWeight: FontWeight.w600)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, this.radius = 12});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}

// ------------------------------------------------------------------ pieces ---

/// Small red label next to the name: TOP SPOT, PARTNER.
class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final pal = MapPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: pal.tile, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: pal.text),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: pal.text, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Avatars and one line: who is here now (green) or who was here last.
class _PeopleLine extends StatelessWidget {
  const _PeopleLine({required this.urls, required this.names, required this.seeds, required this.text, this.live = false});
  final List<String?> urls;
  final List<String?> names;
  final List<String?> seeds;
  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final pal = MapPalette.of(context);
    return Row(
      children: [
        AvatarStack(urls: urls, names: names, seeds: seeds, size: 24, max: 4),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: live ? AppColors.success : pal.text2, fontSize: 13, fontWeight: live ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = MapPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: pal.tile,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 30, height: 30, child: Icon(AppIcons.x, size: 16, color: pal.text2)),
        ),
      ),
    );
  }
}

/// Outlined twin of [PrimaryButton] in the map's colours.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final pal = MapPalette.of(context);
    return PressScale(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: pal.text),
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: pal.text, side: BorderSide(color: pal.text.withValues(alpha: 0.28), width: 1.5)),
      ),
    );
  }
}
