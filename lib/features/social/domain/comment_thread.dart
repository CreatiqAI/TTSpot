import '../../auth/domain/profile.dart';

/// One comment on a post, with where it sits in its thread and its likes
/// (migration 20261005000102). Replies are one level deep, like Instagram:
/// [parentId] is always a top-level comment; [replyToId] is the comment the
/// writer tapped Reply on (that can be another reply).
class CommentItem {
  const CommentItem({
    required this.id,
    required this.postId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.parentId,
    this.replyToId,
    this.author,
    this.likeCount = 0,
    this.likedByMe = false,
  });

  final String id;
  final String postId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final String? parentId;
  final String? replyToId;
  final Profile? author;
  final int likeCount;
  final bool likedByMe;

  bool get isReply => parentId != null;

  /// The top-level comment this sits under (itself when it is one).
  String get threadId => parentId ?? id;

  String get handle => author?.username ?? 'someone';

  CommentItem copyWith({int? likeCount, bool? likedByMe}) => CommentItem(
        id: id,
        postId: postId,
        userId: userId,
        body: body,
        createdAt: createdAt,
        parentId: parentId,
        replyToId: replyToId,
        author: author,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
      );

  /// A post_comments row with `profiles(...)` and `post_comment_likes(count)`.
  factory CommentItem.fromMap(Map<String, dynamic> m, {bool likedByMe = false}) {
    final likes = m['post_comment_likes'];
    var count = 0;
    if (likes is List && likes.isNotEmpty && likes.first is Map) {
      count = ((likes.first as Map)['count'] as num?)?.toInt() ?? 0;
    }
    final author = m['profiles'];
    return CommentItem(
      id: m['id'] as String,
      postId: m['post_id'] as String,
      userId: m['user_id'] as String,
      body: m['body'] as String,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      parentId: m['parent_id'] as String?,
      replyToId: m['reply_to_id'] as String?,
      author: author is Map<String, dynamic> ? Profile.fromMap(author) : null,
      likeCount: count,
      likedByMe: likedByMe,
    );
  }
}

/// A top-level comment and its replies, both oldest first.
class CommentThread {
  const CommentThread(this.top, this.replies);
  final CommentItem top;
  final List<CommentItem> replies;

  /// Replies stay folded behind "View N replies" past this many.
  static const shownOpen = 2;

  bool get folds => replies.length > shownOpen;
}

/// Threads in the order they were written. A reply whose parent isn't in
/// [all] (gone, or written by someone I blocked) goes with it.
List<CommentThread> buildThreads(Iterable<CommentItem> all) {
  final sorted = all.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final replies = <String, List<CommentItem>>{};
  final tops = <CommentItem>[];
  for (final c in sorted) {
    final parent = c.parentId;
    if (parent == null) {
      tops.add(c);
    } else {
      (replies[parent] ??= []).add(c);
    }
  }
  return [for (final t in tops) CommentThread(t, replies[t.id] ?? const [])];
}

/// How many comments go when [c] is deleted: its replies go with it.
int repliesUnder(String commentId, Iterable<CommentItem> all) => all.where((c) => c.parentId == commentId).length;

// ------------------------------------------------------------- mentions ---

final _typing = RegExp(r'(?:^|[^A-Za-z0-9_@./])@([A-Za-z0-9_]{0,20})$');

/// The @handle being typed just before [cursor]: where its "@" is and what
/// follows it so far ("" right after the "@"). Null when the cursor isn't
/// in one (an email address or a URL doesn't count).
({int start, String query})? mentionAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final m = _typing.firstMatch(text.substring(0, cursor));
  if (m == null) return null;
  final query = m.group(1)!;
  return (start: cursor - query.length - 1, query: query);
}

/// [text] with the @handle typed at [start]..[cursor] swapped for
/// "@username ", and where the cursor goes after it.
({String text, int cursor}) insertMention(String text, int start, int cursor, String username) {
  final rest = text.substring(cursor);
  final insert = '@$username ';
  // Don't double the space when one follows already.
  final tail = rest.startsWith(' ') ? rest.substring(1) : rest;
  return (text: '${text.substring(0, start)}$insert$tail', cursor: start + insert.length);
}

/// What the box starts with when replying to [c]: "@handle ", or nothing
/// when it's my own comment.
String replyPrefill(CommentItem c, {String? me}) {
  final handle = c.author?.username;
  if (handle == null || handle.isEmpty || c.userId == me) return '';
  return '@$handle ';
}
