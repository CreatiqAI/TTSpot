import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/media.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/plate_blur.dart';
import '../../../core/utils/thumbnails.dart';
import '../domain/car.dart';
import '../domain/car_recognition.dart';

/// `cars` reads/writes, car photo uploads, and profile stats.
class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  Future<List<Car>> fetchCars(String ownerId) async {
    final rows = await _client.from('cars').select().eq('owner_id', ownerId).order('is_default', ascending: false).order('created_at', ascending: false);
    return rows.map(Car.fromMap).toList();
  }

  Future<void> setDefaultCar(String carId) => _client.rpc('set_default_car', params: {'p_car': carId});

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
    String? color,
    String? specs,
    String? bodyStyle,
  }) async {
    final row = await _client
        .from('cars')
        .insert({
          'color': color,
          'owner_id': ownerId,
          'make': make.trim(),
          'model': model.trim(),
          'year': ?year,
          'description': ?description?.trim(),
          'photo_urls': photoUrls,
          'specs': ?_blank(specs),
          'body_style': ?_blank(bodyStyle),
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
    String? color,
    String? specs,
    String? bodyStyle,
  }) async {
    final row = await _client
        .from('cars')
        .update({
          'color': color,
          'make': make.trim(),
          'model': model.trim(),
          'year': year,
          'description': description?.trim(),
          'photo_urls': photoUrls,
          'specs': _blank(specs),
          'body_style': _blank(bodyStyle),
        })
        .eq('id', id)
        .select()
        .single();
    return Car.fromMap(row);
  }

  Future<void> deleteCar(String id) => _client.from('cars').delete().eq('id', id);

  /// Uploads to `car-photos/<userId>/<millis>_<index>.<ext>` (plus its grid
  /// thumbnail), returns the public URL. JPEG straight from the picker; PNG
  /// once a plate was blurred.
  Future<String> uploadCarPhoto({required String userId, required Uint8List bytes, required int index}) async {
    final type = imageContentType(bytes);
    final ext = switch (type) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_$index.$ext';
    final bucket = _client.storage.from('car-photos');
    await Future.wait([
      bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type, cacheControl: kImmutableCacheControl)),
      uploadThumb(bucket, path, bytes),
    ]);
    return bucket.getPublicUrl(path);
  }

  /// Asks the `recognize-car` edge function what the photo shows. The bytes go
  /// up as a data URL, so the unblurred original never touches storage;
  /// [photoUrl] is for a photo that is already in the car-photos bucket.
  Future<CarRecognition> recognizeCar({Uint8List? bytes, String? photoUrl}) async {
    assert(bytes != null || photoUrl != null);
    final body = bytes != null
        ? {'image': 'data:${imageContentType(bytes)};base64,${base64Encode(bytes)}'}
        : {'photoUrl': photoUrl};
    final res = await _client.functions.invoke('recognize-car', body: body);
    final data = res.data;
    if (data is Map && data['error'] != null) throw Exception(data['error']);
    return CarRecognition.fromMap((data as Map).cast<String, dynamic>());
  }

  static String? _blank(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseProvider)),
);
