import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../domain/portrait_style.dart';

/// `car_portraits` reads, the `car-portrait` edge function, and the choose RPC.
class PortraitRepository {
  PortraitRepository(this._client);
  final SupabaseClient _client;

  Future<List<CarPortrait>> fetchPortraits(String carId) async {
    final rows = await _client.from('car_portraits').select().eq('car_id', carId).order('created_at', ascending: false);
    return rows.map(CarPortrait.fromMap).toList();
  }

  /// Books the job and creates the Kie task. Returns the new portrait id.
  /// The server enforces one pending per car and the daily limit.
  Future<String> request({required String carId, required String styleId}) async {
    try {
      final res = await _client.functions.invoke('car-portrait', body: {'carId': carId, 'style': styleId});
      final data = res.data;
      if (data is Map && data['portraitId'] is String) return data['portraitId'] as String;
      throw const AppException('Could not start the portrait. Try again.');
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map ? d['error'] : null;
      throw AppException(msg is String && msg.isNotEmpty ? msg : 'Could not start the portrait. Try again.');
    }
  }

  /// Makes a ready portrait the car's picture.
  Future<void> choose(String portraitId) => _client.rpc('choose_car_portrait', params: {'p_portrait': portraitId});

  /// Back to the real photos (owner-only update through cars RLS).
  Future<void> clear(String carId) => _client.from('cars').update({'portrait_url': null}).eq('id', carId);

  /// Fires on any insert/update to this car's portraits (status flips).
  RealtimeChannel subscribe(String carId, void Function() onChange) {
    return _client
        .channel('portraits:$carId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'car_portraits',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'car_id', value: carId),
          callback: (_) => onChange(),
        )
        .subscribe();
  }
}

final portraitRepositoryProvider = Provider<PortraitRepository>((ref) => PortraitRepository(ref.watch(supabaseProvider)));
