import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/cards.dart';

/// Blind boxes, my cards, trades and card prizes. Every write is an RPC.
class CardsRepository {
  CardsRepository(this._client);
  final SupabaseClient _client;

  List<Map<String, dynamic>> _rows(Object? v) => (v as List).map((r) => (r as Map).cast<String, dynamic>()).toList();

  // ------------------------------------------------------------ catalogue ---

  Future<List<CardType>> cardTypes() async {
    final rows = await _client.from('card_types').select().order('sort', ascending: true);
    return rows.map(CardType.fromMap).toList();
  }

  /// Odds, box price and trade limit. Readable by every member (RLS).
  Future<CardSettings> settings() async {
    final rows = await _client.from('platform_settings').select('key, value').inFilter('key', ['card_odds', 'box_points_cost', 'trade_max_cards']);
    return CardSettings.fromSettings({for (final r in rows) r['key'] as String: r['value']});
  }

  // ---------------------------------------------------------------- mine ---

  Future<List<UserCard>> myCards() async => _rows(await _client.rpc('my_cards')).map(UserCard.fromMap).toList();

  Future<List<CardBox>> myBoxes() async => _rows(await _client.rpc('my_boxes')).map(CardBox.fromMap).toList();

  Future<List<UserCard>> friendCards(String userId) async =>
      _rows(await _client.rpc('friend_cards', params: {'p_user': userId})).map((m) => UserCard.fromMap({...m, 'status': 'held', 'source': 'box'})).toList();

  /// Someone else's collection as counts per card (anyone signed in).
  Future<Map<String, int>> publicCards(String userId) async {
    final rows = _rows(await _client.rpc('public_cards', params: {'p_user': userId}));
    return {for (final r in rows) r['card_id'] as String: (r['held'] as num).toInt()};
  }

  Future<BoxResult> openBox(String boxId) async {
    final v = await _client.rpc('open_box', params: {'p_box': boxId});
    return BoxResult.fromMap((v as Map).cast<String, dynamic>());
  }

  /// Spend points on a sealed box. Returns its id.
  Future<String> buyBox() async => await _client.rpc('buy_box') as String;

  // -------------------------------------------------------------- trades ---

  Future<String> proposeTrade({required String to, required List<String> offer, required List<String> request, String? message}) async {
    final v = await _client.rpc('propose_trade', params: {'p_to': to, 'p_offer': offer, 'p_request': request, 'p_message': ?message});
    return v as String;
  }

  Future<void> decideTrade(String id, {required bool accept}) => _client.rpc('decide_trade', params: {'p_trade': id, 'p_accept': accept});

  Future<void> cancelTrade(String id) => _client.rpc('cancel_trade', params: {'p_trade': id});

  Future<List<CardTrade>> myTrades() async => _rows(await _client.rpc('my_trades', params: {'p_limit': 100})).map(CardTrade.fromMap).toList();

  // -------------------------------------------------------------- prizes ---

  Future<List<CardReward>> shop() async => _rows(await _client.rpc('card_reward_shop')).map(CardReward.fromMap).toList();

  Future<({String id, DateTime expiresAt, int cardsUsed})> claimReward(String rewardId) async {
    final v = await _client.rpc('claim_card_reward', params: {'p_reward': rewardId});
    final m = (v as Map).cast<String, dynamic>();
    return (id: m['id'] as String, expiresAt: DateTime.parse(m['expires_at'] as String).toLocal(), cardsUsed: (m['cards_used'] as num?)?.toInt() ?? 0);
  }

  Future<List<CardRewardClaim>> myClaims() async => _rows(await _client.rpc('my_card_reward_claims', params: {'p_limit': 100})).map(CardRewardClaim.fromMap).toList();

  Future<String> claimPayload(String claimId) async => await _client.rpc('card_reward_claim_payload', params: {'p_claim': claimId}) as String;

  Future<CardClaimLookup> lookupClaim({required String claimId, required String code}) async {
    final v = await _client.rpc('lookup_card_reward_claim', params: {'p_claim': claimId, 'p_code': code});
    return CardClaimLookup.fromMap((v as Map).cast<String, dynamic>());
  }

  Future<void> redeemClaim({required String claimId, required String code, String? note}) =>
      _client.rpc('redeem_card_reward_claim', params: {'p_claim': claimId, 'p_code': code, 'p_note': ?note});

  // --------------------------------------------------------------- admin ---

  Future<void> saveCardType(CardType t) => _client.rpc('admin_save_card_type', params: {
        'p_id': t.id,
        'p_name': t.name,
        'p_rarity': t.rarity.db,
        'p_number': t.number,
        'p_description': t.description,
        'p_art_url': t.artUrl,
        'p_color': t.hex,
        'p_active': t.active,
        'p_set': t.setId,
      });

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
    final v = await _client.rpc('admin_save_card_reward', params: {
      'p_id': id,
      'p_title': title,
      'p_description': description,
      'p_terms': terms,
      'p_image_url': imageUrl,
      'p_vendor': vendorId,
      'p_common': common,
      'p_rare': rare,
      'p_legendary': legendary,
      'p_full_set': fullSet,
      'p_stock': stock,
      'p_per_user': perUser,
      'p_starts': starts?.toUtc().toIso8601String(),
      'p_ends': ends?.toUtc().toIso8601String(),
      'p_active': active,
    });
    return v as String;
  }

  Future<List<CardReward>> adminRewards() async => _rows(await _client.rpc('admin_card_rewards')).map(CardReward.fromMap).toList();

  Future<List<AdminCardClaim>> adminClaims() async => _rows(await _client.rpc('admin_card_reward_claims', params: {'p_limit': 100})).map(AdminCardClaim.fromMap).toList();

  Future<int> grantBoxes({required String username, required int count}) async {
    final v = await _client.rpc('admin_grant_boxes', params: {'p_username': username, 'p_count': count});
    return (v as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>> adminStats() async => ((await _client.rpc('admin_card_stats')) as Map).cast<String, dynamic>();
}

final cardsRepositoryProvider = Provider<CardsRepository>((ref) => CardsRepository(ref.watch(supabaseProvider)));
