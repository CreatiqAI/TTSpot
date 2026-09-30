import 'package:flutter/material.dart';

/// Blind box cards: 7 per set, 4 common · 2 rare · 1 legendary.
///
/// Members see the top tier as "Secret" (the name printed on the art); the
/// enum and the database keep `legendary`.
enum CardRarity {
  common,
  rare,
  legendary;

  static CardRarity fromDb(String? v) => switch (v) {
        'legendary' => legendary,
        'rare' => rare,
        _ => common,
      };

  String get db => name;

  String get label => switch (this) {
        common => 'Common',
        rare => 'Rare',
        legendary => 'Secret',
      };

  /// Accent used for the ribbon, glow and reveal backdrop. Rare is the silver
  /// of its holographic frame; see `RarityLook` for the pill fill and text tones.
  Color get color => switch (this) {
        common => const Color(0xFF9AA0A8),
        rare => const Color(0xFFAFB6C0),
        legendary => const Color(0xFFF5B301),
      };
}

/// One of the printable card designs (`card_types`).
class CardType {
  const CardType({
    required this.id,
    required this.setId,
    required this.number,
    required this.name,
    required this.rarity,
    required this.color,
    required this.active,
    required this.sort,
    this.description,
    this.artUrl,
  });

  final String id;
  final String setId;
  final int number;
  final String name;
  final CardRarity rarity;
  final String? description;
  /// Final artwork. Null until the designs land: the app draws a placeholder.
  final String? artUrl;
  /// Placeholder tint, as `#RRGGBB`.
  final Color color;
  final bool active;
  final int sort;

  factory CardType.fromMap(Map<String, dynamic> m) => CardType(
        id: m['id'] as String,
        setId: m['set_id'] as String? ?? 'set1',
        number: (m['number'] as num?)?.toInt() ?? 0,
        name: m['name'] as String? ?? '',
        rarity: CardRarity.fromDb(m['rarity'] as String?),
        description: m['description'] as String?,
        artUrl: m['art_url'] as String?,
        color: parseHex(m['color'] as String?) ?? const Color(0xFF9AA0A8),
        active: m['active'] as bool? ?? true,
        sort: (m['sort'] as num?)?.toInt() ?? 100,
      );

  static Color? parseHex(String? hex) {
    if (hex == null) return null;
    final h = hex.replaceFirst('#', '').trim();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  String get hex => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// One copy I own (or owned: `redeemed` rows were spent on a prize).
class UserCard {
  const UserCard({required this.id, required this.cardId, required this.status, required this.source, required this.acquiredAt, this.redeemedAt, this.serial});
  final String id;
  final String cardId;
  final String status; // held | redeemed
  final String source; // box | trade | admin
  final DateTime acquiredAt;
  final DateTime? redeemedAt;
  /// Legendary copies only: which of the limited run this is ("No. 37 of 100").
  final int? serial;

  bool get held => status == 'held';

  factory UserCard.fromMap(Map<String, dynamic> m) => UserCard(
        id: m['id'] as String,
        cardId: m['card_id'] as String,
        status: m['status'] as String? ?? 'held',
        source: m['source'] as String? ?? 'box',
        acquiredAt: DateTime.parse(m['acquired_at'] as String).toLocal(),
        redeemedAt: m['redeemed_at'] == null ? null : DateTime.parse(m['redeemed_at'] as String).toLocal(),
        serial: (m['serial'] as num?)?.toInt(),
      );
}

/// A blind box. Sealed until the member opens it in the app.
class CardBox {
  const CardBox({required this.id, required this.source, required this.status, required this.pointsSpent, required this.createdAt, this.cardId, this.openedAt});
  final String id;
  final String source; // signup | points | spot | admin
  final String status; // sealed | opened
  final String? cardId;
  final int pointsSpent;
  final DateTime createdAt;
  final DateTime? openedAt;

  bool get sealed => status == 'sealed';

  factory CardBox.fromMap(Map<String, dynamic> m) => CardBox(
        id: m['id'] as String,
        source: m['source'] as String? ?? 'admin',
        status: m['status'] as String? ?? 'sealed',
        cardId: m['card_id'] as String?,
        pointsSpent: (m['points_spent'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        openedAt: m['opened_at'] == null ? null : DateTime.parse(m['opened_at'] as String).toLocal(),
      );
}

/// What `open_box` hands back: the card that was inside.
class BoxResult {
  const BoxResult({required this.userCardId, required this.card, required this.held});
  final String userCardId;
  final CardType card;
  /// Copies of this card I hold now, this one included. 1 = brand new.
  final int held;
  bool get isNew => held <= 1;

  factory BoxResult.fromMap(Map<String, dynamic> m) => BoxResult(
        userCardId: m['user_card_id'] as String,
        card: CardType.fromMap({...m, 'id': m['card_id']}),
        held: (m['held'] as num?)?.toInt() ?? 1,
      );
}

/// My cards, counted. Built on the phone from `my_cards` + `card_types`.
class CardCollection {
  CardCollection({required this.types, required this.cards}) {
    for (final c in cards.where((c) => c.held)) {
      counts[c.cardId] = (counts[c.cardId] ?? 0) + 1;
    }
  }

  final List<CardType> types;
  final List<UserCard> cards;
  final Map<String, int> counts = {};

  List<UserCard> get held => cards.where((c) => c.held).toList();
  int get heldCount => held.length;
  int count(String cardId) => counts[cardId] ?? 0;
  bool owns(String cardId) => count(cardId) > 0;
  int get distinctOwned => types.where((t) => t.active && owns(t.id)).length;
  int get setSize => types.where((t) => t.active).length;
  bool get hasFullSet => setSize > 0 && distinctOwned == setSize;

  CardType? type(String id) => types.where((t) => t.id == id).firstOrNull;

  int heldOfRarity(CardRarity r) => held.where((c) => type(c.cardId)?.rarity == r).length;

  /// Held copies of a card, oldest first (what a trade offers first).
  List<UserCard> copiesOf(String cardId) => held.where((c) => c.cardId == cardId).toList()..sort((a, b) => a.acquiredAt.compareTo(b.acquiredAt));

  /// Serial numbers of the held copies of a limited card, lowest first.
  List<int> serialsOf(String cardId) => [for (final c in held) if (c.cardId == cardId && c.serial != null) c.serial!]..sort();

  /// Null when I can claim [r]; otherwise the one-line reason I can't.
  String? shortfall(CardReward r) {
    // full set takes one of each first, then rarity needs come from what is left
    final left = <CardRarity, int>{for (final k in CardRarity.values) k: heldOfRarity(k)};
    if (r.needFullSet) {
      if (!hasFullSet) return 'Needs the full set ($distinctOwned of $setSize)';
      for (final t in types.where((t) => t.active)) {
        left[t.rarity] = (left[t.rarity] ?? 0) - 1;
      }
    }
    for (final (k, need) in [(CardRarity.common, r.needCommon), (CardRarity.rare, r.needRare), (CardRarity.legendary, r.needLegendary)]) {
      final have = left[k] ?? 0;
      if (have < need) return 'Need ${need - have} more ${k.label.toLowerCase()}${need - have == 1 ? '' : 's'}';
    }
    return null;
  }
}

class TradeItem {
  const TradeItem({required this.userCardId, required this.cardId});
  final String userCardId;
  final String cardId;
  factory TradeItem.fromMap(Map<String, dynamic> m) => TradeItem(userCardId: m['user_card_id'] as String, cardId: m['card_id'] as String);
}

enum TradeStatus {
  proposed,
  accepted,
  declined,
  cancelled;

  static TradeStatus fromDb(String? v) => switch (v) {
        'accepted' => accepted,
        'declined' => declined,
        'cancelled' => cancelled,
        _ => proposed,
      };

  String get label => switch (this) {
        proposed => 'Waiting',
        accepted => 'Done',
        declined => 'Declined',
        cancelled => 'Cancelled',
      };
}

/// A trade offer between two friends. `offer` = what the sender gives,
/// `request` = what they want back.
class CardTrade {
  const CardTrade({
    required this.id,
    required this.fromUser,
    required this.toUser,
    required this.status,
    required this.createdAt,
    required this.fromUsername,
    required this.toUsername,
    required this.offer,
    required this.request,
    this.message,
    this.decidedAt,
    this.fromDisplayName,
    this.fromAvatarUrl,
    this.toDisplayName,
    this.toAvatarUrl,
  });

  final String id;
  final String fromUser;
  final String toUser;
  final TradeStatus status;
  final String? message;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String fromUsername;
  final String? fromDisplayName;
  final String? fromAvatarUrl;
  final String toUsername;
  final String? toDisplayName;
  final String? toAvatarUrl;
  final List<TradeItem> offer;
  final List<TradeItem> request;

  bool isIncoming(String? me) => toUser == me;
  String otherName(String? me) => isIncoming(me) ? (fromDisplayName ?? '@$fromUsername') : (toDisplayName ?? '@$toUsername');
  String? otherAvatar(String? me) => isIncoming(me) ? fromAvatarUrl : toAvatarUrl;
  String otherId(String? me) => isIncoming(me) ? fromUser : toUser;

  factory CardTrade.fromMap(Map<String, dynamic> m) => CardTrade(
        id: m['id'] as String,
        fromUser: m['from_user'] as String,
        toUser: m['to_user'] as String,
        status: TradeStatus.fromDb(m['status'] as String?),
        message: m['message'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        decidedAt: m['decided_at'] == null ? null : DateTime.parse(m['decided_at'] as String).toLocal(),
        fromUsername: m['from_username'] as String? ?? '',
        fromDisplayName: m['from_display_name'] as String?,
        fromAvatarUrl: m['from_avatar_url'] as String?,
        toUsername: m['to_username'] as String? ?? '',
        toDisplayName: m['to_display_name'] as String?,
        toAvatarUrl: m['to_avatar_url'] as String?,
        offer: ((m['offer'] as List?) ?? const []).map((e) => TradeItem.fromMap((e as Map).cast<String, dynamic>())).toList(),
        request: ((m['request'] as List?) ?? const []).map((e) => TradeItem.fromMap((e as Map).cast<String, dynamic>())).toList(),
      );
}

/// A prize that costs cards (`card_rewards`).
class CardReward {
  const CardReward({
    required this.id,
    required this.title,
    required this.needCommon,
    required this.needRare,
    required this.needLegendary,
    required this.needFullSet,
    required this.claimsCount,
    required this.perUserLimit,
    required this.startsAt,
    required this.active,
    this.vendorId,
    this.vendorName,
    this.vendorLogo,
    this.description,
    this.terms,
    this.imageUrl,
    this.stock,
    this.endsAt,
    this.myClaims = 0,
    this.myActiveClaim,
    this.redeemedCount = 0,
  });

  final String id;
  final String? vendorId;
  final String? vendorName;
  final String? vendorLogo;
  final String title;
  final String? description;
  final String? terms;
  final String? imageUrl;
  final int needCommon;
  final int needRare;
  final int needLegendary;
  final bool needFullSet;
  final int? stock;
  final int claimsCount;
  final int perUserLimit;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool active;
  final int myClaims;
  final String? myActiveClaim;
  /// Admin list only.
  final int redeemedCount;

  String get byName => vendorName ?? 'TT Spot';
  int? get left => stock == null ? null : (stock! - claimsCount).clamp(0, stock!);

  /// "Full set", "2 common + 1 rare" …
  String get costLabel {
    final parts = <String>[
      if (needFullSet) 'Full set',
      if (needCommon > 0) '$needCommon common',
      if (needRare > 0) '$needRare rare',
      if (needLegendary > 0) '$needLegendary ${CardRarity.legendary.label.toLowerCase()}',
    ];
    return parts.join(' + ');
  }

  int get cardsNeeded => needCommon + needRare + needLegendary;

  factory CardReward.fromMap(Map<String, dynamic> m) => CardReward(
        id: m['id'] as String,
        vendorId: m['vendor_id'] as String?,
        vendorName: m['vendor_name'] as String?,
        vendorLogo: m['vendor_logo'] as String?,
        title: m['title'] as String? ?? '',
        description: m['description'] as String?,
        terms: m['terms'] as String?,
        imageUrl: m['image_url'] as String?,
        needCommon: (m['need_common'] as num?)?.toInt() ?? 0,
        needRare: (m['need_rare'] as num?)?.toInt() ?? 0,
        needLegendary: (m['need_legendary'] as num?)?.toInt() ?? 0,
        needFullSet: m['need_full_set'] as bool? ?? false,
        stock: (m['stock'] as num?)?.toInt(),
        claimsCount: (m['claims_count'] as num?)?.toInt() ?? 0,
        perUserLimit: (m['per_user_limit'] as num?)?.toInt() ?? 1,
        startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
        endsAt: m['ends_at'] == null ? null : DateTime.parse(m['ends_at'] as String).toLocal(),
        active: m['active'] as bool? ?? true,
        myClaims: (m['my_claims'] as num?)?.toInt() ?? 0,
        myActiveClaim: m['my_active_claim'] as String?,
        redeemedCount: (m['redeemed_count'] as num?)?.toInt() ?? 0,
      );
}

enum ClaimState {
  active,
  redeemed,
  expired,
  cancelled;

  static ClaimState fromDb(String? v) => switch (v) {
        'redeemed' => redeemed,
        'expired' => expired,
        'cancelled' => cancelled,
        _ => active,
      };

  String get label => switch (this) {
        active => 'Ready',
        redeemed => 'Handed over',
        expired => 'Expired',
        cancelled => 'Cancelled',
      };
}

/// A prize I claimed: show its QR at the counter.
class CardRewardClaim {
  const CardRewardClaim({
    required this.id,
    required this.rewardId,
    required this.title,
    required this.byName,
    required this.status,
    required this.cardsUsed,
    required this.claimedAt,
    required this.expiresAt,
    this.imageUrl,
    this.redeemedAt,
  });
  final String id;
  final String rewardId;
  final String title;
  final String byName;
  final String? imageUrl;
  final ClaimState status;
  final int cardsUsed;
  final DateTime claimedAt;
  final DateTime expiresAt;
  final DateTime? redeemedAt;

  factory CardRewardClaim.fromMap(Map<String, dynamic> m) => CardRewardClaim(
        id: m['id'] as String,
        rewardId: m['reward_id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        byName: m['vendor_name'] as String? ?? 'TT Spot',
        imageUrl: m['image_url'] as String?,
        status: ClaimState.fromDb(m['status'] as String?),
        cardsUsed: (m['cards_used'] as num?)?.toInt() ?? 0,
        claimedAt: DateTime.parse(m['claimed_at'] as String).toLocal(),
        expiresAt: DateTime.parse(m['expires_at'] as String).toLocal(),
        redeemedAt: m['redeemed_at'] == null ? null : DateTime.parse(m['redeemed_at'] as String).toLocal(),
      );
}

/// Counter side: who is standing here and what did they win.
class CardClaimLookup {
  const CardClaimLookup({
    required this.id,
    required this.title,
    required this.status,
    required this.cardsUsed,
    required this.expiresAt,
    this.description,
    this.terms,
    this.imageUrl,
    this.redeemedAt,
    this.username,
    this.displayName,
    this.avatarUrl,
  });
  final String id;
  final String title;
  final String? description;
  final String? terms;
  final String? imageUrl;
  final ClaimState status;
  final int cardsUsed;
  final DateTime expiresAt;
  final DateTime? redeemedAt;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  factory CardClaimLookup.fromMap(Map<String, dynamic> m) => CardClaimLookup(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        description: m['description'] as String?,
        terms: m['terms'] as String?,
        imageUrl: m['image_url'] as String?,
        status: ClaimState.fromDb(m['status'] as String?),
        cardsUsed: (m['cards_used'] as num?)?.toInt() ?? 0,
        expiresAt: DateTime.parse(m['expires_at'] as String).toLocal(),
        redeemedAt: m['redeemed_at'] == null ? null : DateTime.parse(m['redeemed_at'] as String).toLocal(),
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
      );
}

/// Admin: one claim in the "waiting to be handed out" list.
class AdminCardClaim {
  const AdminCardClaim({
    required this.id,
    required this.code,
    required this.title,
    required this.byName,
    required this.username,
    required this.status,
    required this.cardsUsed,
    required this.claimedAt,
    required this.expiresAt,
    this.displayName,
    this.avatarUrl,
    this.redeemedAt,
  });
  final String id;
  final String code;
  final String title;
  final String byName;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final ClaimState status;
  final int cardsUsed;
  final DateTime claimedAt;
  final DateTime expiresAt;
  final DateTime? redeemedAt;

  factory AdminCardClaim.fromMap(Map<String, dynamic> m) => AdminCardClaim(
        id: m['id'] as String,
        code: m['code'] as String? ?? '',
        title: m['title'] as String? ?? '',
        byName: m['vendor_name'] as String? ?? 'TT Spot',
        username: m['username'] as String? ?? '',
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        status: ClaimState.fromDb(m['status'] as String?),
        cardsUsed: (m['cards_used'] as num?)?.toInt() ?? 0,
        claimedAt: DateTime.parse(m['claimed_at'] as String).toLocal(),
        expiresAt: DateTime.parse(m['expires_at'] as String).toLocal(),
        redeemedAt: m['redeemed_at'] == null ? null : DateTime.parse(m['redeemed_at'] as String).toLocal(),
      );
}

/// Tunables the admin edits (`platform_settings`).
class CardSettings {
  const CardSettings({this.common = 70, this.rare = 25, this.legendary = 5, this.boxCost = 100, this.tradeMax = 9});
  final num common;
  final num rare;
  final num legendary;
  final int boxCost;
  final int tradeMax;

  num get total => common + rare + legendary;
  double pct(CardRarity r) => total == 0 ? 0 : 100 * (switch (r) { CardRarity.common => common, CardRarity.rare => rare, CardRarity.legendary => legendary }) / total;

  /// The odds as set, e.g. "89.5% common · 10% rare · 0.5% secret".
  String get summary => [for (final r in CardRarity.values) '${fmtPct(pct(r))}% ${r.label.toLowerCase()}'].join(' · ');

  factory CardSettings.fromSettings(Map<String, dynamic> s) {
    final odds = (s['card_odds'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CardSettings(
      common: (odds['common'] as num?) ?? 70,
      rare: (odds['rare'] as num?) ?? 25,
      legendary: (odds['legendary'] as num?) ?? 5,
      boxCost: (s['box_points_cost'] as num?)?.toInt() ?? 100,
      tradeMax: (s['trade_max_cards'] as num?)?.toInt() ?? 9,
    );
  }
}

/// What a box can drop right now (`box_odds`), computed on the server from
/// the same weights the roll uses: the legendary run already counted, cards
/// of one rarity sharing its slice. `pity*` = the odds on a guaranteed box.
class BoxOdds {
  const BoxOdds({
    required this.rarity,
    required this.pityRarity,
    required this.cards,
    required this.pityCards,
    required this.legendaryTotal,
    required this.legendaryIssued,
    required this.pityEvery,
    this.pityStreak,
  });

  /// Percent per rarity and per card id, for a plain box.
  final Map<CardRarity, double> rarity;
  final Map<CardRarity, double> pityRarity;
  final Map<String, double> cards;
  final Map<String, double> pityCards;
  /// The limited legendary run: copies that will ever exist, and how many are out.
  final int legendaryTotal;
  final int legendaryIssued;
  /// A rare or better is guaranteed at least once in this many boxes.
  final int pityEvery;
  /// My boxes since my last rare or better. Null when signed out.
  final int? pityStreak;

  int get legendaryLeft => (legendaryTotal - legendaryIssued).clamp(0, legendaryTotal);
  bool get soldOut => legendaryLeft <= 0;
  /// The guarantee lands within this many more boxes (1 = the next one).
  int get pityLeft => (pityEvery - (pityStreak ?? 0)).clamp(1, pityEvery);
  bool get pityNext => pityLeft == 1;

  double pct(CardRarity r) => rarity[r] ?? 0;
  double cardPct(String id) => cards[id] ?? 0;

  /// "89.5% common · 10% rare · 0.5% secret", skipping what can't drop.
  String get summary => [
        for (final r in CardRarity.values)
          if (pct(r) > 0) '${fmtPct(pct(r))}% ${r.label.toLowerCase()}',
      ].join(' · ');

  /// "Only 100 exist · 99 left", or "Sold out" once the run is gone. Short:
  /// for next to a Secret pill.
  String get limitedLine => soldOut ? 'Sold out' : 'Only $legendaryTotal exist · $legendaryLeft left';

  /// "Only 100 Secret cards exist · 99 left": the same, where nothing else
  /// names the tier. "N left" never splits across lines.
  String get secretLine => soldOut ? 'Secret cards sold out' : 'Only $legendaryTotal Secret cards exist · $legendaryLeft left';

  String get pityLine => pityNext ? 'Your next box is guaranteed Rare or better' : 'Rare or better guaranteed within $pityLeft more boxes';

  factory BoxOdds.fromMap(Map<String, dynamic> m) {
    Map<CardRarity, double> rarities(Object? v) {
      final o = (v as Map?)?.cast<String, dynamic>() ?? const {};
      return {for (final r in CardRarity.values) r: (o[r.db] as num?)?.toDouble() ?? 0};
    }

    final list = ((m['cards'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    return BoxOdds(
      rarity: rarities(m['odds']),
      pityRarity: rarities(m['pity_odds']),
      cards: {for (final c in list) c['card_id'] as String: (c['percent'] as num?)?.toDouble() ?? 0},
      pityCards: {for (final c in list) c['card_id'] as String: (c['pity_percent'] as num?)?.toDouble() ?? 0},
      legendaryTotal: (m['legendary_total'] as num?)?.toInt() ?? 0,
      legendaryIssued: (m['legendary_issued'] as num?)?.toInt() ?? 0,
      pityEvery: (m['pity_every'] as num?)?.toInt() ?? 10,
      pityStreak: (m['pity_streak'] as num?)?.toInt(),
    );
  }
}

/// A percentage without noise: 89.5 → "89.5", 10 → "10", 22.375 → "22.4",
/// 4.7619 → "4.76", 0.5 → "0.5". Anything above 0 that would round to 0
/// reads "<0.01".
String fmtPct(num v) {
  if (v <= 0) return '0';
  final s = v.toStringAsFixed(v >= 10 ? 1 : 2);
  final trimmed = s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  return trimmed == '0' ? '<0.01' : trimmed;
}
