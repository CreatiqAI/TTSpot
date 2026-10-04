import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';

/// A post or moment the automatic photo check flagged (migration 0103):
/// hidden from everyone but its author and admins until an admin decides.
class FlaggedItem {
  const FlaggedItem({
    required this.kind,
    required this.id,
    required this.authorId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.photoUrls = const [],
    this.isVideo = false,
    this.title,
    this.caption,
    this.reason,
    this.hits = const [],
    required this.createdAt,
  });

  /// 'post' | 'moment'
  final String kind;
  final String id;
  final String authorId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final List<String> photoUrls;
  final bool isVideo;
  final String? title;
  final String? caption;

  /// "Flagged: sexual 0.93 (photo 2)"
  final String? reason;

  /// The categories over their threshold, worst first.
  final List<String> hits;
  final DateTime createdAt;

  bool get isPost => kind == 'post';

  factory FlaggedItem.fromMap(Map<String, dynamic> m) {
    final cats = (m['categories'] as Map?)?.cast<String, dynamic>();
    return FlaggedItem(
      kind: m['kind'] as String? ?? 'post',
      id: m['id'] as String,
      authorId: m['author_id'] as String,
      username: m['username'] as String? ?? '',
      displayName: m['display_name'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      photoUrls: ((m['photo_urls'] as List?) ?? const []).whereType<String>().toList(),
      isVideo: m['is_video'] as bool? ?? false,
      title: m['title'] as String?,
      caption: m['caption'] as String?,
      reason: m['reason'] as String?,
      hits: ((cats?['hits'] as List?) ?? const []).whereType<String>().toList(),
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }
}

/// Admin · Queues → Flagged posts and moments, newest flag first.
final adminFlaggedProvider = FutureProvider<List<FlaggedItem>>((ref) async {
  ref.watch(currentUserIdProvider);
  final rows = await ref.read(supabaseProvider).rpc('admin_moderation_queue', params: {'p_limit': 100}) as List;
  return [for (final r in rows) FlaggedItem.fromMap((r as Map).cast<String, dynamic>())];
});

class AdminModerationActions {
  AdminModerationActions(this._ref);
  final Ref _ref;

  /// Approve (shown to everyone again) or remove (stays hidden, kept for the
  /// record). Returns the new state, or null when it was deleted meanwhile.
  Future<String?> decide(FlaggedItem item, {required bool approve}) async {
    final v = await _ref.read(supabaseProvider).rpc('admin_moderate', params: {'p_kind': item.kind, 'p_id': item.id, 'p_approve': approve});
    _ref.invalidate(adminFlaggedProvider);
    return v as String?;
  }
}

final adminModerationActionsProvider = Provider<AdminModerationActions>((ref) => AdminModerationActions(ref));
