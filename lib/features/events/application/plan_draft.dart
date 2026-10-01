import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/geo/latlng.dart';
import '../domain/cover_presets.dart';
import '../domain/event.dart';

/// The questions of the plan wizard, one per screen.
enum PlanStep {
  kind('What kind', 'Kind'),
  where('Where', 'Where'),
  when('When', 'When'),
  who('Who', 'Who'),
  style('Make it yours', 'Look'),
  review('Review', 'Review');

  const PlanStep(this.title, this.short);
  final String title;
  final String short;
}

/// A one-tap start time ("Tonight", "Tomorrow night", "This weekend").
typedef QuickTime = ({String label, DateTime at});

/// Everything the plan wizard has collected so far. Lives as long as the
/// wizard, so going back and forth between steps never loses an answer.
class PlanDraft extends ChangeNotifier {
  PlanDraft({required this.session, this.underground = false, LatLng? at, String? venue, DateTime? now})
      : type = session ? EventType.tt : EventType.meet {
    final t = now ?? DateTime.now();
    startsAt = session ? _defaultSessionStart(t) : _defaultMeetStart(t);
    pin = at;
    if (venue != null && venue.trim().isNotEmpty) venueCtrl.text = venue.trim();
    venueCtrl.addListener(_venueChanged);
    _suggestTitle();
  }

  /// A TT session (anyone) rather than a hosted meet (clubs / partners).
  final bool session;

  /// Underground clubs may only plan 7 days ahead (set once the club loads).
  bool underground;

  EventType type;

  // ---- where
  LatLng? pin;
  /// Street address from Places, cleared once the pin is dragged away.
  String? address;
  final venueCtrl = TextEditingController();
  String get venue => venueCtrl.text.trim();

  // ---- when
  late DateTime startsAt;
  /// TT sessions only: how long it stays on the map.
  int minutes = 120;

  // ---- who
  bool friendsOnly = true;
  final Set<String> invitees = {};

  // ---- make it yours
  final titleCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  /// The member typed their own title: stop suggesting one.
  bool titleEdited = false;
  /// A preset id from [kCoverPresets]; null with no [coverFile] = the type's own cover.
  String? presetId;
  XFile? coverFile;

  List<PlanStep> get steps => session
      ? const [PlanStep.where, PlanStep.when, PlanStep.who, PlanStep.style, PlanStep.review]
      : const [PlanStep.kind, PlanStep.where, PlanStep.when, PlanStep.who, PlanStep.style, PlanStep.review];

  DateTime? get endsAt => session ? startsAt.add(Duration(minutes: minutes)) : null;

  /// The latest a meet may start: a week for underground clubs, else a year.
  DateTime maxStart(DateTime now) => now.add(Duration(days: underground ? 7 : 365));

  String get suggestedTitle {
    final where = venue.isEmpty ? null : venue;
    final head = session ? 'TT' : type.label;
    final t = where == null ? (session ? 'TT session' : type.label) : '$head @ $where';
    return t.length <= 80 ? t : t.substring(0, 80).trimRight();
  }

  String get title => titleCtrl.text.trim();

  /// What shows as the cover: a picked preset, else the type's own one.
  String get coverAsset => kCoverPresets.where((p) => p.id == presetId).firstOrNull?.asset ?? type.defaultCover;

  /// The preset's public URL to save in `cover_url` (null = type default or a photo).
  String? get presetUrl {
    if (coverFile != null || presetId == null || presetId == type.db) return null;
    return kCoverPresets.where((p) => p.id == presetId).firstOrNull?.url;
  }

  bool get isDirty => pin != null || venue.isNotEmpty || invitees.isNotEmpty || coverFile != null || notesCtrl.text.trim().isNotEmpty || titleEdited;

  // ------------------------------------------------------------ changes ---

  void setType(EventType t) {
    type = t;
    _suggestTitle();
    notifyListeners();
  }

  /// A place from search, a chip, or my location.
  void setPlace(LatLng at, {required String name, String? address}) {
    pin = at;
    this.address = (address ?? '').trim().isEmpty ? null : address!.trim();
    venueCtrl.text = name; // listener re-suggests the title
    notifyListeners();
  }

  /// The pin was dragged on the map: a move of more than ~50 m is no longer
  /// "that address".
  void nudgePin(LatLng at) {
    final old = pin;
    if (old != null && (at.latitude - old.latitude).abs() + (at.longitude - old.longitude).abs() > 0.0005) address = null;
    pin = at;
    notifyListeners();
  }

  void setStart(DateTime t) {
    startsAt = t;
    notifyListeners();
  }

  void setMinutes(int m) {
    minutes = m.clamp(15, 480);
    notifyListeners();
  }

  void setFriendsOnly(bool v) {
    friendsOnly = v;
    notifyListeners();
  }

  void toggleInvite(String id) {
    if (!invitees.remove(id)) invitees.add(id);
    notifyListeners();
  }

  void setInvites(Iterable<String> ids) {
    invitees
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void pickPreset(String id) {
    presetId = id;
    coverFile = null;
    notifyListeners();
  }

  void setCoverFile(XFile f) {
    coverFile = f;
    notifyListeners();
  }

  /// Typed in the title field: from now on the title is theirs (clearing
  /// it must not snap the suggestion back while they type a new one).
  void titleTyped() {
    titleEdited = true;
    notifyListeners();
  }

  void _venueChanged() {
    _suggestTitle();
    notifyListeners();
  }

  void _suggestTitle() {
    if (titleEdited) return;
    final s = suggestedTitle;
    if (titleCtrl.text != s) titleCtrl.text = s;
  }

  // ---------------------------------------------------------- validation ---

  /// What is still missing on [step], or null when it is answered.
  String? problem(PlanStep step, {DateTime? now}) {
    final t = now ?? DateTime.now();
    switch (step) {
      case PlanStep.kind:
      case PlanStep.who:
        return null;
      case PlanStep.where:
        if (pin == null) return 'Pick a place, or tap Use my location.';
        if (venue.isEmpty) return 'Give the place a name so people know where to go.';
        return null;
      case PlanStep.when:
        if (startsAt.isBefore(t.add(const Duration(minutes: 10)))) return 'Pick a time at least 10 minutes from now.';
        if (startsAt.isAfter(maxStart(t))) return underground ? 'Underground clubs can plan up to 7 days ahead.' : 'Pick a date within a year.';
        return null;
      case PlanStep.style:
        if (title.length < 3) return 'Give it a title (at least 3 characters).';
        return null;
      case PlanStep.review:
        for (final s in steps) {
          if (s == PlanStep.review) continue;
          final p = problem(s, now: t);
          if (p != null) return p;
        }
        return null;
    }
  }

  @override
  void dispose() {
    venueCtrl.dispose();
    titleCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------- quick times ---

  static DateTime _round5(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute - t.minute % 5);

  /// TT sessions: tonight 9 pm, or in an hour if it's already late.
  static DateTime _defaultSessionStart(DateTime now) {
    final tonight = DateTime(now.year, now.month, now.day, 21);
    return _round5(tonight.isAfter(now.add(const Duration(minutes: 30))) ? tonight : now.add(const Duration(hours: 1)));
  }

  /// Meets: next Saturday, 8 pm.
  static DateTime _defaultMeetStart(DateTime now) {
    var days = (DateTime.saturday - now.weekday) % 7;
    if (days == 0 && now.hour >= 20) days = 7;
    final sat = DateTime(now.year, now.month, now.day).add(Duration(days: days));
    return DateTime(sat.year, sat.month, sat.day, 20);
  }

  /// One-tap start times. Evening = 9 pm for TT sessions, 8 pm for meets.
  static List<QuickTime> quickTimes(DateTime now, {bool session = true}) {
    final hour = session ? 21 : 20;
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(DateTime day) => DateTime(day.year, day.month, day.day, hour);
    bool open(DateTime t) => t.isAfter(now.add(const Duration(minutes: 30)));
    final out = <QuickTime>[];

    // Tonight: the usual hour, or in an hour when that has passed (until 11 pm).
    final tonight = at(today);
    if (open(tonight)) {
      out.add((label: 'Tonight', at: tonight));
    } else if (now.hour < 23) {
      final soon = now.add(const Duration(hours: 1));
      out.add((label: 'Tonight', at: DateTime(soon.year, soon.month, soon.day, soon.hour, soon.minute + (15 - soon.minute % 15) % 15)));
    }
    out.add((label: 'Tomorrow night', at: at(today.add(const Duration(days: 1)))));

    // This weekend: the coming Saturday (Sunday when Saturday night is gone).
    var sat = today.add(Duration(days: (DateTime.saturday - now.weekday) % 7));
    if (now.weekday == DateTime.sunday) sat = today.subtract(const Duration(days: 1));
    var weekend = at(sat);
    if (!open(weekend)) weekend = at(sat.add(const Duration(days: 1)));
    if (!open(weekend)) weekend = at(sat.add(const Duration(days: 7)));
    // Same as tonight / tomorrow: still offered, as the weekend's label.
    out.add((label: 'This weekend', at: weekend));
    return out;
  }
}
