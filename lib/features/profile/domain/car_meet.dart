/// A meet a car went to: the member RSVP'd or checked in with this car
/// (`event_attendees.car_id` / `checkins.car_id`). Only meets the viewer may
/// see come back (events RLS), and only ones that have started.
class CarMeet {
  const CarMeet({required this.eventId, required this.title, required this.startsAt, this.venue, this.coverUrl, required this.checkedIn});

  final String eventId;
  final String title;
  final DateTime startsAt;
  final String? venue;
  final String? coverUrl;

  /// Proven there (QR, GPS or the host's list), not just on the list.
  final bool checkedIn;

  /// Rows from `event_attendees` and `checkins` (each with an `events`
  /// embed), merged per meet. Cancelled, hidden and future meets are left
  /// out; newest first.
  static List<CarMeet> merge({required List<Map<String, dynamic>> attended, required List<Map<String, dynamic>> checkins, DateTime? now}) {
    final at = now ?? DateTime.now();
    final byId = <String, CarMeet>{};
    void add(Map<String, dynamic> row, {required bool checkedIn}) {
      final e = row['events'];
      if (e is! Map) return;
      final id = e['id'] as String?;
      final starts = DateTime.tryParse(e['starts_at'] as String? ?? '')?.toLocal();
      if (id == null || starts == null || starts.isAfter(at) || e['status'] == 'cancelled') return;
      final title = (e['title'] as String?)?.trim() ?? '';
      final venue = (e['venue_name'] as String?)?.trim() ?? '';
      byId[id] = CarMeet(
        eventId: id,
        title: title.isEmpty ? 'Meet' : title,
        startsAt: starts,
        venue: venue.isEmpty ? null : venue,
        coverUrl: e['cover_url'] as String?,
        checkedIn: checkedIn || (byId[id]?.checkedIn ?? false),
      );
    }

    for (final r in attended) {
      add(r, checkedIn: false);
    }
    for (final r in checkins) {
      add(r, checkedIn: true);
    }
    return byId.values.toList()..sort((a, b) => b.startsAt.compareTo(a.startsAt));
  }
}
