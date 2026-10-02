import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/domain/profile.dart';
import '../../social/domain/chat.dart';

/// Nicknames (备注): the private names I gave other members, target id ->
/// nickname. Only I see them; they replace the person's name in chats,
/// friends, profiles and the push titles of their messages.
const kNicknameMaxLength = 40;

/// The name to show for someone: my nickname for them, else their display
/// name, else their @handle, else [fallback]. Blank values count as missing.
String resolveDisplayName({String? nickname, String? displayName, String? username, String fallback = 'Member'}) {
  final n = nickname?.trim() ?? '';
  if (n.isNotEmpty) return n;
  final d = displayName?.trim() ?? '';
  if (d.isNotEmpty) return d;
  final u = username?.trim() ?? '';
  if (u.isNotEmpty) return '@$u';
  return fallback;
}

/// [resolveDisplayName] for a profile, with my nicknames.
String displayNameFor(Profile? p, Map<String, String> nicknames, {String fallback = 'Member'}) => p == null
    ? fallback
    : resolveDisplayName(nickname: nicknames[p.id], displayName: p.displayName, username: p.username, fallback: fallback);

/// A chat's title: the nickname of the other person in a one-to-one chat,
/// else the chat's own title (meet name, club / partner name, their name).
String conversationTitle(Conversation c, Map<String, String> nicknames) {
  final other = c.other;
  if (c.isMeet || c.showEntity || other == null) return c.title;
  final n = nicknames[other.id]?.trim() ?? '';
  return n.isNotEmpty ? n : c.title;
}

class ContactNicknames extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    // Re-read after sign-in / token refresh, like points: a cold start with an
    // expired token would otherwise keep an empty map until the next launch.
    ref.watch(authStateProvider);
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const {};
    final rows = await ref.watch(supabaseProvider).rpc('my_contact_nicknames') as List<dynamic>;
    return {
      for (final r in rows.cast<Map<String, dynamic>>())
        if ((r['nickname'] as String?)?.trim().isNotEmpty ?? false) r['target_id'] as String: (r['nickname'] as String).trim(),
    };
  }

  /// Saves (or with null / blank, removes) my nickname for [targetId]. The
  /// change shows at once and is rolled back if saving fails.
  Future<void> setNickname(String targetId, String? nickname) async {
    final clean = nickname?.trim() ?? '';
    final before = state.value ?? const <String, String>{};
    final next = {...before};
    if (clean.isEmpty) {
      next.remove(targetId);
    } else {
      next[targetId] = clean.length > kNicknameMaxLength ? clean.substring(0, kNicknameMaxLength) : clean;
    }
    state = AsyncData(next);
    try {
      await ref.read(supabaseProvider).rpc('set_contact_nickname', params: {'p_target': targetId, 'p_nickname': clean.isEmpty ? null : next[targetId]});
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }
}

final contactNicknamesProvider = AsyncNotifierProvider<ContactNicknames, Map<String, String>>(ContactNicknames.new);

/// My nicknames, empty while loading or when offline (names fall back to the
/// real ones, never an error).
final nicknamesProvider = Provider<Map<String, String>>((ref) => ref.watch(contactNicknamesProvider).value ?? const {});

/// `ref.displayNameFor(profile)` in build methods.
extension DisplayNameRef on WidgetRef {
  String displayNameFor(Profile? p, {String fallback = 'Member'}) => resolveDisplayName(
        nickname: p == null ? null : watch(nicknamesProvider)[p.id],
        displayName: p?.displayName,
        username: p?.username,
        fallback: fallback,
      );

  /// My nickname for [userId], or null.
  String? nicknameFor(String? userId) => userId == null ? null : watch(nicknamesProvider)[userId];
}
