/// A tappable card TiTi showed: a meet, spot, club or car. The server builds
/// it from a real row, so the title, photo and route are always real.
class TitiCard {
  const TitiCard({required this.kind, required this.id, required this.title, required this.subtitle, required this.route, this.image});

  /// meet | spot | club | car
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

/// One piece of a message: a bubble of text, or a card.
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

/// A question (mine) or one of TiTi's answers, split into bubbles and cards.
class TitiMessage {
  const TitiMessage({required this.key, required this.mine, required this.parts, this.chips = const [], this.error, this.question});

  /// Stable within a session: the row id, or a local id while streaming.
  final String key;
  final bool mine;
  final List<TitiPart> parts;

  /// Follow-ups TiTi suggested (shown under the latest answer only).
  final List<String> chips;

  /// Set when this answer failed; the screen shows it with Retry.
  final String? error;

  /// For an answer: the question it answers (what Retry sends again).
  final String? question;

  String get text => parts.whereType<TitiTextPart>().map((p) => p.text).join('\n');
  bool get isEmpty => parts.every((p) => p is TitiTextPart && p.text.trim().isEmpty);

  TitiMessage copyWith({List<TitiPart>? parts, List<String>? chips, String? error, bool clearError = false}) => TitiMessage(
        key: key,
        mine: mine,
        parts: parts ?? this.parts,
        chips: chips ?? this.chips,
        error: clearError ? null : error ?? this.error,
        question: question,
      );

  /// A row of `titi_messages`. An answer's content marks bubbles with a line
  /// "---" and cards with [[meet:<id>]]; `parts.cards` holds the card data.
  static TitiMessage fromRow(Map<String, dynamic> row, {String? question}) {
    final mine = row['role'] == 'user';
    final content = row['content'] as String? ?? '';
    if (mine) return TitiMessage(key: row['id'] as String, mine: true, parts: [TitiTextPart(content)]);
    final meta = row['parts'] is Map ? row['parts'] as Map : const {};
    final cards = meta['cards'] is Map ? meta['cards'] as Map : const {};
    final chips = meta['chips'] is List ? [for (final c in meta['chips'] as List) if (c is String) c] : const <String>[];
    return TitiMessage(key: row['id'] as String, mine: false, parts: splitAnswer(content, cards), chips: chips, question: question);
  }

  static final _marker = RegExp(r'^[ \t]*-{3,}[ \t]*$|\[\[(meet|spot|club|car):([0-9a-fA-F-]{36})\]\]', multiLine: true);

  /// Stored answer text → bubbles and cards (the same rules the server streams by).
  static List<TitiPart> splitAnswer(String content, Map cards) {
    final parts = <TitiPart>[];
    void addText(String s) {
      if (s.trim().isNotEmpty) parts.add(TitiTextPart(s.trim()));
    }

    var at = 0;
    for (final m in _marker.allMatches(content)) {
      addText(content.substring(at, m.start));
      at = m.end;
      if (m.group(1) != null) {
        final card = TitiCard.fromMap(cards['${m.group(1)}:${m.group(2)!.toLowerCase()}']);
        if (card != null) parts.add(TitiCardPart(card));
      }
    }
    addText(content.substring(at));
    return parts;
  }
}
