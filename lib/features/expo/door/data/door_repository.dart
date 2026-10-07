import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../domain/door_models.dart';

/// Door check-in, pass, hub and registration form (migration 0119).
class DoorRepository {
  DoorRepository(this._client);
  final SupabaseClient _client;

  Future<DoorResult> checkinByDoor({required String code, double? lat, double? lng, String? carId}) async {
    final v = await _client.rpc('checkin_by_door', params: {'p_code': code.trim(), 'p_lat': lat, 'p_lng': lng, 'p_car': carId});
    return DoorResult.fromMap((v as Map).cast<String, dynamic>());
  }

  Future<EventHub?> hub(String eventId) async {
    final v = await _client.rpc('event_hub', params: {'p_event': eventId});
    return v == null ? null : EventHub.fromMap((v as Map).cast<String, dynamic>());
  }

  Future<void> setShareContact(String eventId, bool on) => _client.rpc('set_pass_share_contact', params: {'p_event': eventId, 'p_on': on});

  // --------------------------------------------------- check-in area ---

  Future<int> checkinRadius(String eventId) async => ((await _client.rpc('event_checkin_radius', params: {'p_event': eventId})) as num).toInt();

  /// Null = back to the default. Returns the radius now in force.
  Future<int> setCheckinRadius(String eventId, int? metres) async =>
      ((await _client.rpc('set_event_checkin_radius', params: {'p_event': eventId, 'p_m': metres})) as num).toInt();

  /// My entry number at [eventId], or null when I'm not checked in.
  Future<int?> myEntryNo(String eventId, String userId) async {
    final row = await _client.from('checkins').select('entry_no').eq('event_id', eventId).eq('user_id', userId).maybeSingle();
    return (row?['entry_no'] as num?)?.toInt();
  }

  // ---------------------------------------------------- registration ---

  Future<RegistrationForm?> form(String eventId) async {
    final row = await _client.from('event_forms').select('event_id, questions, consent_text, ask_contact, required').eq('event_id', eventId).maybeSingle();
    return row == null ? null : RegistrationForm.fromMap(row);
  }

  /// Host: save the form (RLS: event_forms host write).
  Future<void> saveForm({required String eventId, required List<FormQuestion> questions, String? consentText, required bool askContact, required bool required}) =>
      _client.from('event_forms').upsert({
        'event_id': eventId,
        'questions': [for (final q in questions) q.toMap()],
        'consent_text': consentText == null || consentText.trim().isEmpty ? null : consentText.trim(),
        'ask_contact': askContact,
        'required': required,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<MyRegistration?> myRegistration(String eventId, String userId) async {
    final row = await _client.from('event_registrations').select('answers, contact_ok').eq('event_id', eventId).eq('user_id', userId).maybeSingle();
    if (row == null) return null;
    return MyRegistration(answers: (row['answers'] as Map?)?.cast<String, dynamic>() ?? const {}, contactOk: row['contact_ok'] as bool? ?? false);
  }

  Future<void> saveRegistration({required String eventId, required Map<String, dynamic> answers, required bool contactOk}) =>
      _client.rpc('save_event_registration', params: {'p_event': eventId, 'p_answers': answers, 'p_contact_ok': contactOk});

  Future<List<RegistrationExportRow>> exportRegistrations(String eventId) async {
    final v = await _client.rpc('event_registrations_export', params: {'p_event': eventId});
    return [for (final r in (v as List?) ?? const []) RegistrationExportRow.fromMap((r as Map).cast<String, dynamic>())];
  }
}

final doorRepositoryProvider = Provider<DoorRepository>((ref) => DoorRepository(ref.watch(supabaseProvider)));
