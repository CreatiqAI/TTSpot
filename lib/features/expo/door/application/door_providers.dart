import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../events/application/event_providers.dart';
import '../data/door_repository.dart';
import '../domain/door_models.dart';

/// My hub for an event (pass, entry number, what the event has). Refetches
/// whenever the event page refreshes (it watches the event detail).
final eventHubProvider = FutureProvider.autoDispose.family<EventHub?, String>((ref, eventId) async {
  if (ref.watch(currentUserIdProvider) == null) return null;
  try {
    await ref.watch(eventDetailProvider(eventId).future);
  } catch (_) {
    // the hub still loads on its own
  }
  return ref.watch(doorRepositoryProvider).hub(eventId);
});

/// The event's registration form, or null when it has none.
final registrationFormProvider = FutureProvider.autoDispose.family<RegistrationForm?, String>((ref, eventId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(doorRepositoryProvider).form(eventId);
});

/// My answers at an event, or null.
final myRegistrationProvider = FutureProvider.autoDispose.family<MyRegistration?, String>((ref, eventId) {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return Future.value(null);
  return ref.watch(doorRepositoryProvider).myRegistration(eventId, me);
});

/// Host: the check-in radius in force (the event's own, else the default).
final checkinRadiusProvider = FutureProvider.autoDispose.family<int, String>((ref, eventId) {
  return ref.watch(doorRepositoryProvider).checkinRadius(eventId);
});

/// Events just checked in at the door whose form should open by itself,
/// once (the welcome banner or the pass picks it up).
class PendingRegistration extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String eventId) => state = {...state, eventId};

  /// True once for [eventId]: the caller opens the form.
  bool take(String eventId) {
    if (!state.contains(eventId)) return false;
    state = {...state}..remove(eventId);
    return true;
  }
}

final pendingRegistrationProvider = NotifierProvider<PendingRegistration, Set<String>>(PendingRegistration.new);

class DoorActions {
  DoorActions(this._ref);
  final Ref _ref;

  DoorRepository get _repo => _ref.read(doorRepositoryProvider);

  Future<void> setShareContact(String eventId, bool on) async {
    await _repo.setShareContact(eventId, on);
    _ref.invalidate(eventHubProvider(eventId));
  }

  Future<void> saveRegistration(String eventId, {required Map<String, dynamic> answers, required bool contactOk}) async {
    await _repo.saveRegistration(eventId: eventId, answers: answers, contactOk: contactOk);
    _ref.invalidate(myRegistrationProvider(eventId));
    _ref.invalidate(eventHubProvider(eventId));
  }

  Future<void> saveForm(String eventId, {required List<FormQuestion> questions, String? consentText, required bool askContact, required bool required}) async {
    await _repo.saveForm(eventId: eventId, questions: questions, consentText: consentText, askContact: askContact, required: required);
    _ref.invalidate(registrationFormProvider(eventId));
    _ref.invalidate(eventHubProvider(eventId));
  }

  Future<int> setCheckinRadius(String eventId, int? metres) async {
    final m = await _repo.setCheckinRadius(eventId, metres);
    _ref.invalidate(checkinRadiusProvider(eventId));
    return m;
  }
}

final doorActionsProvider = Provider<DoorActions>((ref) => DoorActions(ref));
