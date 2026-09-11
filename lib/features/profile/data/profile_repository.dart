import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/car.dart';

/// `cars` reads/writes, car photo uploads, and profile stats.
class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  Future<List<Car>> fetchCars(String ownerId) async {
    final rows = await _client.from('cars').select().eq('owner_id', ownerId).order('created_at', ascending: false);
    return rows.map(Car.fromMap).toList();
  }

  Future<Car?> fetchCar(String id) async {
    final row = await _client.from('cars').select().eq('id', id).maybeSingle();
    return row == null ? null : Car.fromMap(row);
  }

  Future<ProfileStats> fetchStats(String userId) async {
    final results = await Future.wait<dynamic>([
      _client.from('cars').select('id').eq('owner_id', userId),
      _client.from('events').select('id').eq('organizer_id', userId).eq('status', 'active'),
      _client.from('event_attendees').select('event_id').eq('user_id', userId),
      _client.from('checkins').select('event_id, events(place_id)').eq('user_id', userId),
    ]);
    final checkins = results[3] as List;
    final places = checkins.map((r) => (r['events'] as Map<String, dynamic>?)?['place_id']).whereType<String>().toSet();
    return ProfileStats(
      cars: (results[0] as List).length,
      organised: (results[1] as List).length,
      attended: (results[2] as List).length,
      went: checkins.length,
      places: places.length,
    );
  }

  Future<Car> insertCar({
    required String ownerId,
    required String make,
    required String model,
    int? year,
    String? description,
    required List<String> photoUrls,
  }) async {
    final row = await _client
        .from('cars')
        .insert({
          'owner_id': ownerId,
          'make': make.trim(),
          'model': model.trim(),
          'year': ?year,
          'description': ?description?.trim(),
          'photo_urls': photoUrls,
        })
        .select()
        .single();
    return Car.fromMap(row);
  }

  Future<Car> updateCar({
    required String id,
    required String make,
    required String model,
    int? year,
    String? description,
    required List<String> photoUrls,
  }) async {
    final row = await _client
        .from('cars')
        .update({
          'make': make.trim(),
          'model': model.trim(),
          'year': year,
          'description': description?.trim(),
          'photo_urls': photoUrls,
        })
        .eq('id', id)
        .select()
        .single();
    return Car.fromMap(row);
  }

  Future<void> deleteCar(String id) => _client.from('cars').delete().eq('id', id);

  /// Uploads to `car-photos/<userId>/<millis>_<index>.jpg`, returns the public URL.
  Future<String> uploadCarPhoto({required String userId, required Uint8List bytes, required int index}) async {
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
    await _client.storage.from('car-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return _client.storage.from('car-photos').getPublicUrl(path);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseProvider)),
);
