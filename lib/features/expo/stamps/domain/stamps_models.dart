// Booth stamps, freebies and leads (Expo mode track C, migration 0121).

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int? _int(Object? v) => (v as num?)?.toInt();
List<String> _strings(Object? v) => ((v as List?) ?? const []).map((e) => e.toString()).toList();

/// The payload printed on a booth's stamp QR.
String boothQrPayload(String exhibitorId, String code) => 'ttspot://booth/$exhibitorId/$code';

/// "A019 · A024", or '' when the exhibitor has no booth codes.
String boothLabel(List<String> booths) => booths.join(' · ');

enum FreebieState {
  /// The booth gives nothing away.
  none,

  /// Stamp the booth first.
  locked,

  /// Stamped, stock left: show the hand-over card.
  available,
  redeemed,

  /// Stock ran out before I collected mine.
  out;

  static FreebieState parse(Object? v) => switch (v) {
        'locked' => FreebieState.locked,
        'available' => FreebieState.available,
        'redeemed' => FreebieState.redeemed,
        'out' => FreebieState.out,
        _ => FreebieState.none,
      };
}

/// Stamp rally reward: none (goal not reached), done (collect it), redeemed.
enum RallyState {
  none,
  done,
  redeemed;

  static RallyState parse(Object? v) => switch (v) {
        'done' => RallyState.done,
        'redeemed' => RallyState.redeemed,
        _ => RallyState.none,
      };
}

/// One stamp stop on my stamp card.
class StampStop {
  const StampStop({
    required this.id,
    required this.name,
    this.booths = const [],
    this.logoUrl,
    this.stampedAt,
    this.freebie,
    this.freebieState = FreebieState.none,
    this.freebieRedeemedAt,
    this.freebieLeft,
    this.levelId,
    this.pinId,
  });

  final String id;
  final String name;
  final List<String> booths;
  final String? logoUrl;
  final DateTime? stampedAt;
  final String? freebie;
  final FreebieState freebieState;
  final DateTime? freebieRedeemedAt;

  /// Null = unlimited.
  final int? freebieLeft;
  final String? levelId;
  final String? pinId;

  bool get stamped => stampedAt != null;
  bool get hasFreebie => freebie != null && freebie!.isNotEmpty;

  factory StampStop.fromMap(Map<String, dynamic> m) => StampStop(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        booths: _strings(m['booths']),
        logoUrl: m['logo_url'] as String?,
        stampedAt: _date(m['stamped_at']),
        freebie: m['freebie'] as String?,
        freebieState: FreebieState.parse(m['freebie_state']),
        freebieRedeemedAt: _date(m['freebie_redeemed_at']),
        freebieLeft: _int(m['freebie_left']),
        levelId: m['level_id'] as String?,
        pinId: m['pin_id'] as String?,
      );
}

/// My stamp card for one event (`my_stamps`).
class StampCard {
  const StampCard({
    this.stops = const [],
    this.goal,
    this.reward,
    this.checkedIn = false,
    this.rally = RallyState.none,
    this.rallyCompletedAt,
    this.rallyRedeemedAt,
  });

  final List<StampStop> stops;

  /// Stamps needed for the rally reward. Null = no rally.
  final int? goal;
  final String? reward;
  final bool checkedIn;
  final RallyState rally;
  final DateTime? rallyCompletedAt;
  final DateTime? rallyRedeemedAt;

  int get stamped => stops.where((s) => s.stamped).length;

  /// What the progress counts up to: the goal, else every stop.
  int get target => goal ?? stops.length;
  double get progress => target <= 0 ? 0 : (stamped / target).clamp(0, 1).toDouble();
  bool get hasRally => goal != null;
  List<StampStop> get freebies => stops.where((s) => s.hasFreebie).toList();

  StampStop? stop(String id) {
    for (final s in stops) {
      if (s.id == id) return s;
    }
    return null;
  }

  factory StampCard.fromMap(Map<String, dynamic> m) => StampCard(
        stops: ((m['stops'] as List?) ?? const []).map((e) => StampStop.fromMap((e as Map).cast<String, dynamic>())).toList(),
        goal: _int(m['goal']),
        reward: m['reward'] as String?,
        checkedIn: m['checked_in'] as bool? ?? false,
        rally: RallyState.parse(m['rally']),
        rallyCompletedAt: _date(m['rally_completed_at']),
        rallyRedeemedAt: _date(m['rally_redeemed_at']),
      );
}

/// What `collect_booth_stamp` answered.
class StampResult {
  const StampResult({
    required this.eventId,
    required this.exhibitorId,
    required this.exhibitorName,
    this.isNew = false,
    this.points = 0,
    this.stamps = 0,
    this.goal,
    this.rallyDone = false,
    this.reward,
    this.freebie,
    this.freebieLeft,
    this.freebieRedeemed = false,
    this.levelId,
  });

  final String eventId;
  final String exhibitorId;
  final String exhibitorName;
  final bool isNew;
  final int points;
  final int stamps;
  final int? goal;
  final bool rallyDone;
  final String? reward;
  final String? freebie;
  final int? freebieLeft;
  final bool freebieRedeemed;
  final String? levelId;

  /// A freebie I can collect right now.
  bool get freebieWaiting => freebie != null && freebie!.isNotEmpty && !freebieRedeemed && (freebieLeft == null || freebieLeft! > 0);

  String get title {
    if (!isNew) return 'Already stamped';
    if (goal != null) return 'Stamp $stamps of $goal';
    return 'Booth stamped';
  }

  String get subtitle {
    final parts = <String>[exhibitorName];
    if (freebieWaiting) parts.add('Free $freebie waiting for you');
    if (isNew && rallyDone && goal != null && stamps == goal) {
      parts.add(reward == null || reward!.isEmpty ? 'Stamp rally done!' : 'Stamp rally done! Collect your $reward');
    }
    return parts.join(' · ');
  }

  factory StampResult.fromMap(Map<String, dynamic> m) => StampResult(
        eventId: m['event_id'] as String,
        exhibitorId: m['exhibitor_id'] as String,
        exhibitorName: (m['exhibitor_name'] as String?) ?? '',
        isNew: m['new'] as bool? ?? false,
        points: _int(m['points']) ?? 0,
        stamps: _int(m['stamps']) ?? 0,
        goal: _int(m['goal']),
        rallyDone: m['rally_done'] as bool? ?? false,
        reward: m['reward'] as String?,
        freebie: m['freebie'] as String?,
        freebieLeft: _int(m['freebie_left']),
        freebieRedeemed: m['freebie_redeemed'] as bool? ?? false,
        levelId: m['level_id'] as String?,
      );
}

/// One exhibitor as I see it, for the exhibitor sheet (`exhibitor_extras`).
class ExhibitorExtrasInfo {
  const ExhibitorExtrasInfo({
    this.stampStop = false,
    this.stampedAt,
    this.freebie,
    this.freebieState = FreebieState.none,
    this.amStaff = false,
    this.leadCount,
  });

  final bool stampStop;
  final DateTime? stampedAt;
  final String? freebie;
  final FreebieState freebieState;
  final bool amStaff;
  final int? leadCount;

  bool get isEmpty => !stampStop && !amStaff && freebieState == FreebieState.none;

  factory ExhibitorExtrasInfo.fromMap(Map<String, dynamic> m) => ExhibitorExtrasInfo(
        stampStop: m['stamp_stop'] as bool? ?? false,
        stampedAt: _date(m['stamped_at']),
        freebie: m['freebie'] as String?,
        freebieState: FreebieState.parse(m['freebie_state']),
        amStaff: m['am_staff'] as bool? ?? false,
        leadCount: _int(m['lead_count']),
      );
}

class BoothStaff {
  const BoothStaff({required this.userId, this.username, required this.name});
  final String userId;
  final String? username;
  final String name;

  factory BoothStaff.fromMap(Map<String, dynamic> m) => BoothStaff(
        userId: m['user_id'] as String,
        username: m['username'] as String?,
        name: (m['name'] as String?) ?? (m['username'] as String?) ?? 'Member',
      );
}

/// Host view of one exhibitor (`booth_setup_list`).
class BoothSetupRow {
  const BoothSetupRow({
    required this.id,
    required this.name,
    this.booths = const [],
    this.stampStop = false,
    this.freebie,
    this.freebieLimit,
    this.stampCode,
    this.stamps = 0,
    this.freebiesRedeemed = 0,
    this.leads = 0,
    this.staff = const [],
  });

  final String id;
  final String name;
  final List<String> booths;
  final bool stampStop;
  final String? freebie;
  final int? freebieLimit;
  final String? stampCode;
  final int stamps;
  final int freebiesRedeemed;
  final int leads;
  final List<BoothStaff> staff;

  String? get qrPayload => stampCode == null ? null : boothQrPayload(id, stampCode!);

  factory BoothSetupRow.fromMap(Map<String, dynamic> m) => BoothSetupRow(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        booths: _strings(m['booths']),
        stampStop: m['stamp_stop'] as bool? ?? false,
        freebie: m['freebie'] as String?,
        freebieLimit: _int(m['freebie_limit']),
        stampCode: m['stamp_code'] as String?,
        stamps: _int(m['stamps']) ?? 0,
        freebiesRedeemed: _int(m['freebies_redeemed']) ?? 0,
        leads: _int(m['leads']) ?? 0,
        staff: ((m['staff'] as List?) ?? const []).map((e) => BoothStaff.fromMap((e as Map).cast<String, dynamic>())).toList(),
      );
}

/// The stamp rally settings (`event_expo_settings`).
class RallySettings {
  const RallySettings({this.goal, this.reward});
  final int? goal;
  final String? reward;

  factory RallySettings.fromMap(Map<String, dynamic>? m) =>
      m == null ? const RallySettings() : RallySettings(goal: _int(m['stamp_goal']), reward: m['stamp_reward'] as String?);
}

/// A booth I staff at an event.
class StaffBooth {
  const StaffBooth({required this.id, required this.name, this.booths = const []});
  final String id;
  final String name;
  final List<String> booths;

  factory StaffBooth.fromMap(Map<String, dynamic> m) =>
      StaffBooth(id: m['id'] as String, name: (m['name'] as String?) ?? '', booths: _strings(m['booths']));
}

/// What `save_lead_by_pass` answered.
class LeadSaved {
  const LeadSaved({required this.exhibitorId, required this.exhibitorName, this.isNew = false, required this.name, this.username, this.car});
  final String exhibitorId;
  final String exhibitorName;
  final bool isNew;
  final String name;
  final String? username;
  final String? car;

  String get title => isNew ? 'Lead saved · $name' : 'Already saved · $name';

  String get subtitle => [if (car != null && car!.isNotEmpty) car!, exhibitorName].join(' · ');

  factory LeadSaved.fromMap(Map<String, dynamic> m) => LeadSaved(
        exhibitorId: m['exhibitor_id'] as String,
        exhibitorName: (m['exhibitor_name'] as String?) ?? '',
        isNew: m['new'] as bool? ?? false,
        name: (m['name'] as String?) ?? (m['username'] as String?) ?? 'Member',
        username: m['username'] as String?,
        car: m['car'] as String?,
      );
}

/// One member a booth scanned (`exhibitor_leads`). Phone and email only
/// when the member shares their contact with booths.
class Lead {
  const Lead({
    required this.id,
    required this.userId,
    required this.name,
    this.username,
    this.avatarUrl,
    this.state,
    this.carMake,
    this.carModel,
    required this.createdAt,
    this.note,
    this.shared = false,
    this.phone,
    this.email,
  });

  final String id;
  final String userId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? state;
  final String? carMake;
  final String? carModel;
  final DateTime createdAt;
  final String? note;
  final bool shared;
  final String? phone;
  final String? email;

  String? get car {
    final s = [carMake, carModel].whereType<String>().where((e) => e.trim().isNotEmpty).join(' ').trim();
    return s.isEmpty ? null : s;
  }

  bool get hasContact => (phone ?? '').isNotEmpty || (email ?? '').isNotEmpty;

  Lead copyWith({String? note}) => Lead(
        id: id,
        userId: userId,
        name: name,
        username: username,
        avatarUrl: avatarUrl,
        state: state,
        carMake: carMake,
        carModel: carModel,
        createdAt: createdAt,
        note: note ?? this.note,
        shared: shared,
        phone: phone,
        email: email,
      );

  factory Lead.fromMap(Map<String, dynamic> m) => Lead(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: (m['name'] as String?) ?? (m['username'] as String?) ?? 'Member',
        username: m['username'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        state: m['state'] as String?,
        carMake: m['car_make'] as String?,
        carModel: m['car_model'] as String?,
        createdAt: _date(m['created_at']) ?? DateTime.now(),
        note: m['note'] as String?,
        shared: m['shared'] as bool? ?? false,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
      );
}

/// A booth holding my contact (`my_event_leads`).
class MyLead {
  const MyLead({required this.id, required this.exhibitorId, required this.exhibitorName, this.booths = const [], this.createdAt});
  final String id;
  final String exhibitorId;
  final String exhibitorName;
  final List<String> booths;
  final DateTime? createdAt;

  factory MyLead.fromMap(Map<String, dynamic> m) => MyLead(
        id: m['id'] as String,
        exhibitorId: m['exhibitor_id'] as String,
        exhibitorName: (m['exhibitor_name'] as String?) ?? '',
        booths: _strings(m['booths']),
        createdAt: _date(m['created_at']),
      );
}

// ------------------------------------------------------------------ CSV ---

/// One CSV cell (RFC 4180): quoted when it holds a comma, quote or line
/// break, quotes doubled. Cells that a spreadsheet would run as a formula
/// (=, @, +, - not followed by a phone number, tab) get a leading apostrophe.
String csvCell(String? v) {
  var s = v ?? '';
  if (s.isNotEmpty) {
    final first = s[0];
    final phoneLike = RegExp(r'^[+-][0-9 ()-]+$').hasMatch(s);
    if (first == '=' || first == '@' || first == '\t' || first == '\r' || ((first == '+' || first == '-') && !phoneLike)) {
      s = "'$s";
    }
  }
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String csvRow(List<String?> cells) => cells.map(csvCell).join(',');

/// "2026-10-07 14:05" in the phone's time zone.
String csvTime(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// The leads export: header + one row per lead, CRLF line ends, with a
/// UTF-8 byte order mark so Excel reads names with accents right.
String leadsCsv(List<Lead> leads) {
  final rows = <String>[
    csvRow(['Name', 'Handle', 'State', 'Car', 'Phone', 'Email', 'Note', 'Saved at']),
    for (final l in leads) csvRow([l.name, l.username, l.state, l.car, l.phone, l.email, l.note, csvTime(l.createdAt)]),
  ];
  return '﻿${rows.join('\r\n')}\r\n';
}
