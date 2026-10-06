// The points week: Friday 18:00 Malaysia time to the next Friday 18:00. The
// weekly limits (one paid check-in per spot, one paid post) reset then. The
// database's points_week_start() is the rule; this mirrors it for the app
// (labels, and a fallback when the server's answer hasn't come back).

/// Malaysia is UTC+8 all year (no daylight saving).
const _myt = Duration(hours: 8);

/// When the points week holding [t] started (a UTC instant).
DateTime pointsWeekStart(DateTime t) {
  // Malaysia's wall clock, kept in a UTC DateTime so no local zone interferes.
  final wall = t.toUtc().add(_myt);
  // Shift back 18 h so the week starts at Friday 00:00, then step back to it.
  final shifted = wall.subtract(const Duration(hours: 18));
  final day = DateTime.utc(shifted.year, shifted.month, shifted.day);
  final back = (shifted.weekday + 2) % 7; // Dart: Monday 1 … Friday 5 … Sunday 7
  final startWall = day.subtract(Duration(days: back)).add(const Duration(hours: 18));
  return startWall.subtract(_myt);
}

/// When the weekly limits reset next after [t].
DateTime nextPointsReset(DateTime t) => pointsWeekStart(t).add(const Duration(days: 7));

/// [t] on Malaysia's wall clock (its weekday / hour fields), whatever zone
/// the phone is set to: the rule is a Malaysia rule, so it always reads
/// "Fri 6 PM".
DateTime malaysiaClock(DateTime t) => t.toUtc().add(_myt);

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Fri 6 PM" for [at]'s own weekday and hour fields (see [malaysiaClock]).
String resetLabel(DateTime at) {
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final m = at.minute == 0 ? '' : ':${at.minute.toString().padLeft(2, '0')}';
  return '${_weekdays[at.weekday - 1]} $h$m ${at.hour < 12 ? 'AM' : 'PM'}';
}

/// This points week, from points_week_status().
class PointsWeek {
  const PointsWeek({required this.weekStart, required this.nextReset, this.postDone = false});

  final DateTime weekStart;
  final DateTime nextReset;

  /// This week's post has paid already.
  final bool postDone;

  /// Worked out on the phone (signed out, or the server didn't answer).
  factory PointsWeek.at(DateTime now) => PointsWeek(weekStart: pointsWeekStart(now), nextReset: nextPointsReset(now));

  factory PointsWeek.fromMap(Map<String, dynamic> m) => PointsWeek(
        weekStart: DateTime.parse(m['week_start'] as String),
        nextReset: DateTime.parse(m['next_reset'] as String),
        postDone: m['post_done'] == true,
      );

  /// "Fri 6 PM" (Malaysia time).
  String get resetText => resetLabel(malaysiaClock(nextReset));
}

/// The snack after a spot check-in: what it paid, or when this spot pays
/// again (once per spot per points week, read in Malaysia time).
String spotCheckinMessage({required bool isNew, required int total, required int points, DateTime? againAt}) {
  final again = againAt == null ? '' : ' Points here again after ${resetLabel(malaysiaClock(againAt))}.';
  if (!isNew) return 'Already checked in here today.$again';
  if (points > 0) return 'Checked in · +$points points. That\'s $total for this spot.';
  return 'Checked in. That\'s $total for this spot.$again';
}
