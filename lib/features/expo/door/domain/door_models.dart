// Expo mode, door & pass (docs/expo-mode-plan.md items 1-6).

/// "#0427": the entry number, zero-padded to 4.
String entryLabel(int n) => '#${n.toString().padLeft(4, '0')}';

/// What a pass QR encodes: `ttspot://pass/<eventId>/<passCode>`.
String passPayload(String eventId, String passCode) => 'ttspot://pass/$eventId/$passCode';

/// "350 m" / "1.2 km" / "5 km".
String formatMetres(int m) {
  if (m < 1000) return '$m m';
  final km = (m / 100).round() / 10;
  return km == km.roundToDouble() ? '${km.round()} km' : '${km.toStringAsFixed(1)} km';
}

/// My registration status for an event.
class HubRegistration {
  const HubRegistration({this.hasForm = false, this.required = false, this.done = false, this.questions = 0});
  final bool hasForm;
  final bool required;
  final bool done;
  final int questions;

  /// The form is there and I haven't answered it yet.
  bool get open => hasForm && !done;

  factory HubRegistration.fromMap(Map<String, dynamic>? m) => m == null
      ? const HubRegistration()
      : HubRegistration(
          hasForm: m['has_form'] as bool? ?? false,
          required: m['required'] as bool? ?? false,
          done: m['done'] as bool? ?? false,
          questions: (m['questions'] as num?)?.toInt() ?? 0,
        );
}

/// The car on my pass.
class HubCar {
  const HubCar({required this.id, this.title, this.cover, this.toyUrl});
  final String id;
  final String? title;
  final String? cover;
  final String? toyUrl;

  /// The toy when there is one, else the cover.
  String? get image => toyUrl ?? cover;

  static HubCar? fromMap(Map<String, dynamic>? m) => m == null || m['id'] == null
      ? null
      : HubCar(id: m['id'] as String, title: m['title'] as String?, cover: m['cover'] as String?, toyUrl: m['toy_url'] as String?);
}

/// A booth I staff.
class HubBooth {
  const HubBooth({required this.id, required this.name});
  final String id;
  final String name;
}

/// RPC `event_hub`: everything the hub card and my pass need, for me.
class EventHub {
  const EventHub({
    this.checkedIn = false,
    this.entryNo,
    this.passCode,
    this.shareContact = false,
    this.checkedInAt,
    this.live = false,
    this.registration = const HubRegistration(),
    this.levels = 0,
    this.exhibitors = 0,
    this.agenda = 0,
    this.stampStops = 0,
    this.myStamps = 0,
    this.stampGoal,
    this.contestId,
    this.contestTitle,
    this.myBooths = const [],
    this.isHost = false,
    this.car,
  });

  final bool checkedIn;
  final int? entryNo;
  final String? passCode;
  final bool shareContact;
  final DateTime? checkedInAt;

  /// Inside the check-in window right now.
  final bool live;
  final HubRegistration registration;

  /// Floor plan levels with an image.
  final int levels;
  final int exhibitors;
  final int agenda;
  final int stampStops;
  final int myStamps;
  final int? stampGoal;

  /// The latest open show-car vote.
  final String? contestId;
  final String? contestTitle;
  final List<HubBooth> myBooths;
  final bool isHost;
  final HubCar? car;

  String? get entry => entryNo == null ? null : entryLabel(entryNo!);

  /// Stamps needed to finish the rally: the host's goal, else every stop.
  int get stampTarget => stampGoal ?? stampStops;

  /// A big, official event: it has an Expo module (floor plan, exhibitors,
  /// schedule, stamp stops or an open vote). Its page shows module tabs.
  bool get isBig => levels > 0 || exhibitors > 0 || agenda > 0 || stampStops > 0 || contestId != null;

  /// Anything worth a hub card on the event page.
  bool get hasAnything =>
      checkedIn || levels > 0 || exhibitors > 0 || agenda > 0 || stampStops > 0 || contestId != null || myBooths.isNotEmpty;

  factory EventHub.fromMap(Map<String, dynamic> m) {
    final contest = (m['contest'] as Map?)?.cast<String, dynamic>();
    final at = m['checked_in_at'] as String?;
    return EventHub(
      checkedIn: m['checked_in'] as bool? ?? false,
      entryNo: (m['entry_no'] as num?)?.toInt(),
      passCode: m['pass_code'] as String?,
      shareContact: m['share_contact'] as bool? ?? false,
      checkedInAt: at == null ? null : DateTime.tryParse(at)?.toLocal(),
      live: m['live'] as bool? ?? false,
      registration: HubRegistration.fromMap((m['registration'] as Map?)?.cast<String, dynamic>()),
      levels: (m['levels'] as num?)?.toInt() ?? 0,
      exhibitors: (m['exhibitors'] as num?)?.toInt() ?? 0,
      agenda: (m['agenda'] as num?)?.toInt() ?? 0,
      stampStops: (m['stamp_stops'] as num?)?.toInt() ?? 0,
      myStamps: (m['my_stamps'] as num?)?.toInt() ?? 0,
      stampGoal: (m['stamp_goal'] as num?)?.toInt(),
      contestId: contest?['id'] as String?,
      contestTitle: contest?['title'] as String?,
      myBooths: [
        for (final b in (m['my_booths'] as List?) ?? const [])
          if (b is Map && b['id'] != null) HubBooth(id: b['id'] as String, name: (b['name'] as String?) ?? 'My booth'),
      ],
      isHost: m['is_host'] as bool? ?? false,
      car: HubCar.fromMap((m['car'] as Map?)?.cast<String, dynamic>()),
    );
  }
}

/// RPC `checkin_by_door`.
class DoorResult {
  const DoorResult({
    required this.eventId,
    required this.live,
    this.needLocation = false,
    this.isNew = false,
    this.entryNo,
    this.points = 0,
    this.hasFloorplan = false,
    this.distanceM,
    this.hasForm = false,
    this.formDone = false,
  });

  final String eventId;
  final bool live;

  /// Live and not checked in yet: send a location fix.
  final bool needLocation;
  final bool isNew;
  final int? entryNo;
  final int points;
  final bool hasFloorplan;
  final int? distanceM;
  final bool hasForm;
  final bool formDone;

  factory DoorResult.fromMap(Map<String, dynamic> m) => DoorResult(
        eventId: m['event_id'] as String,
        live: m['live'] as bool? ?? false,
        needLocation: m['need_location'] as bool? ?? false,
        isNew: m['new'] as bool? ?? false,
        entryNo: (m['entry_no'] as num?)?.toInt(),
        points: (m['points'] as num?)?.toInt() ?? 0,
        hasFloorplan: m['has_floorplan'] as bool? ?? false,
        distanceM: (m['distance_m'] as num?)?.toInt(),
        hasForm: m['has_form'] as bool? ?? false,
        formDone: m['form_done'] as bool? ?? false,
      );
}

// ------------------------------------------------------- registration ---

enum QuestionType {
  text('text', 'Short text'),
  one('one', 'One choice'),
  many('many', 'Many choices');

  const QuestionType(this.db, this.label);
  final String db;
  final String label;

  static QuestionType parse(String? v) => values.firstWhere((t) => t.db == v, orElse: () => QuestionType.text);
}

/// One question on an event's registration form.
class FormQuestion {
  const FormQuestion({required this.id, required this.label, this.type = QuestionType.text, this.options = const [], this.required = false});
  final String id;
  final String label;
  final QuestionType type;
  final List<String> options;
  final bool required;

  bool get hasOptions => type != QuestionType.text;

  factory FormQuestion.fromMap(Map<String, dynamic> m) => FormQuestion(
        id: (m['id'] as String?) ?? '',
        label: (m['label'] as String?) ?? '',
        type: QuestionType.parse(m['type'] as String?),
        options: [for (final o in (m['options'] as List?) ?? const []) '$o'],
        required: m['required'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'type': type.db,
        if (hasOptions) 'options': options,
        'required': required,
      };
}

/// Most questions a form can have (the table's check).
const kMaxFormQuestions = 8;

/// The default consent line under the questions.
const kDefaultConsent = 'I agree to share these answers with the organizer.';

/// `event_forms` row.
class RegistrationForm {
  const RegistrationForm({required this.eventId, this.questions = const [], this.consentText, this.askContact = true, this.required = false});
  final String eventId;
  final List<FormQuestion> questions;
  final String? consentText;
  final bool askContact;
  final bool required;

  bool get isEmpty => questions.isEmpty;
  String get consent => (consentText == null || consentText!.trim().isEmpty) ? kDefaultConsent : consentText!.trim();

  factory RegistrationForm.fromMap(Map<String, dynamic> m) => RegistrationForm(
        eventId: m['event_id'] as String,
        questions: [
          for (final q in (m['questions'] as List?) ?? const [])
            if (q is Map) FormQuestion.fromMap(q.cast<String, dynamic>()),
        ],
        consentText: m['consent_text'] as String?,
        askContact: m['ask_contact'] as bool? ?? true,
        required: m['required'] as bool? ?? false,
      );
}

/// My saved answers.
class MyRegistration {
  const MyRegistration({this.answers = const {}, this.contactOk = false});
  final Map<String, dynamic> answers;
  final bool contactOk;
}

/// A question id not used by [taken]: q1, q2…
String nextQuestionId(Iterable<String> taken) {
  final used = taken.toSet();
  var i = 1;
  while (used.contains('q$i')) {
    i++;
  }
  return 'q$i';
}

/// Problems that block saving a form in the editor, or null when it's fine.
String? validateForm(List<FormQuestion> questions) {
  if (questions.length > kMaxFormQuestions) return 'Up to $kMaxFormQuestions questions.';
  for (var i = 0; i < questions.length; i++) {
    final q = questions[i];
    if (q.label.trim().isEmpty) return 'Question ${i + 1} needs a question.';
    if (q.hasOptions) {
      final opts = q.options.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
      if (opts.length < 2) return 'Question ${i + 1} needs at least 2 options.';
      if (opts.toSet().length != opts.length) return 'Question ${i + 1} has the same option twice.';
    }
  }
  return null;
}

/// A row of `event_registrations_export`.
class RegistrationExportRow {
  const RegistrationExportRow({
    this.entryNo,
    required this.name,
    this.username,
    this.phone,
    this.email,
    this.state,
    this.car,
    this.checkedInAt,
    this.answers = const {},
  });

  final int? entryNo;
  final String name;
  final String? username;
  final String? phone;
  final String? email;
  final String? state;
  final String? car;
  final DateTime? checkedInAt;
  final Map<String, dynamic> answers;

  factory RegistrationExportRow.fromMap(Map<String, dynamic> m) {
    final at = m['checked_in_at'] as String?;
    return RegistrationExportRow(
      entryNo: (m['entry_no'] as num?)?.toInt(),
      name: (m['name'] as String?) ?? '',
      username: m['username'] as String?,
      phone: m['phone'] as String?,
      email: m['email'] as String?,
      state: m['state'] as String?,
      car: m['car'] as String?,
      checkedInAt: at == null ? null : DateTime.tryParse(at)?.toLocal(),
      answers: (m['answers'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}
