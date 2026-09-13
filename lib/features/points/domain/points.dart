/// One row of the append-only points ledger.
class PointEntry {
  const PointEntry({required this.id, required this.delta, required this.reason, required this.label, required this.createdAt, this.refType, this.refId, this.note});
  final int id;
  final int delta;
  final String reason;
  final String label;
  final DateTime createdAt;
  final String? refType;
  final String? refId;
  final String? note;

  factory PointEntry.fromMap(Map<String, dynamic> m) => PointEntry(
        id: (m['id'] as num).toInt(),
        delta: (m['delta'] as num).toInt(),
        reason: m['reason'] as String,
        label: m['label'] as String? ?? m['reason'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        refType: m['ref_type'] as String?,
        refId: m['ref_id'] as String?,
        note: m['note'] as String?,
      );
}

/// How to earn: one row per rule in `point_rules`.
class PointRule {
  const PointRule({required this.reason, required this.points, required this.label, required this.description, required this.sort});
  final String reason;
  final int points;
  final String label;
  final String description;
  final int sort;

  factory PointRule.fromMap(Map<String, dynamic> m) => PointRule(
        reason: m['reason'] as String,
        points: (m['points'] as num).toInt(),
        label: m['label'] as String,
        description: m['description'] as String,
        sort: (m['sort'] as num?)?.toInt() ?? 100,
      );
}

/// What a scanned QR code means. Payloads:
///   `https://ttspot.my/u/{username}?t={token}` → friend
///   `ttspot://checkin/{eventId}/{code}`        → meet check-in
///   `ttspot://spot/{placeId}/{code}`           → spot sticker (phase 2)
sealed class ScannedCode {
  const ScannedCode();

  static ScannedCode? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme == 'ttspot') {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (uri.host == 'checkin' && segs.length >= 2) return MeetCheckinCode(eventId: segs[0], code: segs[1]);
      if (uri.host == 'spot' && segs.length >= 2) return SpotCode(placeId: segs[0], code: segs[1]);
      if (uri.host == 'voucher' && segs.length >= 2) return VoucherCode(claimId: segs[0], code: segs[1]);
      if (uri.host == 'u' && segs.isNotEmpty) return FriendCode(username: segs[0], token: uri.queryParameters['t'] ?? '');
      return null;
    }
    if ((uri.host == 'ttspot.my' || uri.host == 'www.ttspot.my') && uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'u') {
      return FriendCode(username: uri.pathSegments[1], token: uri.queryParameters['t'] ?? '');
    }
    return null;
  }
}

class FriendCode extends ScannedCode {
  const FriendCode({required this.username, required this.token});
  final String username;
  final String token;
}

class MeetCheckinCode extends ScannedCode {
  const MeetCheckinCode({required this.eventId, required this.code});
  final String eventId;
  final String code;
}

class SpotCode extends ScannedCode {
  const SpotCode({required this.placeId, required this.code});
  final String placeId;
  final String code;
}

/// A member's claimed voucher (`ttspot://voucher/<claimId>/<code>`). Only the
/// partner it belongs to can do anything with it.
class VoucherCode extends ScannedCode {
  const VoucherCode({required this.claimId, required this.code});
  final String claimId;
  final String code;
}
