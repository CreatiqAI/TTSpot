import '../../auth/domain/profile.dart';
import 'event.dart';

/// Everything the details screen needs in one object.
class EventDetail {
  const EventDetail({
    required this.event,
    required this.organizer,
    required this.attendeesPreview,
    required this.isAttending,
  });

  final Event event;
  final Profile? organizer;
  final List<Profile> attendeesPreview;
  final bool isAttending;
}

class EventComment {
  const EventComment({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.author,
  });

  final String id;
  final String eventId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final Profile? author;

  factory EventComment.fromMap(Map<String, dynamic> m) => EventComment(
        id: m['id'] as String,
        eventId: m['event_id'] as String,
        userId: m['user_id'] as String,
        body: m['body'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        author: m['profiles'] == null ? null : Profile.fromMap(m['profiles'] as Map<String, dynamic>),
      );
}

/// What `event_recap()` returns for a finished (or live) meet.
class EventRecap {
  const EventRecap({required this.went, required this.going, required this.moments, required this.cars});
  final int went;
  final int going;
  final int moments;
  final List<RecapCar> cars;

  factory EventRecap.fromMap(Map<String, dynamic> m) => EventRecap(
        went: (m['went'] as num?)?.toInt() ?? 0,
        going: (m['going'] as num?)?.toInt() ?? 0,
        moments: (m['moments'] as num?)?.toInt() ?? 0,
        cars: ((m['cars'] as List?) ?? const []).map((c) => RecapCar.fromMap((c as Map).cast<String, dynamic>())).toList(),
      );
}

class RecapCar {
  const RecapCar({required this.id, required this.make, required this.model, this.photoUrl, this.owner});
  final String id;
  final String make;
  final String model;
  final String? photoUrl;
  final String? owner;

  factory RecapCar.fromMap(Map<String, dynamic> m) => RecapCar(
        id: m['id'] as String,
        make: m['make'] as String,
        model: m['model'] as String,
        photoUrl: m['photo'] as String?,
        owner: m['owner'] as String?,
      );
}
