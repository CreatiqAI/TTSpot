import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../domain/car_toy.dart';

/// The toy pipeline's client side: `request_car_toy` and a realtime channel
/// on the owner's cars (migration 0106; the `car-toy` edge function does the
/// rendering and writes `cars.toy_*` itself).
class ToyRepository {
  ToyRepository(this._client);
  final SupabaseClient _client;

  /// Asks for a toy of one of my cars. Returns the job id, or null when
  /// nothing was booked (toys off, same cover already done, one pending).
  /// [manual] = "Remake": the server then raises instead of staying quiet
  /// (still pending, daily cap reached), as an [AppException].
  Future<String?> request(String carId, {bool manual = false}) async {
    try {
      final res = await _client.rpc('request_car_toy', params: {'p_car': carId, 'p_manual': manual});
      return res is String && res.isNotEmpty ? res : null;
    } on PostgrestException catch (e) {
      throw AppException(e.message.isNotEmpty ? e.message : 'Could not start the toy. Try again.');
    }
  }

  /// "Make my toy car": records my OK for Kie.ai on the server
  /// (`settings.ai_consent.toy`, migration 0125) and books toys for my cars
  /// that have none. Returns how many were booked.
  Future<int> allowToyCars() async {
    try {
      final res = await _client.rpc('allow_toy_cars');
      return res is num ? res.toInt() : 0;
    } on PostgrestException catch (e) {
      throw AppException(e.message.isNotEmpty ? e.message : 'Could not start the toy. Try again.');
    }
  }

  /// How many toy renders one of my cars has left today (`car_toy_quota`,
  /// migration 0110).
  Future<ToyQuota> quota(String carId) async {
    try {
      final res = await _client.rpc('car_toy_quota', params: {'p_car': carId});
      return ToyQuota.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw AppException(e.message.isNotEmpty ? e.message : 'Could not check the toy renders left.');
    }
  }

  /// Fires on any change to [ownerId]'s cars (toy_status flips included).
  /// [onChange] gets the changed car's id when the payload carries it.
  RealtimeChannel subscribeCars(String ownerId, void Function(String? carId) onChange) {
    return _client
        .channel('cars:$ownerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cars',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'owner_id', value: ownerId),
          callback: (payload) => onChange(payload.newRecord['id'] as String? ?? payload.oldRecord['id'] as String?),
        )
        .subscribe();
  }
}

final toyRepositoryProvider = Provider<ToyRepository>((ref) => ToyRepository(ref.watch(supabaseProvider)));
