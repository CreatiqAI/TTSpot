import 'event.dart';

/// What the event page calls an event: its app bar title and the kind badge
/// by the title.
///
/// - A big event (any Expo module: floor plan, exhibitors, schedule, stamps
///   or a vote): "Event", badge "Expo".
/// - Hosted by an official club (or typed official): "Official event".
/// - Otherwise by type: TT session, Meet, Convoy, Track day, Charity drive.
enum EventKind {
  expo('Event', 'Expo'),
  official('Official event', 'Official event'),
  tt('TT session', 'TT session'),
  meet('Meet', 'Meet'),
  convoy('Convoy', 'Convoy'),
  trackday('Track day', 'Track day'),
  charity('Charity drive', 'Charity drive');

  const EventKind(this.title, this.badge);

  /// The app bar title.
  final String title;

  /// The pill by the event's name.
  final String badge;
}

EventKind eventKindOf(Event e, {bool big = false}) {
  if (big) return EventKind.expo;
  if (e.isOfficialClubEvent || e.type == EventType.official) return EventKind.official;
  if (e.isInstant) return EventKind.tt;
  return switch (e.type) {
    EventType.tt => EventKind.tt,
    EventType.convoy => EventKind.convoy,
    EventType.trackday => EventKind.trackday,
    EventType.charity => EventKind.charity,
    EventType.official => EventKind.official,
    EventType.meet => EventKind.meet,
  };
}

/// The event page's app bar title.
String eventPageTitle(Event e, {bool big = false}) => eventKindOf(e, big: big).title;
