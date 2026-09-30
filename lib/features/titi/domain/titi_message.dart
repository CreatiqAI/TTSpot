import 'package:flutter/foundation.dart';

/// A tappable card TiTi showed: a meet, spot, club, car, voucher (one I
/// claimed) or offer (a partner voucher to claim). The server builds it from a
/// real row, so the title, photo and route are always real.
class TitiCard {
  const TitiCard({required this.kind, required this.id, required this.title, required this.subtitle, required this.route, this.image});

  /// meet | spot | club | car | voucher | offer
  final String kind;
  final String id;
  final String title;
  final String subtitle;

  /// An https photo, a bundled asset path (`assets/...`), or null for the
  /// kind's own placeholder.
  final String? image;

  /// An in-app route, e.g. `/event/<id>`.
  final String route;

  String get key => '$kind:$id';

  static TitiCard? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'], id = raw['id'], route = raw['route'];
    if (kind is! String || id is! String || route is! String || !route.startsWith('/')) return null;
    return TitiCard(
      kind: kind,
      id: id,
      title: raw['title'] as String? ?? '',
      subtitle: raw['subtitle'] as String? ?? '',
      image: raw['image'] as String?,
      route: route,
    );
  }
}

/// Where an action card stands. TiTi only proposes; the member taps.
enum TitiActionStatus { open, done, dismissed }

/// A button TiTi put on screen: join a meet, save a spot, directions, TT here,
/// open a page or a box, claim a voucher. The app does it with its own code
/// when the member taps (see application/titi_actions.dart).
class TitiAction {
  const TitiAction({
    required this.kind,
    required this.id,
    required this.label,
    required this.title,
    this.detail = '',
    this.image,
    this.target,
    this.route,
    this.lat,
    this.lng,
    this.after,
    this.status = TitiActionStatus.open,
    this.resultRoute,
  });

  /// join_meet | leave_meet | save_spot | directions | tt_here | open_page | open_box | claim_voucher
  final String kind;

  /// A uuid from the server; titi_action_status() finds the card by it.
  final String id;

  /// The button's words ("Join", "Claim · 100 pts").
  final String label;
  final String title;
  final String detail;
  final String? image;

  /// The meet, spot or voucher it acts on.
  final String? target;

  /// Where the card leads (the meet's page, the page to open).
  final String? route;
  final double? lat;
  final double? lng;

  /// TiTi's line once it's done ("You're in. Want directions?").
  final String? after;
  final TitiActionStatus status;

  /// Where the card leads once done, e.g. a claimed voucher's QR.
  final String? resultRoute;

  /// Directions, TT here and opening a page can be tapped again and again;
  /// the rest are one-off.
  bool get repeatable => const {'directions', 'tt_here', 'open_page', 'open_box'}.contains(kind);

  TitiAction copyWith({TitiActionStatus? status, String? resultRoute}) => TitiAction(
        kind: kind,
        id: id,
        label: label,
        title: title,
        detail: detail,
        image: image,
        target: target,
        route: route,
        lat: lat,
        lng: lng,
        after: after,
        status: status ?? this.status,
        resultRoute: resultRoute ?? this.resultRoute,
      );

  static TitiAction? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'], id = raw['id'], label = raw['label'];
    if (kind is! String || id is! String || label is! String) return null;
    return TitiAction(
      kind: kind,
      id: id,
      label: label,
      title: raw['title'] as String? ?? '',
      detail: raw['detail'] as String? ?? '',
      image: raw['image'] as String?,
      target: raw['target'] as String?,
      route: raw['route'] as String?,
      lat: (raw['lat'] as num?)?.toDouble(),
      lng: (raw['lng'] as num?)?.toDouble(),
      after: raw['after'] as String?,
      status: switch (raw['status']) { 'done' => TitiActionStatus.done, 'dismissed' => TitiActionStatus.dismissed, _ => TitiActionStatus.open },
      resultRoute: raw['result_route'] as String?,
    );
  }
}

/// A photo in one of my questions: its path in the private titi-uploads
/// bucket (once uploaded), a signed URL (from history) and/or the picked
/// bytes (while sending, so it shows at once).
class TitiImage {
  const TitiImage({this.path, this.url, this.bytes});
  final String? path;
  final String? url;
  final Uint8List? bytes;

  TitiImage withPath(String p) => TitiImage(path: p, url: url, bytes: bytes);
}

/// One piece of a message: a bubble of text, a card or an action card.
sealed class TitiPart {
  const TitiPart();
}

class TitiTextPart extends TitiPart {
  const TitiTextPart(this.text);
  final String text;
}

class TitiCardPart extends TitiPart {
  const TitiCardPart(this.card);
  final TitiCard card;
}

class TitiActionPart extends TitiPart {
  const TitiActionPart(this.action);
  final TitiAction action;
}

/// A question (mine) or one of TiTi's answers, split into bubbles and cards.
class TitiMessage {
  const TitiMessage({required this.key, required this.mine, required this.parts, this.chips = const [], this.error, this.images = const [], this.live, this.at});

  /// Stable within a session: the row id, or a local id while streaming.
  final String key;
  final bool mine;
  final List<TitiPart> parts;

  /// Follow-ups TiTi suggested (shown under the latest answer only).
  final List<String> chips;

  /// Set when this answer failed; the screen shows it with Retry.
  final String? error;

  /// My photos (questions only).
  final List<TitiImage> images;

  /// The answer as it streams in (null for anything loaded from history).
  /// It stays attached after the stream ends, until its words have typed out.
  final TitiLive? live;

  /// When it was sent (local time): the row's created_at, or now for a
  /// question just asked. An answer gets its time once it's done.
  final DateTime? at;

  String get text => parts.whereType<TitiTextPart>().map((p) => p.text).join('\n');
  bool get isEmpty => images.isEmpty && parts.every((p) => p is TitiTextPart && p.text.trim().isEmpty);

  TitiMessage copyWith({List<TitiPart>? parts, List<String>? chips, String? error, bool clearError = false, List<TitiImage>? images, DateTime? at}) => TitiMessage(
        key: key,
        mine: mine,
        parts: parts ?? this.parts,
        chips: chips ?? this.chips,
        error: clearError ? null : error ?? this.error,
        images: images ?? this.images,
        live: live,
        at: at ?? this.at,
      );

  /// A row of `titi_messages`. An answer's content marks bubbles with a line
  /// "---", cards with [[meet:<id>]] and action cards with [[act:<id>]];
  /// `parts` holds their data. [urls]: signed URLs of my photos, by path.
  static TitiMessage fromRow(Map<String, dynamic> row, {Map<String, String> urls = const {}}) {
    final mine = row['role'] == 'user';
    final content = row['content'] as String? ?? '';
    final meta = row['parts'] is Map ? row['parts'] as Map : const {};
    final at = DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
    if (mine) {
      final paths = meta['images'] is List ? [for (final p in meta['images'] as List) if (p is String) p] : const <String>[];
      return TitiMessage(
        key: row['id'] as String,
        mine: true,
        parts: content.trim().isEmpty ? const [] : [TitiTextPart(content)],
        images: [for (final p in paths) TitiImage(path: p, url: urls[p])],
        at: at,
      );
    }
    final cards = meta['cards'] is Map ? meta['cards'] as Map : const {};
    final actions = meta['actions'] is Map ? meta['actions'] as Map : const {};
    final chips = meta['chips'] is List ? [for (final c in meta['chips'] as List) if (c is String) c] : const <String>[];
    return TitiMessage(key: row['id'] as String, mine: false, parts: splitAnswer(content, cards, actions), chips: chips, at: at);
  }

  static final _marker = RegExp(r'^[ \t]*-{3,}[ \t]*$|\[\[(meet|spot|club|car|voucher|offer|act):([0-9a-fA-F-]{36})\]\]', multiLine: true);

  /// Stored answer text → bubbles, cards and action cards (the same rules the
  /// server streams by).
  static List<TitiPart> splitAnswer(String content, Map cards, [Map actions = const {}]) {
    final parts = <TitiPart>[];
    void addText(String s) {
      if (s.trim().isNotEmpty) parts.add(TitiTextPart(s.trim()));
    }

    var at = 0;
    for (final m in _marker.allMatches(content)) {
      addText(content.substring(at, m.start));
      at = m.end;
      final kind = m.group(1);
      if (kind == null) continue;
      final id = m.group(2)!.toLowerCase();
      if (kind == 'act') {
        final a = TitiAction.fromMap(actions[id]);
        if (a != null) parts.add(TitiActionPart(a));
      } else {
        final card = TitiCard.fromMap(cards['$kind:$id']);
        if (card != null) parts.add(TitiCardPart(card));
      }
    }
    addText(content.substring(at));
    return parts;
  }
}

/// One chat with TiTi.
class TitiSession {
  const TitiSession({required this.id, required this.title, required this.updatedAt});
  final String id;

  /// Null until the first answer names it.
  final String? title;
  final DateTime updatedAt;

  factory TitiSession.fromMap(Map<String, dynamic> m) => TitiSession(
        id: m['id'] as String,
        title: (m['title'] as String?)?.trim().isEmpty ?? true ? null : m['title'] as String,
        updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
      );
}

/// The answer being written. The stream's words land here instead of in the
/// Riverpod state, so a new word redraws only the answer's own widget, which
/// types them out at an even pace (presentation/titi_answer.dart).
class TitiLive extends ChangeNotifier {
  /// Finished pieces: bubbles, cards, action cards.
  final _parts = <TitiPart>[];

  /// The bubble still growing.
  var _text = '';

  /// A tool is running ("Checking meets near you…"), and which (TiTi's pose).
  String? status;
  String? tool;

  /// Nothing new to show since the start or the last status: the thinking
  /// row is up.
  var waiting = true;

  /// The stream has ended (answer, stop or error).
  var done = false;

  List<String> chips = const [];
  String? error;

  /// The typewriter's position, in units (see [unitsOf]). Kept here so a
  /// screen that is closed and reopened mid-answer carries on where it was.
  double shown = 0;

  /// Every unit has been shown after [done]: the answer is plain from now on.
  var revealed = false;

  List<TitiPart> get parts => [..._parts, if (_text.trim().isNotEmpty) TitiTextPart(_text)];
  bool get isEmpty => _parts.isEmpty && _text.trim().isEmpty;

  /// Letters count one each; a card counts [blockUnits], a short beat before
  /// it slides in.
  static const blockUnits = 6.0;
  static double unitsOf(TitiPart p) => p is TitiTextPart ? p.text.length.toDouble() : blockUnits;
  double get total => parts.fold(0, (s, p) => s + unitsOf(p));

  void addText(String s) {
    _text += s;
    if (s.trim().isNotEmpty) {
      waiting = false;
      status = null;
      tool = null;
    }
    notifyListeners();
  }

  /// Starts a new bubble.
  void closeBubble() {
    if (_text.trim().isNotEmpty) _parts.add(TitiTextPart(_text));
    _text = '';
  }

  void addPart(TitiPart p) {
    closeBubble();
    _parts.add(p);
    waiting = false;
    status = null;
    tool = null;
    notifyListeners();
  }

  void setStatus(String text, String? tool) {
    closeBubble();
    status = text;
    this.tool = tool;
    waiting = true;
    notifyListeners();
  }

  /// An action card changed (done or dismissed).
  void replaceAction(TitiAction a) {
    for (var i = 0; i < _parts.length; i++) {
      final p = _parts[i];
      if (p is TitiActionPart && p.action.id == a.id) _parts[i] = TitiActionPart(a);
    }
    notifyListeners();
  }

  void finish() {
    closeBubble();
    done = true;
    waiting = false;
    status = null;
    tool = null;
    notifyListeners();
  }

  void markRevealed() {
    if (revealed) return;
    revealed = true;
    notifyListeners();
  }
}
