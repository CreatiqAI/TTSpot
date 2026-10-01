import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Bundled illustration sets (batch 3): car placeholders by body style, badge
/// pins, place-kind icons, club crests, partner covers, prizes and the points
/// coin. Every helper returns a path under assets/ that always exists.

// ---- Cars -------------------------------------------------------------------

/// Studio render of a generic white car matching a free-text body style (from
/// the recogniser, e.g. "Hatchback", "Sport Utility", "Saloon"), 4:3.
String carPlaceholderAsset(String? bodyStyle) {
  final s = (bodyStyle ?? '').toLowerCase();
  String pick() {
    if (s.isEmpty) return 'hatchback';
    if (s.contains('hatch')) return 'hatchback';
    if (s.contains('motor') || s.contains('bike') || s.contains('scooter')) return 'bike';
    if (s.contains('pickup') || s.contains('pick-up') || s.contains('truck') || s.contains('ute')) return 'pickup';
    if (s.contains('mpv') || s.contains('minivan') || s.contains('van') || s.contains('people')) return 'mpv';
    if (s.contains('suv') || s.contains('crossover') || s.contains('4x4') || s.contains('sport utility') || s.contains('off-road') || s.contains('offroad')) return 'suv';
    if (s.contains('coupe') || s.contains('coupé') || s.contains('convertible') || s.contains('roadster') || s.contains('cabrio') || s.contains('sport')) return 'coupe';
    if (s.contains('sedan') || s.contains('saloon') || s.contains('wagon') || s.contains('estate')) return 'sedan';
    return 'hatchback';
  }

  return 'assets/cars/${pick()}.png';
}

/// A car's placeholder art on a soft grey backdrop, filling its box. Used
/// wherever a car has no photo yet.
class CarPlaceholder extends StatelessWidget {
  const CarPlaceholder({super.key, this.bodyStyle, this.padding = 0.08});

  final String? bodyStyle;

  /// Inset as a fraction of the box's shorter side.
  final double padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceGray,
      child: LayoutBuilder(
        builder: (context, c) {
          final shortest = c.biggest.shortestSide.isFinite ? c.biggest.shortestSide : 100.0;
          final w = c.maxWidth.isFinite ? c.maxWidth : 400.0;
          return Padding(
            padding: EdgeInsets.all(shortest * padding),
            child: Image.asset(
              carPlaceholderAsset(bodyStyle),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              cacheWidth: (w * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 1200),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}

// ---- Badges -----------------------------------------------------------------

const _badgeIds = {
  'car_of_week',
  'convoy_captain',
  'explorer',
  'first_meet',
  'first_post',
  'garage_open',
  'guide_writer',
  'organiser',
  'popular',
  'regular',
  'spotter',
  'tt_regular',
};

/// Enamel-pin art for a badge id (public.badges.id), or null when unknown.
String? badgeAsset(String? id) => (id != null && _badgeIds.contains(id)) ? 'assets/badges/$id.png' : null;

/// A badge pin at [size]; greyed and faded when not [earned]. Falls back to
/// [fallback] (usually the emoji art) when the id has no pin.
class BadgeImage extends StatelessWidget {
  const BadgeImage({super.key, required this.id, this.size = 44, this.earned = true, this.fallback});

  final String id;
  final double size;
  final bool earned;
  final Widget? fallback;

  static const _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final asset = badgeAsset(id);
    Widget child = asset == null
        ? (fallback ?? SizedBox(width: size, height: size))
        : Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(48, 512),
            errorBuilder: (_, _, _) => fallback ?? SizedBox(width: size, height: size),
          );
    if (!earned) child = Opacity(opacity: 0.4, child: ColorFiltered(colorFilter: _greyscale, child: child));
    return child;
  }
}

// ---- Place kinds -------------------------------------------------------------

const _kinds = {
  'cafe',
  'mamak',
  'carpark',
  'route',
  'circuit',
  'mall',
  'workshop',
  'tyres',
  'bodyshop',
  'audio',
  'accessories',
  'detailing',
  'carwash',
  'other',
};

/// 3D category icon for a place kind (places.kind / vendors.type); unknown
/// kinds get the generic pin.
String kindIconAsset(String? kind) => 'assets/kinds/${_kinds.contains(kind) ? kind : 'other'}.png';

// ---- Event types + vouchers (batch 4) ---------------------------------------------

/// 3D icon for an event type (EventType.db / events.type).
String eventTypeAsset(String db) => 'assets/event_types/$db.png';

/// The voucher (coupon) icon, and its torn, greyed "used" version.
const kVoucherAsset = 'assets/vouchers/voucher.png';
const kVoucherUsedAsset = 'assets/vouchers/voucher_used.png';

// ---- Club crests --------------------------------------------------------------

/// A stable crest (1..8) for a club with no logo, picked from [seed] (the club
/// id). FNV-1a so it never changes between runs or platforms.
String crestAsset(String seed) {
  var h = 0x811c9dc5;
  for (final c in seed.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return 'assets/crests/crest_${h % 8 + 1}.png';
}

// ---- Partner covers -----------------------------------------------------------

const _partnerCovers = {'workshop', 'detailing', 'tyres', 'bodyshop', 'audio', 'accessories', 'carwash', 'cafe'};

/// 16:9 stock photo for a partner type (vendors.type) with no photos yet.
String partnerCoverAsset(String? type) => 'assets/partner_covers/${_partnerCovers.contains(type) ? type : 'workshop'}.jpg';

// ---- Prizes + points ------------------------------------------------------------

/// Generic prize art guessed from the prize name.
String prizeAsset(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'voucher|\brm\s?\d|\brm\b|discount|% off|\boff\b|cash|credit|coupon').hasMatch(n)) return 'assets/prizes/voucher.png';
  if (RegExp(r'\bcap\b|shirt|\btee\b|t-shirt|hoodie|jacket|merch|sticker|keychain|lanyard|decal').hasMatch(n)) return 'assets/prizes/merch.png';
  return 'assets/prizes/gift.png';
}

/// The points currency icon.
const kCoinAsset = 'assets/prizes/coin.png';

/// The coin at [size], for point balances and prices.
class PointsCoin extends StatelessWidget {
  const PointsCoin({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        kCoinAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(32, 256),
      );
}

/// Square asset thumbnail with rounded corners on grey, e.g. a prize without
/// a photo.
class AssetThumb extends StatelessWidget {
  const AssetThumb(this.asset, {super.key, this.size = 44, this.radius = 10, this.padding = 4});
  final String asset;
  final double size;
  final double radius;
  final double padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          color: AppColors.surfaceGray,
          padding: EdgeInsets.all(padding),
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(48, 512),
          ),
        ),
      );
}

/// The garage badge: the points coin's twin (blue enamel, garage emblem),
/// for the My garage pill. Made with tool/art_garage_icon.py.
const kGarageAsset = 'assets/prizes/garage.png';

class GarageBadge extends StatelessWidget {
  const GarageBadge({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        kGarageAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(32, 256),
      );
}
