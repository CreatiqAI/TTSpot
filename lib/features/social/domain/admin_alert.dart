/// `admin` notifications: something waiting for an admin's review
/// (supabase/migrations/20261008000117_admin_alerts.sql). Only admins get them.
///
/// The body is `<kind>:<detail>`:
/// - `report:<target_type>:<reason>`  a member reported something,
/// - `spot:<place name>`              a member suggested a spot,
/// - `verify:<place name>`            a sticker check-in photo needs a look,
/// - `flagged:<post|moment>:<why>`    the photo check hid a post or moment.
///
/// supabase/functions/push/index.ts `adminAlert` uses the same titles and
/// routes (its push bodies name the member by display name).
library;

enum AdminAlertKind { report, spot, verify, flagged }

class AdminAlert {
  const AdminAlert(this.kind, this.subject, this.detail);
  final AdminAlertKind kind;

  /// report: the target type (post, profile, …); flagged: post or moment;
  /// spot / verify: the place name.
  final String subject;

  /// report: the reason; flagged: the categories; else empty.
  final String detail;

  static AdminAlert? parse(String? body) {
    final s = body ?? '';
    final colon = s.indexOf(':');
    if (colon < 0) return null;
    final kind = switch (s.substring(0, colon)) {
      'report' => AdminAlertKind.report,
      'spot' => AdminAlertKind.spot,
      'verify' => AdminAlertKind.verify,
      'flagged' => AdminAlertKind.flagged,
      _ => null,
    };
    if (kind == null) return null;
    final rest = s.substring(colon + 1).trim();
    if (kind == AdminAlertKind.spot || kind == AdminAlertKind.verify) return AdminAlert(kind, rest, '');
    final c = rest.indexOf(':');
    return c < 0 ? AdminAlert(kind, rest, '') : AdminAlert(kind, rest.substring(0, c).trim(), rest.substring(c + 1).trim());
  }

  /// "a post", "a member", … for a report's target type.
  static String targetLabel(String type) => switch (type) {
        'post' => 'a post',
        'post_comment' => 'a comment',
        'comment' => 'a meet comment',
        'profile' => 'a member',
        'event' => 'a meet',
        'message' => 'a message',
        'story' => 'a moment',
        'club' => 'a club',
        _ => 'something',
      };

  /// Short push title.
  String get title => switch (kind) {
        AdminAlertKind.report => 'Report',
        AdminAlertKind.spot => 'Spot suggested',
        AdminAlertKind.verify => 'Photo to check',
        AdminAlertKind.flagged => subject == 'moment' ? 'Flagged moment' : 'Flagged post',
      };

  /// The one-line Activity sentence. [who]: the member's @handle, if known.
  String sentence({String? who}) {
    final by = who == null || who.isEmpty ? '' : ' by @$who';
    return switch (kind) {
      AdminAlertKind.report => 'New report on ${targetLabel(subject)}${detail.isEmpty ? '' : ': $detail'}',
      AdminAlertKind.spot => 'Spot suggested$by: ${subject.isEmpty ? 'a new place' : subject}',
      AdminAlertKind.verify => 'Spot photo to check$by${subject.isEmpty ? '' : ' at $subject'}',
      AdminAlertKind.flagged =>
        'Photo check hid ${subject == 'moment' ? 'a moment' : 'a post'}$by${detail.isEmpty ? '' : ' ($detail)'}. Approve or remove it.',
    };
  }

  /// The admin screen with that queue.
  String get route => switch (kind) {
        AdminAlertKind.report => '/admin/queues',
        AdminAlertKind.spot => '/admin/queues?open=suggestions',
        AdminAlertKind.verify => '/admin/review',
        AdminAlertKind.flagged => '/admin/moderation',
      };
}
