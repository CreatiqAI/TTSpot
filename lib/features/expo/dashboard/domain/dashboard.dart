/// The organizer's live expo dashboard (migration 0123 `expo_dashboard`).
library;

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
int? _iN(Object? v) => (v as num?)?.toInt();
List<Map<String, dynamic>> _rows(Object? v) => ((v as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

class DashTotals {
  const DashTotals({
    this.checkedIn = 0,
    this.going = 0,
    this.registrations = 0,
    this.contactOk = 0,
    this.stamps = 0,
    this.stampers = 0,
    this.freebies = 0,
    this.rallyCompleted = 0,
    this.rallyRedeemed = 0,
    this.leads = 0,
    this.votes = 0,
    this.exhibitors = 0,
  });

  final int checkedIn;
  final int going;
  final int registrations;
  final int contactOk;
  final int stamps;
  /// Members with at least one stamp.
  final int stampers;
  final int freebies;
  final int rallyCompleted;
  final int rallyRedeemed;
  final int leads;
  final int votes;
  final int exhibitors;

  factory DashTotals.fromMap(Map<String, dynamic>? m) => m == null
      ? const DashTotals()
      : DashTotals(
          checkedIn: _i(m['checked_in']),
          going: _i(m['going']),
          registrations: _i(m['registrations']),
          contactOk: _i(m['contact_ok']),
          stamps: _i(m['stamps']),
          stampers: _i(m['stampers']),
          freebies: _i(m['freebies']),
          rallyCompleted: _i(m['rally_completed']),
          rallyRedeemed: _i(m['rally_redeemed']),
          leads: _i(m['leads']),
          votes: _i(m['votes']),
          exhibitors: _i(m['exhibitors']),
        );
}

/// Check-ins in one Malaysia-time hour. [hour] is wall-clock MYT (no zone).
class HourCount {
  const HourCount(this.hour, this.count);
  final DateTime hour;
  final int count;

  @override
  bool operator ==(Object other) => other is HourCount && other.hour == hour && other.count == count;
  @override
  int get hashCode => Object.hash(hour, count);
  @override
  String toString() => 'HourCount($hour, $count)';
}

class LabelCount {
  const LabelCount(this.label, this.count);
  final String label;
  final int count;
}

class BoothStat {
  const BoothStat({required this.id, required this.name, this.booths = const [], this.stamps = 0, this.freebies = 0, this.leads = 0});
  final String id;
  final String name;
  final List<String> booths;
  final int stamps;
  final int freebies;
  final int leads;

  factory BoothStat.fromMap(Map<String, dynamic> m) => BoothStat(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? 'Exhibitor',
        booths: ((m['booths'] as List?) ?? const []).map((e) => '$e').toList(),
        stamps: _i(m['stamps']),
        freebies: _i(m['freebies']),
        leads: _i(m['leads']),
      );
}

class DrawStat {
  const DrawStat({required this.id, required this.title, required this.status, this.drawAt, this.presenceMinutes, this.entrants, this.confirmed = 0});
  final String id;
  final String title;
  /// 'scheduled' | 'drawn'.
  final String status;
  final DateTime? drawAt;
  /// Roll call on: minutes before the draw.
  final int? presenceMinutes;
  /// Drawn: the frozen entrant count. Scheduled without roll call: everyone
  /// checked in so far. Null with roll call (see [confirmed]).
  final int? entrants;
  /// Roll call confirmations.
  final int confirmed;

  bool get drawn => status == 'drawn';
  bool get rollCall => presenceMinutes != null;

  factory DrawStat.fromMap(Map<String, dynamic> m) => DrawStat(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? 'Lucky draw',
        status: m['status'] as String? ?? 'scheduled',
        drawAt: m['draw_at'] == null ? null : DateTime.tryParse(m['draw_at'] as String)?.toLocal(),
        presenceMinutes: _iN(m['presence_minutes']),
        entrants: _iN(m['entrants']),
        confirmed: _i(m['confirmed']),
      );
}

class ContestStat {
  const ContestStat({required this.id, required this.title, this.ended = false, this.entries = 0, this.pending = 0, this.votes = 0});
  final String id;
  final String title;
  final bool ended;
  final int entries;
  final int pending;
  final int votes;

  factory ContestStat.fromMap(Map<String, dynamic> m) => ContestStat(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? 'Show car vote',
        ended: m['ended'] as bool? ?? false,
        entries: _i(m['entries']),
        pending: _i(m['pending']),
        votes: _i(m['votes']),
      );
}

class ExpoDashboard {
  const ExpoDashboard({
    this.totals = const DashTotals(),
    this.arrivals = const [],
    this.makes = const [],
    this.states = const [],
    this.booths = const [],
    this.draws = const [],
    this.contests = const [],
    this.generatedAt,
  });

  final DashTotals totals;
  final List<HourCount> arrivals;
  final List<LabelCount> makes;
  final List<LabelCount> states;
  final List<BoothStat> booths;
  final List<DrawStat> draws;
  final List<ContestStat> contests;
  final DateTime? generatedAt;

  factory ExpoDashboard.fromMap(Map<String, dynamic> m) => ExpoDashboard(
        totals: DashTotals.fromMap((m['totals'] as Map?)?.cast<String, dynamic>()),
        arrivals: fillHours([
          for (final r in _rows(m['arrivals']))
            if (_parseWallClock(r['hour'] as String?) case final h?) HourCount(h, _i(r['count'])),
        ]),
        makes: [for (final r in _rows(m['makes'])) LabelCount(r['label'] as String? ?? '', _i(r['count']))],
        states: [for (final r in _rows(m['states'])) LabelCount(r['label'] as String? ?? '', _i(r['count']))],
        booths: _rows(m['booths']).map(BoothStat.fromMap).toList(),
        draws: _rows(m['draws']).map(DrawStat.fromMap).toList(),
        contests: _rows(m['contests']).map(ContestStat.fromMap).toList(),
        generatedAt: m['generated_at'] == null ? null : DateTime.tryParse(m['generated_at'] as String)?.toLocal(),
      );
}

/// "2026-10-08T14:00:00" as a wall-clock time (no zone conversion).
DateTime? _parseWallClock(String? s) {
  if (s == null) return null;
  final t = DateTime.tryParse(s);
  if (t == null) return null;
  return DateTime(t.year, t.month, t.day, t.hour);
}

/// Hours with no check-ins become zero bars, so the chart reads as a
/// timeline. Spans longer than [maxHours] stay as they are.
List<HourCount> fillHours(List<HourCount> list, {int maxHours = 48}) {
  if (list.length < 2) return list;
  final sorted = [...list]..sort((a, b) => a.hour.compareTo(b.hour));
  final first = sorted.first.hour;
  final last = sorted.last.hour;
  final span = last.difference(first).inHours;
  if (span + 1 > maxHours) return sorted;
  final byHour = {for (final h in sorted) h.hour: h.count};
  return [
    for (var i = 0; i <= span; i++)
      // DateTime(…, hour + i) rolls over days correctly with no DST in MYT.
      HourCount(DateTime(first.year, first.month, first.day, first.hour + i), byHour[DateTime(first.year, first.month, first.day, first.hour + i)] ?? 0),
  ];
}

/// "10 AM", "12 PM".
String hourLabel(DateTime h) {
  final x = h.hour % 12 == 0 ? 12 : h.hour % 12;
  return '$x ${h.hour < 12 ? 'AM' : 'PM'}';
}
