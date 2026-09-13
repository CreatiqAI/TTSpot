import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/points.dart';
import '../domain/verification.dart';

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

extension PointsVerificationRepo on PointsRepository {
  // ---------------------------------------------------------- stickers ---

  /// Uploads the proof photo to `post-photos/<uid>/verify/…` and returns its public URL.
  Future<String> uploadProof({required String userId, required Uint8List bytes}) async {
    final path = '$userId/verify/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage.from('post-photos').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    return _client.storage.from('post-photos').getPublicUrl(path);
  }

  Future<String> submitVerification({required String placeId, required String code, required String photoUrl, double? lat, double? lng}) async {
    final v = await _client.rpc('submit_spot_verification', params: {
      'p_place': placeId,
      'p_code': code,
      'p_photo_url': photoUrl,
      'p_lat': lat,
      'p_lng': lng,
    });
    return (v as Map)['id'] as String;
  }

  /// Runs the AI check server-side. Never throws for a slow/absent AI: the
  /// function parks the row for a human instead.
  Future<VerifyResult> runVerification(String id) async {
    final res = await _client.functions.invoke('verify-spot-photo', body: {'id': id});
    final data = res.data;
    if (data is Map && data['error'] != null) throw Exception(data['error']);
    return VerifyResult.fromMap((data as Map).cast<String, dynamic>());
  }

  Future<List<SpotVerification>> myVerifications() async {
    final rows = await _client.rpc('my_spot_verifications', params: {'p_limit': 30}) as List;
    return rows.map((r) => SpotVerification.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  Future<List<SpotVerification>> adminQueue() async {
    final rows = await _client.rpc('admin_review_queue', params: {'p_limit': 100}) as List;
    return rows.map((r) => SpotVerification.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  Future<void> reviewVerification(String id, {required bool approve, String? note}) =>
      _client.rpc('review_spot_verification', params: {'p_id': id, 'p_approve': approve, 'p_note': ?note});
}

final pointsRepositoryProvider = Provider<PointsRepository>((ref) => PointsRepository(ref.watch(supabaseProvider)));
