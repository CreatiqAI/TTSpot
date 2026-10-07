import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../data/agenda_repository.dart';
import '../domain/agenda.dart';

/// An event's stage schedule, with my reminders.
final eventAgendaProvider = FutureProvider.autoDispose.family<List<AgendaItem>, String>((ref, eventId) {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(agendaRepositoryProvider).list(eventId);
});

/// Schedule writes. Each refreshes the list.
class AgendaActions {
  AgendaActions(this._ref);
  final Ref _ref;

  AgendaRepository get _repo => _ref.read(agendaRepositoryProvider);

  /// True when the reminder is now on.
  Future<bool> toggleReminder(String eventId, String itemId) async {
    final on = await _repo.toggleReminder(itemId);
    _ref.invalidate(eventAgendaProvider(eventId));
    return on;
  }

  Future<String> save({
    required String eventId,
    String? itemId,
    required String title,
    String? about,
    required DateTime startsAt,
    DateTime? endsAt,
    String? pinId,
    String? place,
  }) async {
    final id = await _repo.save(eventId: eventId, itemId: itemId, title: title, about: about, startsAt: startsAt, endsAt: endsAt, pinId: pinId, place: place);
    _ref.invalidate(eventAgendaProvider(eventId));
    return id;
  }

  Future<void> delete(String eventId, String itemId) async {
    await _repo.delete(itemId);
    _ref.invalidate(eventAgendaProvider(eventId));
  }
}

final agendaActionsProvider = Provider<AgendaActions>((ref) => AgendaActions(ref));
