// Organizer tools: my role at a meet, crew, announcements, lucky draws.

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
int _int(Object? v) => (v as num?)?.toInt() ?? 0;
List<Map<String, dynamic>> _list(Object? v) => ((v as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

/// What `my_event_role()` says about me at one meet.
class EventRole {
  const EventRole({this.role, this.tools = false, this.hostVerified = false, this.iAmOrganizer = false});

  /// 'host' | 'cohost' | 'crew' | 'admin' | null.
  final String? role;

  /// The organizer tools are on for this meet (its host is a verified organizer).
  final bool tools;
  final bool hostVerified;
  final bool iAmOrganizer;

  bool get isHost => role == 'host';
  bool get isCrewOnly => role == 'crew';
  /// Host, co-host, club officer or admin: announcements, draws, crew.
  bool get isHostCircle => role == 'host' || role == 'cohost' || role == 'admin';
  bool get onTeam => role != null;
  /// Host or admin: can add and change co-hosts.
  bool get managesCohosts => role == 'host' || role == 'admin';

  String get label => switch (role) {
        'host' => 'Host',
        'cohost' => 'Co-host',
        'crew' => 'Crew',
        'admin' => 'Admin',
        _ => 'Member',
      };

  static const none = EventRole();

  factory EventRole.fromMap(Map<String, dynamic>? m) => m == null
      ? none
      : EventRole(
          role: m['role'] as String?,
          tools: m['tools'] as bool? ?? false,
          hostVerified: m['host_verified'] as bool? ?? false,
          iAmOrganizer: m['i_am_organizer'] as bool? ?? false,
        );
}

class CrewMember {
  const CrewMember({required this.userId, this.username, this.displayName, this.avatarUrl, required this.role, this.addedAt});
  final String userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  /// 'host' | 'cohost' | 'crew'.
  final String role;
  final DateTime? addedAt;

  String get name => displayName ?? (username == null ? 'Member' : '@$username');
  String get roleLabel => switch (role) { 'host' => 'Host', 'cohost' => 'Co-host', _ => 'Crew' };

  factory CrewMember.fromMap(Map<String, dynamic> m) => CrewMember(
        userId: m['user_id'] as String,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        role: m['role'] as String? ?? 'crew',
        addedAt: _date(m['added_at']),
      );
}

/// Who an announcement reaches. Mirrors the check on event_announcements.audience.
enum Audience {
  linked('linked', 'Everyone linked', 'Checked in, going, or joined with your invite code'),
  checkedIn('checked_in', 'Checked in', 'Only people at the meet right now'),
  going('going', 'Going', 'Everyone who RSVP\'d'),
  everyone('everyone', 'Everyone', 'Linked, plus people who saved the meet, plus your crew');

  const Audience(this.db, this.label, this.hint);
  final String db;
  final String label;
  final String hint;

  static Audience fromDb(String? v) => values.firstWhere((a) => a.db == v, orElse: () => linked);
}

class EventAnnouncement {
  const EventAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.sendAt,
    this.sentAt,
    this.cancelledAt,
    this.recipients,
    this.authorUsername,
  });

  final String id;
  final String title;
  final String body;
  final Audience audience;
  final DateTime sendAt;
  final DateTime? sentAt;
  final DateTime? cancelledAt;
  final int? recipients;
  final String? authorUsername;

  bool get isSent => sentAt != null;
  bool get isCancelled => cancelledAt != null;
  bool get isScheduled => !isSent && !isCancelled;

  factory EventAnnouncement.fromMap(Map<String, dynamic> m) => EventAnnouncement(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        audience: Audience.fromDb(m['audience'] as String?),
        sendAt: _date(m['send_at'])!,
        sentAt: _date(m['sent_at']),
        cancelledAt: _date(m['cancelled_at']),
        recipients: (m['recipients'] as num?)?.toInt(),
        authorUsername: m['author_username'] as String?,
      );
}

// ----------------------------------------------------------- lucky draw ---

class DrawPrize {
  const DrawPrize({this.id, required this.name, this.quantity = 1});
  final String? id;
  final String name;
  final int quantity;

  Map<String, Object?> toJson() => {'name': name, 'quantity': quantity};

  factory DrawPrize.fromMap(Map<String, dynamic> m) => DrawPrize(
        id: m['id'] as String?,
        name: m['name'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
      );
}

enum DrawStatus {
  scheduled, drawn, cancelled;
  static DrawStatus fromDb(String? v) => switch (v) { 'drawn' => drawn, 'cancelled' => cancelled, _ => scheduled };
}

/// A row of `lucky_draws` with its prizes (organizer list and edit form).
class LuckyDraw {
  const LuckyDraw({
    required this.id,
    required this.eventId,
    required this.title,
    required this.drawAt,
    required this.cutoffAt,
    required this.mustBePresent,
    required this.claimMinutes,
    required this.status,
    this.entrantCount,
    this.seedHash,
    this.prizes = const [],
    this.presenceMinutes,
    this.presenceAskedAt,
  });

  final String id;
  final String eventId;
  final String title;
  final DateTime drawAt;
  final DateTime cutoffAt;
  final bool mustBePresent;
  final int claimMinutes;
  final DrawStatus status;
  final int? entrantCount;
  final String? seedHash;
  final List<DrawPrize> prizes;

  /// Roll call: ask everyone to confirm they're here this many minutes
  /// before the draw; only confirmed members enter. Null = off.
  final int? presenceMinutes;
  final DateTime? presenceAskedAt;

  int get winnerCount => prizes.fold(0, (s, p) => s + p.quantity);

  bool get hasRollCall => presenceMinutes != null;
  DateTime? get rollCallOpensAt => rollCallOpens(drawAt, presenceMinutes);
  bool rollCallOpenAt(DateTime now) => status == DrawStatus.scheduled && rollCallOpenNow(drawAt, cutoffAt, presenceMinutes, now);

  factory LuckyDraw.fromMap(Map<String, dynamic> m) {
    final prizes = _list(m['lucky_draw_prizes'])..sort((a, b) => _int(a['sort']).compareTo(_int(b['sort'])));
    final drawAt = _date(m['draw_at'])!;
    return LuckyDraw(
      id: m['id'] as String,
      eventId: m['event_id'] as String,
      title: m['title'] as String? ?? 'Lucky draw',
      drawAt: drawAt,
      cutoffAt: _date(m['cutoff_at']) ?? drawAt,
      mustBePresent: m['must_be_present'] as bool? ?? true,
      claimMinutes: (m['claim_minutes'] as num?)?.toInt() ?? 15,
      status: DrawStatus.fromDb(m['status'] as String?),
      entrantCount: (m['entrant_count'] as num?)?.toInt(),
      seedHash: m['seed_hash'] as String?,
      prizes: prizes.map(DrawPrize.fromMap).toList(),
      presenceMinutes: (m['presence_minutes'] as num?)?.toInt(),
      presenceAskedAt: _date(m['presence_asked_at']),
    );
  }
}

/// My result in one draw.
class MyWin {
  const MyWin({
    required this.id,
    this.prize,
    required this.rank,
    required this.claimCode,
    this.expiresAt,
    required this.status,
    required this.isAlternate,
    required this.hasPrize,
    this.claimedAt,
  });

  final String id;
  final String? prize;
  final int rank;
  final String claimCode;
  final DateTime? expiresAt;
  /// 'pending' | 'claimed' | 'expired' | 'forfeited'.
  final String status;
  final bool isAlternate;
  final bool hasPrize;
  final DateTime? claimedAt;

  /// The QR crew scan at the stage.
  String get qrPayload => 'ttspot://drawclaim/$claimCode';

  bool get isOpen => hasPrize && status == 'pending' && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));
  bool get isClosed => status == 'expired' || status == 'forfeited' || (hasPrize && status == 'pending' && expiresAt != null && !expiresAt!.isAfter(DateTime.now()));
  bool get onStandby => !hasPrize && status == 'pending';

  factory MyWin.fromMap(Map<String, dynamic> m) => MyWin(
        id: m['id'] as String,
        prize: m['prize'] as String?,
        rank: _int(m['rank']),
        claimCode: m['claim_code'] as String? ?? '',
        expiresAt: _date(m['expires_at']),
        status: m['status'] as String? ?? 'pending',
        isAlternate: m['is_alternate'] as bool? ?? false,
        hasPrize: m['has_prize'] as bool? ?? false,
        claimedAt: _date(m['claimed_at']),
      );
}

/// One draw as a member sees it (`my_draw_status`).
class MyDraw {
  const MyDraw({
    required this.id,
    required this.title,
    required this.drawAt,
    required this.cutoffAt,
    required this.mustBePresent,
    required this.claimMinutes,
    required this.status,
    this.entrantCount,
    this.prizes = const [],
    this.checkedIn = false,
    this.eligible = false,
    this.excluded,
    this.win,
    this.entryNo,
    this.presenceRequired = false,
    this.presenceMinutes,
    this.presenceOpen = false,
    this.presenceConfirmed = false,
  });

  final String id;
  final String title;
  final DateTime drawAt;
  final DateTime cutoffAt;
  final bool mustBePresent;
  final int claimMinutes;
  final DrawStatus status;
  final int? entrantCount;
  final List<DrawPrize> prizes;
  final bool checkedIn;
  final bool eligible;
  /// 'host' | 'crew' when I can't enter because I'm running it.
  final String? excluded;
  final MyWin? win;

  /// My entry number at this event (#0427), once checked in.
  final int? entryNo;

  /// Roll call is on: only members who tap "I'm here" in time are in.
  final bool presenceRequired;
  final int? presenceMinutes;

  /// The server's view when this was fetched; [rollCallOpenAt] follows the clock.
  final bool presenceOpen;
  final bool presenceConfirmed;

  bool get cutoffPassed => cutoffAt.isBefore(DateTime.now());
  int get winnerCount => prizes.fold(0, (s, p) => s + p.quantity);

  DateTime? get rollCallOpensAt => presenceRequired ? rollCallOpens(drawAt, presenceMinutes) : null;
  bool rollCallOpenAt(DateTime now) => presenceRequired && status == DrawStatus.scheduled && rollCallOpenNow(drawAt, cutoffAt, presenceMinutes, now);

  factory MyDraw.fromMap(Map<String, dynamic> m) {
    final drawAt = _date(m['draw_at'])!;
    return MyDraw(
      id: m['id'] as String,
      title: m['title'] as String? ?? 'Lucky draw',
      drawAt: drawAt,
      cutoffAt: _date(m['cutoff_at']) ?? drawAt,
      mustBePresent: m['must_be_present'] as bool? ?? true,
      claimMinutes: (m['claim_minutes'] as num?)?.toInt() ?? 15,
      status: DrawStatus.fromDb(m['status'] as String?),
      entrantCount: (m['entrant_count'] as num?)?.toInt(),
      prizes: _list(m['prizes']).map(DrawPrize.fromMap).toList(),
      checkedIn: m['checked_in'] as bool? ?? false,
      eligible: m['eligible'] as bool? ?? false,
      excluded: m['excluded'] as String?,
      win: m['win'] == null ? null : MyWin.fromMap((m['win'] as Map).cast<String, dynamic>()),
      entryNo: (m['entry_no'] as num?)?.toInt(),
      presenceRequired: m['presence_required'] as bool? ?? false,
      presenceMinutes: (m['presence_minutes'] as num?)?.toInt(),
      presenceOpen: m['presence_open'] as bool? ?? false,
      presenceConfirmed: m['presence_confirmed'] as bool? ?? false,
    );
  }
}

/// A public winners-list row (`draw_results`).
class DrawResult {
  const DrawResult({required this.rank, required this.prize, required this.displayName, this.userId, this.username, this.avatarUrl, required this.status, this.entryNo});
  final int rank;
  final String prize;
  final String displayName;
  /// The winner; picks their default avatar.
  final String? userId;
  final String? username;
  final String? avatarUrl;
  final String status;
  final int? entryNo;

  factory DrawResult.fromMap(Map<String, dynamic> m) => DrawResult(
        rank: _int(m['rank']),
        prize: m['prize'] as String? ?? '',
        displayName: m['display_name'] as String? ?? 'Member',
        userId: m['user_id'] as String?,
        username: m['username'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        status: m['status'] as String? ?? 'pending',
        entryNo: (m['entry_no'] as num?)?.toInt(),
      );
}

/// A winner or alternate on the stage screen.
class StageWinner {
  const StageWinner({
    required this.id,
    required this.rank,
    this.prize,
    this.prizeId,
    this.prizeSort = 0,
    required this.displayName,
    this.userId,
    this.username,
    this.avatarUrl,
    required this.status,
    required this.isAlternate,
    this.expiresAt,
    this.claimedAt,
    this.promotedAt,
    this.entryNo,
  });

  final String id;
  final int rank;
  final String? prize;
  final String? prizeId;
  final int prizeSort;
  final String displayName;
  /// The winner; picks their default avatar.
  final String? userId;
  final String? username;
  final String? avatarUrl;
  final String status;
  final bool isAlternate;
  final DateTime? expiresAt;
  final DateTime? claimedAt;
  final DateTime? promotedAt;

  /// Their entry number at the event (#0427): what the stage calls out.
  final int? entryNo;

  bool get hasPrize => prizeId != null;

  factory StageWinner.fromMap(Map<String, dynamic> m) => StageWinner(
        id: m['id'] as String,
        rank: _int(m['rank']),
        prize: m['prize'] as String?,
        prizeId: m['prize_id'] as String?,
        prizeSort: _int(m['prize_sort']),
        displayName: m['display_name'] as String? ?? 'Member',
        userId: m['user_id'] as String?,
        username: m['username'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        status: m['status'] as String? ?? 'pending',
        isAlternate: m['is_alternate'] as bool? ?? false,
        expiresAt: _date(m['expires_at']),
        claimedAt: _date(m['claimed_at']),
        promotedAt: _date(m['promoted_at']),
        entryNo: (m['entry_no'] as num?)?.toInt(),
      );
}

/// Everything the stage screen shows (`draw_stage`).
class DrawStage {
  const DrawStage({
    required this.id,
    required this.eventId,
    required this.title,
    required this.status,
    required this.drawAt,
    required this.cutoffAt,
    required this.mustBePresent,
    required this.claimMinutes,
    this.drawnAt,
    this.seedHash,
    this.seedReveal,
    this.entrantsHash,
    required this.entrantCount,
    required this.checkedIn,
    required this.names,
    required this.prizes,
    required this.winners,
    this.presenceMinutes,
    this.presenceConfirmed = 0,
    this.entryNos = const [],
  });

  final String id;
  final String eventId;
  final String title;
  final DrawStatus status;
  final DateTime drawAt;
  final DateTime cutoffAt;
  final bool mustBePresent;
  final int claimMinutes;
  final DateTime? drawnAt;
  final String? seedHash;
  final String? seedReveal;
  final String? entrantsHash;
  final int entrantCount;
  final int checkedIn;
  final List<String> names;
  final List<DrawPrize> prizes;
  final List<StageWinner> winners;

  /// Roll call minutes before the draw (null = off) and how many confirmed.
  final int? presenceMinutes;
  final int presenceConfirmed;

  /// A random sample of entrants' numbers to roll during the reveal.
  final List<int> entryNos;

  bool get hasRollCall => presenceMinutes != null;

  /// Winners holding a prize, in prize order then rank (the reveal order).
  List<StageWinner> get prizeWinners =>
      winners.where((w) => w.hasPrize).toList()..sort((a, b) => a.prizeSort != b.prizeSort ? a.prizeSort.compareTo(b.prizeSort) : a.rank.compareTo(b.rank));
  List<StageWinner> get standby => winners.where((w) => !w.hasPrize && w.status == 'pending').toList();

  factory DrawStage.fromMap(Map<String, dynamic> m) {
    final drawAt = _date(m['draw_at'])!;
    return DrawStage(
      id: m['id'] as String,
      eventId: m['event_id'] as String,
      title: m['title'] as String? ?? 'Lucky draw',
      status: DrawStatus.fromDb(m['status'] as String?),
      drawAt: drawAt,
      cutoffAt: _date(m['cutoff_at']) ?? drawAt,
      mustBePresent: m['must_be_present'] as bool? ?? true,
      claimMinutes: (m['claim_minutes'] as num?)?.toInt() ?? 15,
      drawnAt: _date(m['drawn_at']),
      seedHash: m['seed_hash'] as String?,
      seedReveal: m['seed_reveal'] as String?,
      entrantsHash: m['entrants_hash'] as String?,
      entrantCount: _int(m['entrant_count']),
      checkedIn: _int(m['checked_in']),
      names: ((m['names'] as List?) ?? const []).map((e) => '$e').toList(),
      prizes: _list(m['prizes']).map(DrawPrize.fromMap).toList(),
      winners: _list(m['winners']).map(StageWinner.fromMap).toList(),
      presenceMinutes: (m['presence_minutes'] as num?)?.toInt(),
      presenceConfirmed: _int(m['presence_confirmed']),
      entryNos: ((m['entry_nos'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toList(),
    );
  }
}

/// What `claim_prize()` answers when crew scan a winner's QR.
class PrizeClaimResult {
  const PrizeClaimResult({required this.ok, required this.message, this.prize, this.displayName, this.userId, this.username, this.avatarUrl, this.rank});
  final bool ok;
  final String message;
  final String? prize;
  final String? displayName;
  /// The winner; picks their default avatar.
  final String? userId;
  final String? username;
  final String? avatarUrl;
  final int? rank;

  factory PrizeClaimResult.fromMap(Map<String, dynamic> m) => PrizeClaimResult(
        ok: m['ok'] as bool? ?? false,
        message: m['message'] as String? ?? '',
        prize: m['prize'] as String?,
        displayName: m['display_name'] as String?,
        userId: m['user_id'] as String?,
        username: m['username'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        rank: (m['rank'] as num?)?.toInt(),
      );
}

/// A scanned `ttspot://drawclaim/<code>` QR, or null.
String? parseDrawClaimCode(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'ttspot' || uri.host != 'drawclaim') return null;
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return segs.isEmpty ? null : segs.first;
}

/// "#0427": a member's entry number at an event (= their lucky draw number).
String formatEntryNo(int n) => '#${n.toString().padLeft(4, '0')}';

/// When the roll call opens, or null when it's off.
DateTime? rollCallOpens(DateTime drawAt, int? minutes) => minutes == null ? null : drawAt.subtract(Duration(minutes: minutes));

/// The roll call is open from draw time minus [minutes] until entries close.
bool rollCallOpenNow(DateTime drawAt, DateTime cutoffAt, int? minutes, DateTime now) {
  final opens = rollCallOpens(drawAt, minutes);
  return opens != null && !now.isBefore(opens) && !now.isAfter(cutoffAt);
}

/// Roll call choices on the draw form (minutes before the draw).
const kRollCallMinutes = [10, 15, 30];

/// A name for the big screen: "Ahmad Rizal" -> "Ah*** Ri***". The entry
/// number is what identifies the winner on stage.
String maskName(String name) {
  final words = name.trim().replaceAll('@', '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.map((w) {
    final chars = w.runes.toList();
    if (chars.length <= 1) return w;
    final keep = chars.length <= 3 ? 1 : 2;
    final stars = (chars.length - keep).clamp(1, 4);
    return String.fromCharCodes(chars.take(keep)) + '*' * stars;
  }).join(' ');
}

/// Typical turnout options on the organizer application.
const kEventSizes = ['Under 30', '30 to 100', '100 to 300', '300+'];
