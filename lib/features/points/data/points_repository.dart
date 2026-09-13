import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/points.dart';

/// Points ledger, earn rules, referral codes, and the QR RPCs.
class PointsRepository {
  PointsRepository(this._client);
  final SupabaseClient _client;

  Future<int> balance(String userId) async {
    final row = await _client.from('profiles').select('points').eq('id', userId).maybeSingle();
    return (row?['points'] as num?)?.toInt() ?? 0;
  }

  Future<List<PointEntry>> history() async {
    final rows = await _client.rpc('my_point_history', params: {'p_limit': 100}) as List;
    return rows.map((r) => PointEntry.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  Future<List<PointRule>> rules() async {
    final rows = await _client.from('point_rules').select().order('sort', ascending: true);
    return rows.map(PointRule.fromMap).toList();
  }

  // -------------------------------------------------------------- referrals ---

  Future<bool> claimReferral(String code) async {
    final v = await _client.rpc('claim_referral', params: {'p_code': code});
    return v as bool? ?? false;
  }

  /// How many people I brought in, and how many of those have been paid out.
  Future<({int total, int rewarded})> myReferrals(String me) async {
    final rows = await _client.from('referrals').select('rewarded_at').eq('referrer_id', me);
    return (total: rows.length, rewarded: rows.where((r) => r['rewarded_at'] != null).length);
  }

  // --------------------------------------------------------------------- qr ---

  Future<String> myQrPayload() async => await _client.rpc('my_qr_payload') as String;

  Future<void> rotateMyQr() => _client.rpc('rotate_my_qr');

  /// Scan a friend's QR → instant friends. Returns their user id.
  Future<String> addFriendByQr({required String username, required String token}) async {
    final v = await _client.rpc('add_friend_by_qr', params: {'p_username': username, 'p_token': token});
    return v as String;
  }

  /// Organiser: the current rotating payload for the meet's check-in QR.
  Future<String> eventQrPayload(String eventId) async => await _client.rpc('event_qr_payload', params: {'p_event': eventId}) as String;

  /// Attendee: check in with a scanned code. Returns whether it was new and the points.
  Future<({bool isNew, int points})> checkinByQr({required String eventId, required String code, double? lat, double? lng}) async {
    final v = await _client.rpc('checkin_by_qr', params: {'p_event': eventId, 'p_code': code, 'p_lat': ?lat, 'p_lng': ?lng});
    final m = (v as Map).cast<String, dynamic>();
    return (isNew: m['new'] as bool? ?? false, points: (m['points'] as num?)?.toInt() ?? 0);
  }
}

final pointsRepositoryProvider = Provider<PointsRepository>((ref) => PointsRepository(ref.watch(supabaseProvider)));
