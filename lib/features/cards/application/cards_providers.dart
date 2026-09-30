import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../admin/application/admin_providers.dart';
import '../../points/application/points_providers.dart';
import '../../social/application/notification_providers.dart';
import '../data/cards_repository.dart';
import '../domain/cards.dart';

/// The 7 designs. Rarely changes; refetched after an admin edit.
final cardTypesProvider = FutureProvider<List<CardType>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(cardsRepositoryProvider).cardTypes();
});

final cardSettingsProvider = FutureProvider<CardSettings>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const CardSettings());
  return ref.watch(cardsRepositoryProvider).settings();
});

/// What a box drops right now, the legendary run and my pity count.
/// Refetched after every box I open and every odds edit.
final boxOddsProvider = FutureProvider<BoxOdds>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(cardsRepositoryProvider).boxOdds();
});

final myCardsProvider = FutureProvider<List<UserCard>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(cardsRepositoryProvider).myCards();
});

/// Types + my copies, counted.
final myCollectionProvider = FutureProvider<CardCollection>((ref) async {
  final types = await ref.watch(cardTypesProvider.future);
  final cards = await ref.watch(myCardsProvider.future);
  return CardCollection(types: types, cards: cards);
});

final myBoxesProvider = FutureProvider<List<CardBox>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(cardsRepositoryProvider).myBoxes();
});

/// Boxes waiting to be opened. Drives the "open your box" nudges.
final sealedBoxesProvider = Provider<List<CardBox>>((ref) => (ref.watch(myBoxesProvider).value ?? const []).where((b) => b.sealed).toList());

/// A member's held cards as counts, for their profile's Cards tab.
final userCardCountsProvider = FutureProvider.autoDispose.family<Map<String, int>, String>((ref, userId) => ref.watch(cardsRepositoryProvider).publicCards(userId));

final friendCardsProvider = FutureProvider.autoDispose.family<List<UserCard>, String>((ref, userId) => ref.watch(cardsRepositoryProvider).friendCards(userId));

final myTradesProvider = FutureProvider<List<CardTrade>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(cardsRepositoryProvider).myTrades();
});

/// Offers waiting for my answer.
final incomingTradeCountProvider = Provider<int>((ref) {
  final me = ref.watch(currentUserIdProvider);
  return (ref.watch(myTradesProvider).value ?? const []).where((t) => t.status == TradeStatus.proposed && t.toUser == me).length;
});

final cardRewardShopProvider = FutureProvider<List<CardReward>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(cardsRepositoryProvider).shop();
});

final myCardClaimsProvider = FutureProvider<List<CardRewardClaim>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(cardsRepositoryProvider).myClaims();
});

final cardClaimPayloadProvider = FutureProvider.family<String, String>((ref, claimId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(cardsRepositoryProvider).claimPayload(claimId);
});

// Admin lists watch the user id so a switch never shows the previous admin's data.
final adminCardRewardsProvider = FutureProvider<List<CardReward>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(cardsRepositoryProvider).adminRewards();
});

final adminCardClaimsProvider = FutureProvider<List<AdminCardClaim>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(cardsRepositoryProvider).adminClaims();
});

final adminCardStatsProvider = FutureProvider<Map<String, dynamic>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(cardsRepositoryProvider).adminStats();
});

class CardsActions {
  CardsActions(this._ref);
  final Ref _ref;
  CardsRepository get _repo => _ref.read(cardsRepositoryProvider);

  void refreshCollection() {
    _ref.invalidate(myCardsProvider);
    _ref.invalidate(myBoxesProvider);
    _ref.invalidate(boxOddsProvider); // pity count and legendary stock move with every box
  }

  /// Server rolls the card. The caller animates the reveal.
  Future<BoxResult> openBox(String boxId) async {
    final r = await _repo.openBox(boxId);
    refreshCollection();
    return r;
  }

  Future<String> buyBox() async {
    final id = await _repo.buyBox();
    _ref.invalidate(myBoxesProvider);
    _ref.read(pointsActionsProvider).refreshBalance();
    return id;
  }

  Future<String> proposeTrade({required String to, required List<String> offer, required List<String> request, String? message}) async {
    final id = await _repo.proposeTrade(to: to, offer: offer, request: request, message: message);
    _ref.invalidate(myTradesProvider);
    return id;
  }

  Future<void> decideTrade(String id, {required bool accept}) async {
    try {
      await _repo.decideTrade(id, accept: accept);
    } finally {
      _ref.invalidate(myTradesProvider);
      refreshCollection();
      _ref.invalidate(notificationsProvider);
    }
  }

  Future<void> cancelTrade(String id) async {
    await _repo.cancelTrade(id);
    _ref.invalidate(myTradesProvider);
  }

  Future<({String id, DateTime expiresAt, int cardsUsed})> claimReward(String rewardId) async {
    final r = await _repo.claimReward(rewardId);
    _ref.invalidate(cardRewardShopProvider);
    _ref.invalidate(myCardClaimsProvider);
    refreshCollection();
    return r;
  }

  Future<CardClaimLookup> lookup({required String claimId, required String code}) => _repo.lookupClaim(claimId: claimId, code: code);

  Future<void> redeem({required String claimId, required String code, String? note}) async {
    await _repo.redeemClaim(claimId: claimId, code: code, note: note);
    _ref.invalidate(adminCardClaimsProvider);
    _ref.invalidate(adminCardStatsProvider);
  }

  // --------------------------------------------------------------- admin ---

  Future<void> saveCardType(CardType t) async {
    await _repo.saveCardType(t);
    _ref.invalidate(cardTypesProvider);
  }

  Future<String> saveReward({
    String? id,
    required String title,
    String? description,
    String? terms,
    String? imageUrl,
    String? vendorId,
    required int common,
    required int rare,
    required int legendary,
    required bool fullSet,
    int? stock,
    required int perUser,
    DateTime? starts,
    DateTime? ends,
    required bool active,
  }) async {
    final v = await _repo.saveReward(
      id: id, title: title, description: description, terms: terms, imageUrl: imageUrl, vendorId: vendorId,
      common: common, rare: rare, legendary: legendary, fullSet: fullSet, stock: stock, perUser: perUser, starts: starts, ends: ends, active: active,
    );
    _ref.invalidate(adminCardRewardsProvider);
    _ref.invalidate(cardRewardShopProvider);
    return v;
  }

  Future<int> grantBoxes({required String username, required int count}) async {
    final n = await _repo.grantBoxes(username: username, count: count);
    _ref.invalidate(adminCardStatsProvider);
    return n;
  }

  Future<void> setOdds({required num common, required num rare, required num legendary}) async {
    await _ref.read(adminActionsProvider).setSetting('card_odds', {'common': common, 'rare': rare, 'legendary': legendary});
    _ref.invalidate(cardSettingsProvider);
    _ref.invalidate(boxOddsProvider);
  }

  /// How many legendary copies will ever exist.
  Future<void> setLegendaryTotal(int total) async {
    await _ref.read(adminActionsProvider).setSetting('legendary_stock_total', total);
    _ref.invalidate(boxOddsProvider);
  }

  Future<void> setBoxCost(int cost) async {
    await _ref.read(adminActionsProvider).setSetting('box_points_cost', cost);
    _ref.invalidate(cardSettingsProvider);
  }
}

final cardsActionsProvider = Provider<CardsActions>((ref) => CardsActions(ref));
