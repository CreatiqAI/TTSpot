// Who counts as "on the map now". One rule for the chats page and the map,
// kept free of Flutter so it can be unit tested.
//
// A position at most [kLiveWindow] old is live: "On the map now" and the
// green dot in Chats, "now" in green and a pulse on the map, and it counts in
// "N on the map". Older than that but younger than [kShowWindow] it is "last
// seen": still drawn on the map, muted, with its age ("5 min ago"), and never
// called live. From [kShowWindow] on it is gone (the server stops returning
// it at the same age: user_locations.expires_at is 24 h after each ping).
//
// While the app is open it re-sends my position every [kPresenceHeartbeat]
// even when I stand still (the GPS stream only fires on movement), so a
// friend parked with the app open stays live.

/// Up to this old, a position is live ("on the map now").
const kLiveWindow = Duration(minutes: 1);

/// Under this old, a position still shows on the map (as last seen).
const kShowWindow = Duration(hours: 24);

/// How often the open app re-sends my position to stay live. Well inside
/// [kLiveWindow], so one late ping does not make me look gone.
const kPresenceHeartbeat = Duration(seconds: 30);

enum Presence {
  /// Updated within [kLiveWindow]: on the map now.
  live,

  /// Older than [kLiveWindow], younger than [kShowWindow]: last seen.
  seen,

  /// [kShowWindow] or older: off the map.
  gone,
}

/// Where a position updated at [updatedAt] stands at [now]. A timestamp a
/// little in the future (the phone's clock behind the server's) is live.
Presence presenceAt(DateTime updatedAt, DateTime now) {
  final age = now.difference(updatedAt);
  if (age <= kLiveWindow) return Presence.live;
  if (age < kShowWindow) return Presence.seen;
  return Presence.gone;
}

/// On the map now (see [kLiveWindow]).
bool isLiveAt(DateTime updatedAt, [DateTime? now]) => presenceAt(updatedAt, now ?? DateTime.now()) == Presence.live;

/// Still drawn on the map, live or last seen (see [kShowWindow]).
bool isShownAt(DateTime updatedAt, [DateTime? now]) => presenceAt(updatedAt, now ?? DateTime.now()) != Presence.gone;

/// "now" while live, else how long ago: "1 min ago", "40 min ago", "3 h ago".
String presenceLabel(DateTime updatedAt, [DateTime? now]) {
  final t = now ?? DateTime.now();
  if (isLiveAt(updatedAt, t)) return 'now';
  final d = t.difference(updatedAt);
  if (d < const Duration(hours: 1)) return '${d.inMinutes} min ago';
  if (d < const Duration(days: 1)) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// How long until the first of [updatedAts] that is live at [now] stops
/// being live (a second past the edge), or null when none is live. Lets a
/// list of pins flip from "now" to "1 min ago" on time without a refetch.
Duration? untilLiveEnds(Iterable<DateTime> updatedAts, DateTime now) {
  Duration? next;
  for (final u in updatedAts) {
    if (presenceAt(u, now) != Presence.live) continue;
    final left = u.add(kLiveWindow).difference(now) + const Duration(seconds: 1);
    if (next == null || left < next) next = left;
  }
  return next;
}
