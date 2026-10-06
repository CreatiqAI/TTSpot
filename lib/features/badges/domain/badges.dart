import 'dart:math' as math;
import 'dart:ui' show Color;

// Badges with four tiers (migration 20261006000108_points_badges.sql):
// 1 bronze, 2 silver, 3 platinum, 4 gold. The database keeps each member's
// tier (badge_tiers) and only ever raises it; every new tier pays +10.

/// The five badges, in page order (public.badges where active).
const kBadgeIds = ['posts', 'organizer', 'joiner', 'explorer', 'popular'];

/// Names for when the badges table hasn't loaded (Activity rows).
const kBadgeNames = {
  'posts': 'Posts',
  'organizer': 'Car meet organizer',
  'joiner': 'Car meet joining',
  'explorer': 'Explorer',
  'popular': 'Popular',
};

/// Gold is the top.
const kTopTier = 4;

/// At most this many medallions in the profile's honour row.
const kHonourMax = 3;

String badgeTierName(int tier) => switch (tier) {
      1 => 'Bronze',
      2 => 'Silver',
      3 => 'Platinum',
      4 => 'Gold',
      _ => 'Locked',
    };

/// Text colour for a tier's name (readable on white and on the dark theme).
Color badgeTierColor(int tier) => switch (tier) {
      1 => const Color(0xFFA9612B),
      2 => const Color(0xFF7D858F),
      3 => const Color(0xFF4F7FA6),
      4 => const Color(0xFFB8860B),
      _ => const Color(0xFF9AA0A8),
    };

/// How many of [thresholds] a [count] reaches: 0 (locked) to 4 (gold).
int tierForCount(List<int> thresholds, int count) => math.min(kTopTier, thresholds.where((t) => t <= count).length);

/// The art for a badge at a tier: `assets/badges/<id>_<tier>.png` (1 bronze …
/// 4 gold, transparent square PNGs). Locked badges use the bronze art, greyed.
String badgeArt(String id, int tier) => 'assets/badges/${id}_${tier.clamp(1, kTopTier)}.png';

/// The single (gold-style) art each badge had before tiers, shown tinted per
/// tier until the tiered files land.
String badgeFallbackArt(String id) => switch (id) {
      'posts' => 'assets/badges/first_post.png',
      'organizer' => 'assets/badges/organiser.png',
      'joiner' => 'assets/badges/first_meet.png',
      'explorer' => 'assets/badges/explorer.png',
      'popular' => 'assets/badges/popular.png',
      _ => 'assets/badges/first_meet.png',
    };

/// One badge on the badges page: the member's tier and live count.
class BadgeProgress {
  const BadgeProgress({
    required this.id,
    required this.name,
    required this.description,
    required this.unit,
    required this.thresholds,
    required this.storedTier,
    required this.count,
    this.sort = 100,
    this.tierReachedAt,
    this.onProfile = false,
  });

  final String id;
  final String name;

  /// What it counts, in a sentence.
  final String description;

  /// "meets joined", "followers".
  final String unit;

  /// Four counts: bronze, silver, platinum, gold.
  final List<int> thresholds;

  /// The tier the database holds (it never goes down).
  final int storedTier;
  final int count;
  final int sort;
  final DateTime? tierReachedAt;

  /// In the member's honour row right now.
  final bool onProfile;

  factory BadgeProgress.fromMap(Map<String, dynamic> m) => BadgeProgress(
        id: m['badge_id'] as String,
        name: m['name'] as String? ?? kBadgeNames[m['badge_id']] ?? '',
        description: m['description'] as String? ?? '',
        unit: m['unit'] as String? ?? '',
        thresholds: ((m['thresholds'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        storedTier: (m['tier'] as num?)?.toInt() ?? 0,
        count: (m['progress'] as num?)?.toInt() ?? 0,
        sort: (m['sort'] as num?)?.toInt() ?? 100,
        tierReachedAt: m['tier_reached_at'] == null ? null : DateTime.parse(m['tier_reached_at'] as String).toLocal(),
        onProfile: m['on_profile'] == true,
      );

  /// What to show: the stored tier, or what the count already reaches when
  /// the database hasn't caught up yet (someone else's page between sweeps).
  int get tier => math.max(storedTier, tierForCount(thresholds, count));

  bool get earned => tier > 0;
  bool get isTop => tier >= kTopTier;

  /// The tier to aim for next (gold stays gold).
  int get nextTier => math.min(kTopTier, tier + 1);

  /// The count that reaches [nextTier]; null at gold.
  int? get nextThreshold => isTop || tier >= thresholds.length ? null : thresholds[tier];

  /// The bar: how far the count is towards [nextThreshold] (full at gold).
  double get fraction {
    final next = nextThreshold;
    if (next == null || next <= 0) return 1;
    return (count / next).clamp(0.0, 1.0);
  }

  /// "12 / 20 meets joined to Platinum"; at gold "57 meets joined · top tier".
  String get progressLabel {
    final next = nextThreshold;
    if (next == null) return '$count $unit · top tier';
    return '$count / $next $unit to ${badgeTierName(nextTier)}';
  }
}

/// One medallion in a profile's honour row.
class HonourBadge {
  const HonourBadge({required this.id, required this.name, required this.tier, this.reachedAt, this.chosen = false});
  final String id;
  final String name;
  final int tier;
  final DateTime? reachedAt;

  /// Picked by the member (else it's one of their latest three).
  final bool chosen;

  factory HonourBadge.fromMap(Map<String, dynamic> m) => HonourBadge(
        id: m['badge_id'] as String,
        name: m['name'] as String? ?? kBadgeNames[m['badge_id']] ?? '',
        tier: (m['tier'] as num?)?.toInt() ?? 1,
        reachedAt: m['tier_reached_at'] == null ? null : DateTime.parse(m['tier_reached_at'] as String).toLocal(),
        chosen: m['chosen'] == true,
      );
}

/// The Activity line for a 'badge' notification (body = the tier reached,
/// empty on rows from before tiers).
String badgeActivityText(String name, String? body) {
  final tier = int.tryParse(body ?? '');
  if (tier == null || tier < 1) return 'You earned the $name badge.';
  if (tier == 1) return 'You earned the $name badge: Bronze.';
  return 'Your $name badge is now ${badgeTierName(tier)}.';
}

/// Activity hides badge rows for the retired one-shot badges.
bool isRetiredBadgeRow(String? badgeId) => badgeId == null || !kBadgeIds.contains(badgeId);
