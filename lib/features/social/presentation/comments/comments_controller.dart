import 'package:flutter/widgets.dart';

import '../../domain/comment_thread.dart';

/// What the comment list and the comment box share on a post page: the
/// text being typed, who it replies to, which threads are unfolded and
/// which comment a notification pointed at.
class CommentsController extends ChangeNotifier {
  CommentsController({String? highlightId}) : _highlight = highlightId;

  final text = TextEditingController();
  final focus = FocusNode();

  CommentItem? _replyTo;
  String _prefill = '';
  final _open = <String>{};
  String? _highlight;

  /// The comment tapped Reply on (null: a new top-level comment).
  CommentItem? get replyTo => _replyTo;

  /// Opened from a notification about this comment: scroll to it, light it up.
  String? get highlightId => _highlight;

  bool isOpen(String threadId) => _open.contains(threadId);

  /// Reply to [c]: the box gets "@handle " and the keyboard comes up.
  void reply(CommentItem c, {String? me}) {
    final prefill = replyPrefill(c, me: me);
    final current = text.text;
    if (current.trim().isEmpty || current == _prefill) {
      _set(prefill);
    } else if (prefill.isNotEmpty && !current.startsWith(prefill)) {
      _set('$prefill${current.startsWith(_prefill) ? current.substring(_prefill.length) : current}');
    }
    _replyTo = c;
    _prefill = prefill;
    focus.requestFocus();
    notifyListeners();
  }

  /// Back to a new top-level comment; an untouched "@handle " goes too.
  void cancelReply() {
    if (_replyTo == null) return;
    if (text.text == _prefill) text.clear();
    _replyTo = null;
    _prefill = '';
    notifyListeners();
  }

  /// The comment bubble on the post: a fresh comment, not a reply.
  void startComment() {
    cancelReply();
    focus.requestFocus();
  }

  /// Posted: empty box, and the thread it went into stays unfolded.
  void sent() {
    final r = _replyTo;
    if (r != null) _open.add(r.threadId);
    text.clear();
    _replyTo = null;
    _prefill = '';
    notifyListeners();
  }

  void toggle(String threadId) {
    if (!_open.remove(threadId)) _open.add(threadId);
    notifyListeners();
  }

  void open(String threadId) {
    if (_open.add(threadId)) notifyListeners();
  }

  void clearHighlight() {
    if (_highlight == null) return;
    _highlight = null;
    notifyListeners();
  }

  void _set(String t) => text.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}
