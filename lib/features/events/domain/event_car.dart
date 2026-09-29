/// The car a member is bringing to (or brought to) a meet: the one they picked
/// when they joined / checked in, else their default car (RPC `event_cars`).
class EventCar {
  const EventCar({required this.userId, required this.carId, this.title, this.cover, this.bodyStyle});

  final String userId;
  final String carId;
  /// "Make Model".
  final String? title;
  /// AI portrait, else the first photo.
  final String? cover;
  /// Body style for the placeholder render (when the RPC returns it).
  final String? bodyStyle;

  factory EventCar.fromMap(Map<String, dynamic> m) => EventCar(
        userId: m['user_id'] as String,
        carId: m['car_id'] as String,
        title: m['car_title'] as String?,
        cover: m['car_cover'] as String?,
        bodyStyle: m['car_body_style'] as String?,
      );
}
