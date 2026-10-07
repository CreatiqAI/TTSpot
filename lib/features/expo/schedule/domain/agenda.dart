import '../../../../core/utils/dates.dart';
import '../../../floorplan/domain/floorplan.dart';

/// "10:30 – 11:00 AM", "11:30 AM – 12:15 PM", or just "10:30 AM".
String agendaTimeRange(DateTime start, DateTime? end) {
  final s = formatTime(start);
  if (end == null) return s;
  final e = formatTime(end);
  final sameHalf = (start.toLocal().hour < 12) == (end.toLocal().hour < 12) && isSameDay(start, end);
  return sameHalf ? '${s.substring(0, s.length - 3)} – $e' : '$s – $e';
}

/// One stage schedule item (`event_agenda_list`).
class AgendaItem {
  const AgendaItem({
    required this.id,
    required this.eventId,
    required this.title,
    this.about,
    required this.startsAt,
    this.endsAt,
    this.pinId,
    this.placeLabel,
    this.place,
    this.pinKind,
    this.pinLevelId,
    this.reminderOn = false,
    this.reminderCount,
  });

  final String id;
  final String eventId;
  final String title;
  final String? about;
  final DateTime startsAt;
  final DateTime? endsAt;

  /// The floor pin it happens at, if any.
  final String? pinId;

  /// What the host typed for the place (overrides the pin's name).
  final String? placeLabel;

  /// The place in words: the typed place, the pin's label, or its kind.
  final String? place;
  final PinKind? pinKind;

  /// The floor level of the pin; opens the floor plan there.
  final String? pinLevelId;

  /// I asked for a push 10 minutes before.
  final bool reminderOn;

  /// Hosts only: how many asked for a reminder.
  final int? reminderCount;

  /// Items without an end count as 30 minutes long for "Now".
  static const defaultLength = Duration(minutes: 30);

  DateTime get effectiveEnd => endsAt ?? startsAt.add(defaultLength);

  bool hasStarted(DateTime now) => !startsAt.isAfter(now);

  AgendaItem copyWith({bool? reminderOn}) => AgendaItem(
        id: id,
        eventId: eventId,
        title: title,
        about: about,
        startsAt: startsAt,
        endsAt: endsAt,
        pinId: pinId,
        placeLabel: placeLabel,
        place: place,
        pinKind: pinKind,
        pinLevelId: pinLevelId,
        reminderOn: reminderOn ?? this.reminderOn,
        reminderCount: reminderCount,
      );

  factory AgendaItem.fromMap(Map<String, dynamic> m) {
    final kind = m['pin_kind'] as String?;
    final about = (m['about'] as String?)?.trim();
    return AgendaItem(
      id: m['id'] as String,
      eventId: m['event_id'] as String,
      title: m['title'] as String? ?? '',
      about: about == null || about.isEmpty ? null : about,
      startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
      endsAt: m['ends_at'] == null ? null : DateTime.parse(m['ends_at'] as String).toLocal(),
      pinId: m['pin_id'] as String?,
      placeLabel: m['place_label'] as String?,
      place: m['place'] as String?,
      pinKind: kind == null ? null : PinKind.fromDb(kind),
      pinLevelId: m['pin_level_id'] as String?,
      reminderOn: m['reminder_on'] as bool? ?? false,
      reminderCount: (m['reminder_count'] as num?)?.toInt(),
    );
  }
}

/// Where an item sits against the clock.
enum AgendaPhase { past, now, next, later }

/// Now = started and not ended. Next = the earliest item(s) still to start.
Map<String, AgendaPhase> agendaPhases(List<AgendaItem> items, DateTime now) {
  DateTime? nextStart;
  for (final i in items) {
    if (i.startsAt.isAfter(now) && (nextStart == null || i.startsAt.isBefore(nextStart))) nextStart = i.startsAt;
  }
  return {
    for (final i in items)
      i.id: !i.startsAt.isAfter(now)
          ? (i.effectiveEnd.isAfter(now) ? AgendaPhase.now : AgendaPhase.past)
          : (nextStart != null && i.startsAt.isAtSameMomentAs(nextStart) ? AgendaPhase.next : AgendaPhase.later),
  };
}

/// Items grouped by local calendar day, days and items in time order.
List<({DateTime day, List<AgendaItem> items})> groupAgendaByDay(List<AgendaItem> items) {
  final sorted = [...items]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final out = <({DateTime day, List<AgendaItem> items})>[];
  for (final i in sorted) {
    final l = i.startsAt.toLocal();
    final day = DateTime(l.year, l.month, l.day);
    if (out.isEmpty || out.last.day != day) {
      out.add((day: day, items: [i]));
    } else {
      out.last.items.add(i);
    }
  }
  return out;
}
