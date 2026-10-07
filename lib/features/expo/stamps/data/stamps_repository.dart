import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../domain/stamps_models.dart';

/// Booth stamps, freebies and leads (migration 0121).
class StampsRepository {
  StampsRepository(this._client);
  final SupabaseClient _client;

  Map<String, dynamic> _map(Object? v) => ((v as Map?) ?? const {}).cast<String, dynamic>();
  List<Map<String, dynamic>> _rows(Object? v) => ((v as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  // ---------------------------------------------------------- member ---

  Future<StampResult> collectStamp({required String exhibitorId, required String code, double? lat, double? lng}) async =>
      StampResult.fromMap(_map(await _client.rpc('collect_booth_stamp', params: {
        'p_exhibitor': exhibitorId,
        'p_code': code,
        'p_lat': lat,
        'p_lng': lng,
      })));

  Future<StampCard> myStamps(String eventId) async => StampCard.fromMap(_map(await _client.rpc('my_stamps', params: {'p_event': eventId})));

  Future<ExhibitorExtrasInfo?> extras(String exhibitorId) async {
    final v = await _client.rpc('exhibitor_extras', params: {'p_exhibitor': exhibitorId});
    return v == null ? null : ExhibitorExtrasInfo.fromMap(_map(v));
  }

  /// Returns when it was handed over.
  Future<DateTime> redeemFreebie(String exhibitorId) async {
    final m = _map(await _client.rpc('redeem_booth_freebie', params: {'p_exhibitor': exhibitorId}));
    return DateTime.tryParse('${m['redeemed_at']}')?.toLocal() ?? DateTime.now();
  }

  Future<DateTime> redeemRally(String eventId) async {
    final m = _map(await _client.rpc('redeem_rally_reward', params: {'p_event': eventId}));
    return DateTime.tryParse('${m['redeemed_at']}')?.toLocal() ?? DateTime.now();
  }

  Future<List<MyLead>> myLeads(String eventId) async =>
      _rows(await _client.rpc('my_event_leads', params: {'p_event': eventId})).map(MyLead.fromMap).toList();

  /// The member takes their contact back (RLS: own row).
  Future<void> removeMyLead(String leadId) => _client.from('event_leads').delete().eq('id', leadId);

  // ------------------------------------------------------------ host ---

  Future<List<BoothSetupRow>> setupList(String eventId) async =>
      _rows(await _client.rpc('booth_setup_list', params: {'p_event': eventId})).map(BoothSetupRow.fromMap).toList();

  Future<RallySettings> rallySettings(String eventId) async =>
      RallySettings.fromMap(await _client.from('event_expo_settings').select('stamp_goal, stamp_reward').eq('event_id', eventId).maybeSingle());

  Future<void> setBoothStamp(String exhibitorId, {required bool stop, String? freebie, int? limit}) =>
      _client.rpc('set_booth_stamp', params: {'p_exhibitor': exhibitorId, 'p_stop': stop, 'p_freebie': freebie, 'p_limit': limit});

  Future<void> setRally(String eventId, {int? goal, String? reward}) =>
      _client.rpc('set_stamp_rally', params: {'p_event': eventId, 'p_goal': goal, 'p_reward': reward});

  Future<BoothStaff> addStaff(String exhibitorId, String username) async =>
      BoothStaff.fromMap(_map(await _client.rpc('add_exhibitor_staff', params: {'p_exhibitor': exhibitorId, 'p_username': username})));

  Future<void> removeStaff(String exhibitorId, String userId) =>
      _client.rpc('remove_exhibitor_staff', params: {'p_exhibitor': exhibitorId, 'p_user': userId});

  Future<String> rotateCode(String exhibitorId) async => await _client.rpc('rotate_booth_code', params: {'p_exhibitor': exhibitorId}) as String;

  // ----------------------------------------------------------- staff ---

  Future<List<StaffBooth>> myStaffBooths(String eventId) async =>
      _rows(await _client.rpc('my_staff_booths', params: {'p_event': eventId})).map(StaffBooth.fromMap).toList();

  Future<LeadSaved> saveLead({required String eventId, required String passCode, String? exhibitorId}) async =>
      LeadSaved.fromMap(_map(await _client.rpc('save_lead_by_pass', params: {
        'p_event': eventId,
        'p_pass_code': passCode,
        'p_exhibitor': exhibitorId,
      })));

  Future<List<Lead>> leads(String exhibitorId) async =>
      _rows(await _client.rpc('exhibitor_leads', params: {'p_exhibitor': exhibitorId})).map(Lead.fromMap).toList();

  /// Staff note on a lead (RLS: booth staff may update).
  Future<void> setLeadNote(String leadId, String? note) =>
      _client.from('event_leads').update({'note': (note ?? '').trim().isEmpty ? null : note!.trim()}).eq('id', leadId);
}

final stampsRepositoryProvider = Provider<StampsRepository>((ref) => StampsRepository(ref.watch(supabaseProvider)));
