// Date formatting without the `intl` package. Malaysian-English style.

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "8:00 PM"
String formatTime(DateTime t) {
  final l = t.toLocal();
  var h = l.hour % 12;
  if (h == 0) h = 12;
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// "Sat, 14 Sep"
String formatDate(DateTime t) {
  final l = t.toLocal();
  return '${_weekdays[l.weekday - 1]}, ${l.day} ${_months[l.month - 1]}';
}

/// "Sat, 14 Sep · 8:00 PM"
String formatEventDate(DateTime t) => '${formatDate(t)} · ${formatTime(t)}';

/// "Today · 8:00 PM", "Tomorrow · 9:30 AM", else [formatEventDate].
String formatEventDateFriendly(DateTime t, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final l = t.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(l.year, l.month, l.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today · ${formatTime(l)}';
  if (diff == 1) return 'Tomorrow · ${formatTime(l)}';
  return formatEventDate(l);
}

/// Compact time-until, for map marker labels: "now", "45m", "5h", "2d", "3w", "2mo", "past".
String relativeShort(DateTime t, {DateTime? now}) {
  final d = t.difference(now ?? DateTime.now());
  if (d.isNegative) return 'past';
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 30) return '${d.inDays ~/ 7}w';
  return '${d.inDays ~/ 30}mo';
}

/// "Just now", "5m", "3h", "2d", "3w", else "14 Sep".
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 30) return '${d.inDays ~/ 7}w';
  final l = t.toLocal();
  return '${l.day} ${_months[l.month - 1]}';
}
