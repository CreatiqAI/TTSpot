import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../domain/agenda.dart';

/// The stage schedule (migration 0122).
class AgendaRepository {
  AgendaRepository(this._client);
  final SupabaseClient _client;

  Future<List<AgendaItem>> list(String eventId) async {
    final rows = (await _client.rpc('event_agenda_list', params: {'p_event': eventId}) as List?) ?? const [];
    return rows.map((e) => AgendaItem.fromMap((e as Map).cast<String, dynamic>())).toList();
  }

  /// True when the reminder is now on.
  Future<bool> toggleReminder(String itemId) async => (await _client.rpc('toggle_agenda_reminder', params: {'p_item': itemId})) == true;

  Future<String> save({
    required String eventId,
    String? itemId,
    required String title,
    String? about,
    required DateTime startsAt,
    DateTime? endsAt,
    String? pinId,
    String? place,
  }) async =>
      await _client.rpc('save_agenda_item', params: {
        'p_event': eventId,
        'p_item': itemId,
        'p_title': title,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt?.toUtc().toIso8601String(),
        'p_about': about,
        'p_pin': pinId,
        'p_place': place,
      }) as String;

  Future<void> delete(String itemId) => _client.rpc('delete_agenda_item', params: {'p_item': itemId});
}

final agendaRepositoryProvider = Provider<AgendaRepository>((ref) => AgendaRepository(ref.watch(supabaseProvider)));
