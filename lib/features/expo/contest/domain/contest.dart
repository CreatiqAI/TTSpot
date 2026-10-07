/// The show car vote (People's Choice), migration 0123 `contest_board`.
library;

import '../../../../core/utils/dates.dart';
import '../../expo_routes.dart';

enum ContestStatus {
  open,
  closed,
  cancelled;

  static ContestStatus parse(String? s) => switch (s) {
        'closed' => closed,
        'cancelled' => cancelled,
        _ => open,
      };
}

enum EntryStatus {
  pending,
  approved,
  rejected;

  static EntryStatus parse(String? s) => switch (s) {
        'approved' => approved,
        'rejected' => rejected,
        _ => pending,
      };
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
int? _int(Object? v) => (v as num?)?.toInt();

class Contest {
  const Contest({
    required this.id,
    required this.eventId,
    required this.title,
    this.about,
    this.opensAt,
    this.closesAt,
    this.membersEnter = true,
    this.status = ContestStatus.open,
    this.ended = false,
    this.notYet = false,
  });

  final String id;
  final String eventId;
  final String title;
  final String? about;
  final DateTime? opensAt;
  final DateTime? closesAt;
  /// Members can enter their own car (the host approves).
  final bool membersEnter;
  final ContestStatus status;
  /// Closed by the host, or its closing time passed: results are public.
  final bool ended;
  /// It opens later.
  final bool notYet;

  bool get cancelled => status == ContestStatus.cancelled;
  bool get live => !cancelled && !ended && !notYet;

  factory Contest.fromMap(Map<String, dynamic> m) => Contest(
        id: m['id'] as String,
        eventId: m['event_id'] as String,
        title: m['title'] as String? ?? 'Show car vote',
        about: m['about'] as String?,
        opensAt: _date(m['opens_at']),
        closesAt: _date(m['closes_at']),
        membersEnter: m['members_enter'] as bool? ?? true,
        status: ContestStatus.parse(m['status'] as String?),
        ended: m['ended'] as bool? ?? false,
        notYet: m['not_yet'] as bool? ?? false,
      );
}

class ContestEntry {
  const ContestEntry({
    required this.id,
    this.number,
    this.status = EntryStatus.approved,
    required this.userId,
    this.carId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.make,
    this.model,
    this.year,
    this.toyUrl,
    this.cover,
    this.votes,
    this.mine = false,
  });

  final String id;
  final int? number;
  final EntryStatus status;
  final String userId;
  final String? carId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? make;
  final String? model;
  final int? year;
  final String? toyUrl;
  final String? cover;
  /// Null when counts are hidden (members, until the vote ends).
  final int? votes;
  final bool mine;

  String get carName {
    final s = '${make ?? ''} ${model ?? ''}'.trim();
    return s.isEmpty ? 'Car' : s;
  }

  String get handle => username == null ? '' : '@$username';
  String get ownerName => displayName ?? (username == null ? 'Member' : '@$username');

  /// The toy render when there is one, else the cover photo.
  String? get image => (toyUrl ?? '').isNotEmpty ? toyUrl : ((cover ?? '').isNotEmpty ? cover : null);
  bool get imageIsToy => (toyUrl ?? '').isNotEmpty;

  factory ContestEntry.fromMap(Map<String, dynamic> m) => ContestEntry(
        id: m['id'] as String,
        number: _int(m['number']),
        status: EntryStatus.parse(m['status'] as String?),
        userId: m['user_id'] as String? ?? '',
        carId: m['car_id'] as String?,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        make: m['make'] as String?,
        model: m['model'] as String?,
        year: _int(m['year']),
        toyUrl: m['toy_url'] as String?,
        cover: m['cover'] as String?,
        votes: _int(m['votes']),
        mine: m['mine'] as bool? ?? false,
      );
}

/// My place in the vote.
class ContestMe {
  const ContestMe({this.myVoteEntryId, this.myEntry, this.canVote = false, this.reason, this.checkedIn = false, this.going = false, this.canEnter = false});

  final String? myVoteEntryId;
  final ContestEntry? myEntry;
  final bool canVote;
  /// Why I can't vote ("Check in at the event to vote"), or null.
  final String? reason;
  final bool checkedIn;
  final bool going;
  final bool canEnter;

  factory ContestMe.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ContestMe();
    final e = m['my_entry'];
    return ContestMe(
      myVoteEntryId: m['my_vote_entry_id'] as String?,
      myEntry: e == null ? null : ContestEntry.fromMap({...(e as Map).cast<String, dynamic>(), 'mine': true}),
      canVote: m['can_vote'] as bool? ?? false,
      reason: m['reason'] as String?,
      checkedIn: m['checked_in'] as bool? ?? false,
      going: m['going'] as bool? ?? false,
      canEnter: m['can_enter'] as bool? ?? false,
    );
  }
}

class ContestBoard {
  const ContestBoard({required this.contest, required this.entries, this.isHost = false, this.countsVisible = false, this.totalVotes, this.me = const ContestMe()});

  final Contest contest;
  /// Approved entries (and, for the host, pending ones), by number.
  final List<ContestEntry> entries;
  final bool isHost;
  final bool countsVisible;
  final int? totalVotes;
  final ContestMe me;

  List<ContestEntry> get approved => entries.where((e) => e.status == EntryStatus.approved).toList();
  List<ContestEntry> get pending => entries.where((e) => e.status == EntryStatus.pending).toList();

  ContestEntry? entry(String id) => entries.where((e) => e.id == id).firstOrNull;
  ContestEntry? get myVote => me.myVoteEntryId == null ? null : entry(me.myVoteEntryId!);

  factory ContestBoard.fromMap(Map<String, dynamic> m) => ContestBoard(
        contest: Contest.fromMap((m['contest'] as Map).cast<String, dynamic>()),
        entries: ((m['entries'] as List?) ?? const []).map((e) => ContestEntry.fromMap((e as Map).cast<String, dynamic>())).toList(),
        isHost: m['is_host'] as bool? ?? false,
        countsVisible: m['counts_visible'] as bool? ?? false,
        totalVotes: _int(m['total_votes']),
        me: ContestMe.fromMap((m['me'] as Map?)?.cast<String, dynamic>()),
      );
}

/// One row of the results: the place is shared on a tie (1, 2, 2, 4).
class RankedEntry {
  const RankedEntry(this.place, this.entry);
  final int place;
  final ContestEntry entry;
}

/// Approved entries by votes (most first), ties sharing a place; equal votes
/// keep number order.
List<RankedEntry> rankEntries(List<ContestEntry> entries) {
  final list = entries.where((e) => e.status == EntryStatus.approved).toList()
    ..sort((a, b) {
      final v = (b.votes ?? 0).compareTo(a.votes ?? 0);
      if (v != 0) return v;
      return (a.number ?? 1 << 30).compareTo(b.number ?? 1 << 30);
    });
  final out = <RankedEntry>[];
  for (var i = 0; i < list.length; i++) {
    final place = i > 0 && (list[i].votes ?? 0) == (list[i - 1].votes ?? 0) ? out[i - 1].place : i + 1;
    out.add(RankedEntry(place, list[i]));
  }
  return out;
}

/// What a vote QR encodes.
String voteQrPayload(String entryId) => 'ttspot://vote/$entryId';

/// Where a vote QR leads (`contest_entry_info`).
class ContestEntryInfo {
  const ContestEntryInfo({required this.entryId, required this.contestId, required this.eventId, this.number, this.status = EntryStatus.approved, this.contestStatus = ContestStatus.open, this.title, this.car});
  final String entryId;
  final String contestId;
  final String eventId;
  final int? number;
  final EntryStatus status;
  final ContestStatus contestStatus;
  final String? title;
  final String? car;

  factory ContestEntryInfo.fromMap(Map<String, dynamic> m) => ContestEntryInfo(
        entryId: m['entry_id'] as String,
        contestId: m['contest_id'] as String,
        eventId: m['event_id'] as String,
        number: _int(m['number']),
        status: EntryStatus.parse(m['status'] as String?),
        contestStatus: ContestStatus.parse(m['contest_status'] as String?),
        title: m['title'] as String?,
        car: m['car'] as String?,
      );
}

/// A vote route that opens one entry's sheet (`?entry=`), read by ContestScreen.
String voteEntryRoute(String eventId, String contestId, String entryId) => '${ExpoRoutes.vote(eventId, contestId: contestId)}&entry=$entryId';

String _when(DateTime t, DateTime now) {
  final l = t.toLocal();
  final n = now.toLocal();
  return l.year == n.year && l.month == n.month && l.day == n.day ? formatTime(l) : formatEventDate(l);
}

/// "Voting open · closes 6:00 PM", "Opens 2:00 PM", "Closed · results are in".
String contestStatusLine(Contest c, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (c.cancelled) return 'Cancelled';
  if (c.ended) return 'Closed · results are in';
  if (c.notYet && c.opensAt != null) return 'Opens ${_when(c.opensAt!, n)}';
  if (c.closesAt != null) return 'Voting open · closes ${_when(c.closesAt!, n)}';
  return 'Voting open';
}
