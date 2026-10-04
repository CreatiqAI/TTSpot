import '../../events/domain/event.dart';

/// The meets behind a profile's "Meets" number (ProfileStats.went) that I
/// may see, newest first, and which of them they checked in at. The number
/// counts private meets too; [hiddenOf] says how many the list leaves out.
class ProfileMeets {
  const ProfileMeets({required this.events, this.checkedIn = const {}});
  final List<Event> events;
  final Set<String> checkedIn;

  /// Of [total] meets, how many I can't see (private ones). Never negative,
  /// even when the number is a little older than the list.
  int hiddenOf(int? total) => total == null || total <= events.length ? 0 : total - events.length;

  bool wentTo(Event e) => checkedIn.contains(e.id);
}

/// The line under the sheet's title: what the number counts.
String meetsExplainer({required bool isMe}) =>
    "Meets and TT sessions ${isMe ? 'you' : 'they'} joined or hosted, counted once they start.";

/// "Plus 2 private meets." under the list, or null when none are hidden.
String? privateMeetsLine(int hidden) => hidden <= 0 ? null : 'Plus $hidden private meet${hidden == 1 ? '' : 's'}.';
