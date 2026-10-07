import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../expo/door/domain/door_models.dart';
import '../../organizer/domain/organizer_models.dart';

/// Whose eyes a big event's page looks through.
enum EventView {
  attendee('Attendee'),
  organizer('Organizer'),
  booth('Booth');

  const EventView(this.label);
  final String label;
}

/// A tab of a big event's attendee view.
enum EventModule {
  overview('Overview'),
  floorPlan('Floor plan'),
  exhibitors('Exhibitors'),
  schedule('Schedule'),
  activities('Activities');

  const EventModule(this.label);
  final String label;
}

/// The attendee tabs: Overview, then only the modules that have data.
/// Activities = booth stamps and the show car vote (plus the lucky draw).
List<EventModule> eventModulesFor(EventHub h) => [
      EventModule.overview,
      if (h.levels > 0) EventModule.floorPlan,
      if (h.exhibitors > 0) EventModule.exhibitors,
      if (h.agenda > 0) EventModule.schedule,
      if (h.stampStops > 0 || h.contestId != null) EventModule.activities,
    ];

/// The views I can switch between at an event, attendee first. Only
/// [EventView.attendee] for most people (then there is no switch).
///
/// - Organizer: the host, co-hosts, club officers, admins and crew
///   (`my_event_role`), once the event's organizer tools are on (or I'm its
///   host, who gets the "get verified" pitch there).
/// - Booth: staff of at least one exhibitor (`event_hub.my_booths`).
List<EventView> eventViewsFor({required EventRole role, EventHub? hub}) => [
      EventView.attendee,
      if (role.onTeam && (role.tools || role.isHost)) EventView.organizer,
      if (hub != null && hub.myBooths.isNotEmpty) EventView.booth,
    ];

/// The view picked per event, kept for the app session (in memory).
class EventViewChoice extends Notifier<Map<String, EventView>> {
  @override
  Map<String, EventView> build() => const {};

  void set(String eventId, EventView view) => state = {...state, eventId: view};
}

final eventViewChoiceProvider = NotifierProvider<EventViewChoice, Map<String, EventView>>(EventViewChoice.new);

/// The view to show: the one picked, when I still have it, else attendee.
EventView currentEventView(Map<String, EventView> picked, String eventId, List<EventView> available) {
  final p = picked[eventId];
  return p != null && available.contains(p) ? p : EventView.attendee;
}
