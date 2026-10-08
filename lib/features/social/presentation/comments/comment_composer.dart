import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/profile.dart';
import '../../application/comment_providers.dart';
import '../../domain/comment_thread.dart';
import 'comments_controller.dart';

/// The comment box pinned under a post: @ suggestions while typing a
/// handle (friends first), "Replying to @handle" with a cancel, then my
/// avatar, the field and Post.
class CommentComposer extends ConsumerStatefulWidget {
  const CommentComposer({super.key, required this.postId, required this.controller});
  final String postId;
  final CommentsController controller;

  @override
  ConsumerState<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends ConsumerState<CommentComposer> {
  bool _busy = false;

  /// What follows the "@" being typed (null: no suggestions).
  String? _query;
  Timer? _debounce;

  CommentsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _c.text.addListener(_typed);
    _c.focus.addListener(_typed);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.removeListener(_changed);
    _c.text.removeListener(_typed);
    _c.focus.removeListener(_typed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _typed() {
    final v = _c.text.value;
    final sel = v.selection;
    final hit = _c.focus.hasFocus && sel.isValid && sel.isCollapsed ? mentionAt(v.text, sel.baseOffset) : null;
    _debounce?.cancel();
    if (hit == null) {
      if (_query != null) setState(() => _query = null);
      return;
    }
    final String q = hit.query;
    if (q == _query) return;
    // Right after the "@" the friends show at once; typing waits a beat.
    if (q.isEmpty) {
      setState(() => _query = q);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _query = q);
    });
  }

  void _pick(Profile p) {
    final handle = p.username;
    if (handle == null) return;
    final v = _c.text.value;
    final cursor = v.selection.baseOffset;
    final hit = mentionAt(v.text, cursor);
    if (hit == null) return;
    final r = insertMention(v.text, hit.start, cursor, handle);
    _c.text.value = TextEditingValue(text: r.text, selection: TextSelection.collapsed(offset: r.cursor));
    setState(() => _query = null);
  }

  Future<void> _send() async {
    final text = _c.text.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(commentActionsProvider).add(widget.postId, text, replyTo: _c.replyTo?.id);
      _c.sent();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentProfileProvider).value;
    final replyTo = _c.replyTo;
    final query = _query;
    // Taps on Post, the @ suggestions or the reply strip count as inside the
    // field, so the app's tap-outside keyboard close leaves them alone.
    return TextFieldTapRegion(child: Container(
      decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (query != null) MentionSuggestions(query: query, onPick: _pick),
            if (replyTo != null)
              Container(
                color: AppColors.surfaceRaised,
                padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to @${replyTo.handle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel reply',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(AppIcons.x, size: 16, color: AppColors.textSecondary),
                      onPressed: _c.cancelReply,
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  UserAvatar(url: me?.avatarUrl, name: me?.displayName ?? me?.username, seed: me?.id, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _c.text,
                      focusNode: _c.focus,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      // Return posts (same as Post) and closes the keyboard; long text still wraps.
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        if (!_busy) _send();
                      },
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: replyTo == null ? 'Add a comment…' : 'Add a reply…',
                        counterText: '',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _send,
                    child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Post'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

/// Who an "@" can mean, in a short scrolling list above the comment box.
class MentionSuggestions extends ConsumerStatefulWidget {
  const MentionSuggestions({super.key, required this.query, required this.onPick});
  final String query;
  final ValueChanged<Profile> onPick;

  @override
  ConsumerState<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends ConsumerState<MentionSuggestions> {
  /// The last list shown, kept while the next one loads so it doesn't flicker.
  List<Profile> _last = const [];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mentionSuggestionsProvider(widget.query));
    final fresh = async.value;
    if (fresh != null) _last = fresh;
    final people = fresh ?? _last;
    if (people.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.divider))),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final p in people)
            InkWell(
              onTap: () => widget.onPick(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                child: Row(
                  children: [
                    UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, seed: p.id, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (p.displayName ?? '').trim().isEmpty ? '@${p.username}' : p.displayName!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                          if ((p.displayName ?? '').trim().isNotEmpty)
                            Text('@${p.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
