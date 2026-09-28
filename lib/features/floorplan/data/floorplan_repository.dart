import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/floorplan.dart';

/// Event floorplans: levels, pins, my spot, plus the event invite code.
/// Tables: event_floor_levels, event_floor_pins, event_positions.
/// Storage: bucket `event-floorplans`, objects under `<event_id>/…`.
class FloorplanRepository {
  FloorplanRepository(this._client);
  final SupabaseClient _client;

  static const bucket = 'event-floorplans';

  String _publicUrl(String path) => _client.storage.from(bucket).getPublicUrl(path);

  // ------------------------------------------------------------- levels ---

  Future<List<FloorLevel>> levels(String eventId) async {
    final rows = await _client.from('event_floor_levels').select('*, event_floor_pins(*)').eq('event_id', eventId).order('sort').order('created_at');
    return (rows as List).map((r) => FloorLevel.fromMap((r as Map).cast<String, dynamic>(), publicUrl: _publicUrl)).toList();
  }

  Future<String> addLevel({required String eventId, required String name, required int sort}) async {
    final row = await _client.from('event_floor_levels').insert({'event_id': eventId, 'name': name.trim(), 'sort': sort}).select('id').single();
    return row['id'] as String;
  }

  Future<void> renameLevel(String levelId, String name) => _client.from('event_floor_levels').update({'name': name.trim()}).eq('id', levelId);

  /// Writes `sort` = list index for every level, in order.
  Future<void> reorderLevels(List<String> levelIds) async {
    for (var i = 0; i < levelIds.length; i++) {
      await _client.from('event_floor_levels').update({'sort': i}).eq('id', levelIds[i]);
    }
  }

  Future<void> deleteLevel(FloorLevel level) async {
    await _client.from('event_floor_levels').delete().eq('id', level.id);
    if (level.imagePath != null) {
      try {
        await _client.storage.from(bucket).remove([level.imagePath!]);
      } catch (_) {/* orphaned file is harmless */}
    }
  }

  /// Uploads a plan image to `event-floorplans/<event_id>/<level_id>-<ms>.<ext>` and
  /// points the level at it. Deletes the old file afterwards.
  Future<void> setLevelImage({required FloorLevel level, required Uint8List bytes, required String ext, required int width, required int height}) async {
    final e = switch (ext.toLowerCase()) { 'png' => 'png', 'webp' => 'webp', _ => 'jpg' };
    final mime = switch (e) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
    final path = '${level.eventId}/${level.id}-${DateTime.now().millisecondsSinceEpoch}.$e';
    await _client.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: true));
    await _client.from('event_floor_levels').update({'image_path': path, 'image_w': width, 'image_h': height}).eq('id', level.id);
    if (level.imagePath != null && level.imagePath != path) {
      try {
        await _client.storage.from(bucket).remove([level.imagePath!]);
      } catch (_) {}
    }
  }

  // --------------------------------------------------------------- pins ---

  Future<FloorPin> addPin({required String levelId, required PinKind kind, required String label, required double x, required double y, String? partnerVendorId}) async {
    final row = await _client
        .from('event_floor_pins')
        .insert({'level_id': levelId, 'kind': kind.db, 'label': label.trim(), 'x': x, 'y': y, 'partner_vendor_id': partnerVendorId})
        .select()
        .single();
    return FloorPin.fromMap(row);
  }

  Future<void> updatePin(FloorPin pin) => _client.from('event_floor_pins').update({
        'kind': pin.kind.db,
        'label': pin.label.trim(),
        'x': pin.x.clamp(0.0, 1.0),
        'y': pin.y.clamp(0.0, 1.0),
        'partner_vendor_id': pin.partnerVendorId,
      }).eq('id', pin.id);

  Future<void> deletePin(String pinId) => _client.from('event_floor_pins').delete().eq('id', pinId);

  // ------------------------------------------------------------ my spot ---

  Future<MyPosition?> myPosition(String eventId, String userId) async {
    final row = await _client.from('event_positions').select().eq('event_id', eventId).eq('user_id', userId).maybeSingle();
    return row == null ? null : MyPosition.fromMap(row);
  }

  Future<void> setMyPosition({required String eventId, required String userId, required String levelId, double? x, double? y, String? zonePinId}) =>
      _client.from('event_positions').upsert({
        'event_id': eventId,
        'user_id': userId,
        'level_id': levelId,
        'x': x,
        'y': y,
        'zone_pin_id': zonePinId,
      }, onConflict: 'event_id,user_id');

  Future<void> clearMyPosition(String eventId, String userId) => _client.from('event_positions').delete().eq('event_id', eventId).eq('user_id', userId);

  /// Zone QR scan: puts me on that pin server-side. Returns (eventId, levelId).
  Future<({String eventId, String levelId})> setPositionFromZone(String pinId) async {
    final rows = await _client.rpc('set_position_from_zone', params: {'p_pin': pinId});
    final r = ((rows as List).first as Map).cast<String, dynamic>();
    return (eventId: r['event_id'] as String, levelId: r['level_id'] as String);
  }

  // --------------------------------------------------------- organizers ---

  Future<bool> isHost(String eventId) async => (await _client.rpc('is_meet_host', params: {'p_event': eventId})) == true;

  /// Host only: members who set their spot, per level id. Never positions.
  Future<Map<String, int>> levelCounts(String eventId) async {
    final rows = await _client.rpc('event_level_counts', params: {'p_event': eventId});
    return {for (final r in (rows as List).cast<Map>()) r['level_id'] as String: (r['members'] as num).toInt()};
  }

  /// The event's 6-char invite code (RPC from the referral migration).
  Future<String> inviteCode(String eventId) async => (await _client.rpc('event_invite_code', params: {'p_event': eventId})) as String;

  Future<int> linkedCount(String eventId) async => ((await _client.rpc('event_linked_count', params: {'p_event': eventId})) as num?)?.toInt() ?? 0;

  /// Which event an invite code belongs to, or null.
  Future<String?> eventForInviteCode(String code) async => (await _client.rpc('event_for_invite_code', params: {'p_code': code.trim()})) as String?;
}

final floorplanRepositoryProvider = Provider<FloorplanRepository>((ref) => FloorplanRepository(ref.watch(supabaseProvider)));
