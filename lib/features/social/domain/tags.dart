import 'package:flutter/services.dart' show TextEditingValue, TextSelection;

/// #tags and @mentions in post text.
///
/// [parseTags] follows the database's parse_tags (migration 0101), which
/// fills posts.tags on the server, so the app and the server agree on what a
/// tag is: a # at the start or after anything but a letter, digit, _ or &,
/// then 2 to 30 letters, digits or underscores. Lowercase, first 10, no
/// repeats.

const kMaxTagsPerPost = 10;
const kTagMinLength = 2;
const kTagMaxLength = 30;

final _tagRe = RegExp(r'(^|[^\p{L}\p{N}_&])#([\p{L}\p{N}_]+)', unicode: true);

/// Usernames are 3 to 20 of a-z, 0-9 and _ (profiles.username_format).
final _mentionRe = RegExp(r'(^|[^\p{L}\p{N}_@])@([A-Za-z0-9_]{3,20})(?![\p{L}\p{N}_])', unicode: true);
final _wordRe = RegExp(r'[\p{L}\p{N}_]', unicode: true);
final _handleRe = RegExp(r'[A-Za-z0-9_]');

bool _validTag(String word) => word.length >= kTagMinLength && word.length <= kTagMaxLength;

/// The tags of a post's text, as the server stores them.
List<String> parseTags(String? text) {
  final out = <String>[];
  for (final m in _tagRe.allMatches(text ?? '')) {
    final word = m.group(2)!;
    if (!_validTag(word)) continue;
    final tag = word.toLowerCase();
    if (out.contains(tag)) continue;
    out.add(tag);
    if (out.length == kMaxTagsPerPost) break;
  }
  return out;
}

/// What someone typed or tapped ("#Myvi", "myvi ") as a tag, or null.
String? normaliseTag(String? raw) {
  final t = (raw ?? '').trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
  if (!_validTag(t) || t.split('').any((c) => !_wordRe.hasMatch(c))) return null;
  return t;
}

/// A car make or model as a tag: "Civic Type R" -> civictyper.
String? tagFromName(String? name) {
  final t = (name ?? '').toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}_]+', unicode: true), '');
  return _validTag(t) ? t : null;
}

enum CaptionTokenKind { text, tag, mention }

/// A run of post text: plain, a #tag or an @mention. [text] is as written
/// ("#Myvi"); [value] is the tag or username, lowercase ("myvi").
class CaptionToken {
  const CaptionToken(this.kind, this.text, [this.value = '']);
  final CaptionTokenKind kind;
  final String text;
  final String value;

  @override
  bool operator ==(Object other) => other is CaptionToken && other.kind == kind && other.text == text && other.value == value;

  @override
  int get hashCode => Object.hash(kind, text, value);

  @override
  String toString() => '${kind.name}($text)';
}

/// [text] cut into plain runs, #tags and @mentions, in order. Joining every
/// token's [CaptionToken.text] gives [text] back.
List<CaptionToken> captionTokens(String text) {
  final links = <(int, int, CaptionToken)>[];
  for (final m in _tagRe.allMatches(text)) {
    final word = m.group(2)!;
    if (!_validTag(word)) continue;
    final start = m.start + m.group(1)!.length;
    links.add((start, m.end, CaptionToken(CaptionTokenKind.tag, text.substring(start, m.end), word.toLowerCase())));
  }
  for (final m in _mentionRe.allMatches(text)) {
    final start = m.start + m.group(1)!.length;
    links.add((start, m.end, CaptionToken(CaptionTokenKind.mention, text.substring(start, m.end), m.group(2)!.toLowerCase())));
  }
  links.sort((a, b) => a.$1.compareTo(b.$1));
  final out = <CaptionToken>[];
  var at = 0;
  for (final (start, end, token) in links) {
    if (start < at) continue; // overlaps the one before
    if (start > at) out.add(CaptionToken(CaptionTokenKind.text, text.substring(at, start)));
    out.add(token);
    at = end;
  }
  if (at < text.length) out.add(CaptionToken(CaptionTokenKind.text, text.substring(at)));
  return out;
}

/// The #word or @word the caret is in while typing: [query] is what follows
/// the # or @ up to the caret ("my" in "#my|"), [start] is where the # or @
/// is and [end] where the word ends (it can run on past the caret).
class CaptionQuery {
  const CaptionQuery({required this.kind, required this.query, required this.start, required this.end});
  final CaptionTokenKind kind;
  final String query;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) => other is CaptionQuery && other.kind == kind && other.query == query && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(kind, query, start, end);
}

/// The word being typed, when it is a #tag or an @mention, else null.
CaptionQuery? activeCaptionQuery(TextEditingValue value) {
  final sel = value.selection;
  final text = value.text;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final caret = sel.baseOffset;
  if (caret < 1 || caret > text.length) return null;
  var i = caret;
  while (i > 0 && _wordRe.hasMatch(text[i - 1])) {
    i--;
  }
  if (i == 0) return null;
  final mark = text[i - 1];
  if (mark != '#' && mark != '@') return null;
  final before = i >= 2 ? text[i - 2] : null;
  if (before != null && (_wordRe.hasMatch(before) || before == '&' || before == '#' || before == '@')) return null;
  var end = caret;
  while (end < text.length && _wordRe.hasMatch(text[end])) {
    end++;
  }
  final query = text.substring(i, caret);
  if (mark == '#') {
    if (query.length > kTagMaxLength) return null;
    return CaptionQuery(kind: CaptionTokenKind.tag, query: query.toLowerCase(), start: i - 1, end: end);
  }
  if (query.length > 20 || query.split('').any((c) => !_handleRe.hasMatch(c))) return null;
  return CaptionQuery(kind: CaptionTokenKind.mention, query: query.toLowerCase(), start: i - 1, end: end);
}

/// [value] with the word [q] replaced by [replacement] ("#myvi" or
/// "@keith_ek9") and a space after it, the caret after the space.
TextEditingValue completeCaptionQuery(TextEditingValue value, CaptionQuery q, String replacement) {
  final text = value.text;
  final end = q.end.clamp(q.start, text.length);
  final rest = text.substring(end);
  final spaced = rest.startsWith(' ') ? rest : ' $rest';
  final next = '${text.substring(0, q.start)}$replacement$spaced';
  final caret = q.start + replacement.length + 1;
  return TextEditingValue(text: next, selection: TextSelection.collapsed(offset: caret));
}

/// A tag with how many posts carry it.
class TagCount {
  const TagCount({required this.tag, required this.posts});
  final String tag;
  final int posts;

  factory TagCount.fromMap(Map<String, dynamic> m) => TagCount(tag: m['tag'] as String, posts: (m['posts'] as num?)?.toInt() ?? 0);
}

/// "128 posts", "1 post".
String postCountLabel(int n) => n == 1 ? '1 post' : '${_grouped(n)} posts';

String _grouped(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// How one of my posts is doing. Only the author ever gets these
/// (my_post_stats, migration 0101).
class MyPostStats {
  const MyPostStats({required this.views, required this.saves, required this.likes, required this.comments, required this.shares});
  final int views;
  final int saves;
  final int likes;
  final int comments;
  final int shares;

  factory MyPostStats.fromMap(Map<String, dynamic> m) => MyPostStats(
        views: (m['views'] as num?)?.toInt() ?? 0,
        saves: (m['saves'] as num?)?.toInt() ?? 0,
        likes: (m['likes'] as num?)?.toInt() ?? 0,
        comments: (m['comments'] as num?)?.toInt() ?? 0,
        shares: (m['shares'] as num?)?.toInt() ?? 0,
      );

  /// "128 views · 12 saves · 3 shares"
  String get summary => [
        _count(views, 'view'),
        _count(saves, 'save'),
        _count(shares, 'share'),
      ].join(' · ');

  /// "1.2k" style for the small grid badge.
  String get viewsShort => compactCount(views);

  static String _count(int n, String noun) => '${_grouped(n)} $noun${n == 1 ? '' : 's'}';
}

/// 950, 1.2k, 12k, 1.5m.
String compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')}k';
  if (n < 1000000) return '${n ~/ 1000}k';
  return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')}m';
}
