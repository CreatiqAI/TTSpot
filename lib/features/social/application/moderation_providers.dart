import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';

// The automatic photo check (migration 0103, Edge Function moderate-content)
// as the author sees it. A flagged post or moment is hidden from everyone but
// me and the admins until the team decides; a removed one stays hidden.

enum ModerationState {
  pending,
  ok,
  flagged,
  removed;

  static ModerationState fromDb(String? v) => ModerationState.values.firstWhere((s) => s.name == v, orElse: () => ModerationState.ok);

  /// Others can't see it.
  bool get hidden => this == flagged || this == removed;
}

/// My posts the check has hidden: post id → flagged / removed. Small: most
/// members have none.
final myHiddenPostsProvider = FutureProvider<Map<String, ModerationState>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const {};
  final rows = await ref
      .watch(supabaseProvider)
      .from('posts')
      .select('id, moderation')
      .eq('author_id', me)
      .inFilter('moderation', const ['flagged', 'removed'])
      .limit(100);
  return {for (final r in rows) r['id'] as String: ModerationState.fromDb(r['moderation'] as String?)};
});
