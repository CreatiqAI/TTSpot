/// `partner` notifications: an application to be a partner shop, a car club
/// or a verified organizer, and the admin's decision on it.
///
/// The database (admin_review_partner / apply_partner / apply_organizer)
/// writes the body as `<what>[-club|-organizer]:<text>`:
/// - `applied…:<name>` to every admin (actor = the applicant),
/// - `approved…:<name>` to the applicant,
/// - `rejected…:<admin's note>` to the applicant ("no reason given" when blank).
///
/// supabase/functions/push/index.ts `applicationNotice` mirrors this copy.
library;

enum ApplicantRole { partner, club, organizer }

enum ApplicationStep { applied, approved, rejected }

class ApplicationNotice {
  const ApplicationNotice(this.step, this.kind, this.text);
  final ApplicationStep step;
  final ApplicantRole kind;

  /// Business / club / crew name (applied, approved) or the admin's note (rejected; may be empty).
  final String text;

  static ApplicationNotice? parse(String? body) {
    final s = body ?? '';
    final colon = s.indexOf(':');
    if (colon < 0) return null;
    final head = s.substring(0, colon).split('-');
    final step = switch (head.first) {
      'applied' => ApplicationStep.applied,
      'approved' => ApplicationStep.approved,
      'rejected' => ApplicationStep.rejected,
      _ => null,
    };
    if (step == null || head.length > 2) return null;
    final kind = switch (head.length == 2 ? head[1] : '') {
      '' => ApplicantRole.partner,
      'club' => ApplicantRole.club,
      'organizer' => ApplicantRole.organizer,
      _ => null,
    };
    if (kind == null) return null;
    var text = s.substring(colon + 1).trim();
    if (step == ApplicationStep.rejected && text.toLowerCase() == 'no reason given') text = '';
    return ApplicationNotice(step, kind, text);
  }

  String get _what => switch (kind) {
        ApplicantRole.partner => 'partner',
        ApplicantRole.club => 'car club',
        ApplicantRole.organizer => 'organizer',
      };

  /// What the applicant gets when it's approved, after the name.
  String get _ready => switch (kind) {
        ApplicantRole.partner => 'Your partner tools are ready.',
        ApplicantRole.club => 'Create your club and invite members.',
        ApplicantRole.organizer => 'Your organizer tools are ready.',
      };

  /// The sentence (no emoji: the push adds one, the Activity row shows art).
  /// For [ApplicationStep.applied] it follows the applicant's name.
  String get sentence => switch (step) {
        ApplicationStep.applied => switch (kind) {
            ApplicantRole.partner => 'applied to be a partner: $text',
            ApplicantRole.club => 'applied to run a car club: $text',
            ApplicantRole.organizer => 'applied to be a verified organizer: $text',
          },
        ApplicationStep.approved => '${text.isEmpty ? 'Your $_what application' : text} is approved. $_ready',
        ApplicationStep.rejected => "Your $_what application wasn't approved.${text.isEmpty ? '' : ' Note: $text'}",
      };

  /// Where a tap goes: admins to the queue; approved to the new tools;
  /// rejected to the application page (it shows the note and lets them reapply).
  String get route => switch (step) {
        ApplicationStep.applied => '/admin/partners',
        ApplicationStep.approved => switch (kind) {
            ApplicantRole.partner => '/vendor',
            ApplicantRole.club => '/create/club',
            ApplicantRole.organizer => '/organizer/apply',
          },
        ApplicationStep.rejected => switch (kind) {
            ApplicantRole.partner => '/partner/apply',
            ApplicantRole.club => '/club/apply',
            ApplicantRole.organizer => '/organizer/apply',
          },
      };
}
