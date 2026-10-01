import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/media.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/plate_blur.dart';
import '../../../core/utils/thumbnails.dart';
import '../domain/car_documents.dart';
import '../domain/car_meet.dart';
import '../domain/car_mod.dart';

/// What hangs off a car besides the car itself: the mods log and the
/// owner-only documents.
///
/// Mods are read and written through RPCs: members cannot read the price
/// column of `car_mods` at all, and `car_mod_list` fills it in for the owner.
class GarageRepository {
  GarageRepository(this._client);
  final SupabaseClient _client;

  // ------------------------------------------------------------------ mods ---

  Future<List<CarMod>> carMods(String carId) async {
    final rows = await _client.rpc('car_mod_list', params: {'p_car': carId}) as List;
    return rows.map((r) => CarMod.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  /// Adds a mod ([id] null) or overwrites one. Returns its id.
  Future<String> saveMod({
    String? id,
    required String carId,
    required ModCategory category,
    required String title,
    required DateTime doneOn,
    double? cost,
    String? shop,
    String? vendorId,
    String? description,
    required List<String> photoUrls,
    required bool isPrivate,
  }) async {
    final res = await _client.rpc('save_car_mod', params: {
      'p_id': id,
      'p_car': carId,
      'p_category': category.name,
      'p_title': title.trim(),
      'p_done_on': _day(doneOn),
      'p_cost': cost,
      'p_shop': shop,
      'p_vendor': vendorId,
      'p_description': description,
      'p_photo_urls': photoUrls,
      'p_private': isPrivate,
    });
    return res as String;
  }

  Future<void> deleteMod(String id) => _client.from('car_mods').delete().eq('id', id);

  /// `car-photos/<userId>/mods/<micros>.<ext>` plus its grid thumbnail.
  Future<String> uploadModPhoto({required String userId, required Uint8List bytes}) async {
    final type = imageContentType(bytes);
    final ext = switch (type) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };
    final path = '$userId/mods/${DateTime.now().microsecondsSinceEpoch}.$ext';
    final bucket = _client.storage.from('car-photos');
    await Future.wait([
      bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type, cacheControl: kImmutableCacheControl)),
      uploadThumb(bucket, path, bytes),
    ]);
    return bucket.getPublicUrl(path);
  }

  // ----------------------------------------------------------------- meets ---

  /// Meets this car went to (RSVP'd or checked in with it). Two small reads:
  /// both tables are readable by members, and the `events` embed comes back
  /// null for a meet the viewer may not see.
  Future<List<CarMeet>> carMeets(String carId) async {
    const event = 'events(id, title, starts_at, venue_name, cover_url, status)';
    final res = await Future.wait([
      _client.from('event_attendees').select('event_id, $event').eq('car_id', carId).limit(200),
      _client.from('checkins').select('event_id, $event').eq('car_id', carId).limit(200),
    ]);
    return CarMeet.merge(attended: res[0], checkins: res[1]);
  }

  // ------------------------------------------------------------- documents ---

  /// Null when nothing is saved yet (or it is not my car: RLS hides it).
  Future<CarDocuments?> documents(String carId) async {
    final row = await _client.from('car_documents').select().eq('car_id', carId).maybeSingle();
    return row == null ? null : CarDocuments.fromMap(row);
  }

  Future<void> saveDocuments(CarDocuments docs) => _client.from('car_documents').upsert(docs.toMap());

  Future<void> deleteDocuments(String carId) => _client.from('car_documents').delete().eq('car_id', carId);

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final garageRepositoryProvider = Provider<GarageRepository>((ref) => GarageRepository(ref.watch(supabaseProvider)));
