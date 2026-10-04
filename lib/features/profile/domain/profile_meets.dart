import '../../events/domain/event.dart';

/// The meets behind a profile's "Meets" number (ProfileStats.went) that I
/// may see, newest first, and which of them they checked in at. The number
/// counts private meets too; [hiddenOf] says how many the list leaves out.
/// [complete] is false when the list stopped at its limit (older ones left
/// out as well).
class ProfileMeets {
  const ProfileMeets({required this.events, this.checkedIn = const {}, this.complete = true});
  final List<Event> events;
  final Set<String> checkedIn;
  final bool complete;

  /// Of [total] meets, how many the list leaves out. Never negative, even
  /// when the number is a little older than the list.
  int hiddenOf(int? total) => total == null || total <= events.length ? 0 : total - events.length;

  bool wentTo(Event e) => checkedIn.contains(e.id);

  /// The line under the list, or null when nothing is left out: private
  /// meets, or simply more when the list was cut short.
  String? hiddenLine(int? total) {
    final n = hiddenOf(total);
    if (n <= 0) return null;
    return complete ? privateMeetsLine(n) : 'Plus $n more.';
  }
}

/// The line under the sheet's title: what the number counts.
String meetsExplainer({required bool isMe}) =>
    "Meets and TT sessions ${isMe ? 'you' : 'they'} joined or hosted, counted once they start.";

/// "Plus 2 private meets." under the list, or null when none are hidden.
String? privateMeetsLine(int hidden) => hidden <= 0 ? null : 'Plus $hidden private meet${hidden == 1 ? '' : 's'}.';
