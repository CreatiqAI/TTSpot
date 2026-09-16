import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/profile.dart';
import '../../social/application/chat_providers.dart';
import '../../social/application/social_providers.dart';
import '../application/friends_providers.dart';
import '../domain/friend.dart';

/// Friends: requests waiting, your friends, people you may know, and search.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _query = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final requests = ref.watch(friendRequestsProvider).value ?? const <FriendRequest>[];
    final friends = ref.watch(friendsProvider);
    final friendIds = ref.watch(friendIdsProvider);
    final outgoing = ref.watch(outgoingRequestIdsProvider).value ?? const <String>{};
    final searching = _q.trim().length >= 2;
    final results = searching ? ref.watch(profileSearchProvider(_q.trim())) : const AsyncValue<List<Profile>>.data([]);
    final suggestions = ref.watch(friendSuggestionsProvider).value ?? const <FriendSuggestion>[];
    final actions = ref.read(friendActionsProvider);

    Widget addButton(Profile p) => FilledButton(
          onPressed: () => _run(() async {
            final s = await actions.add(p.id);
            _snack(s == FriendshipStatus.friends ? 'You\'re now friends.' : 'Request sent.');
          }),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 16)),
          child: const Text('Add'),
        );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Friends'),
        actions: [
          IconButton(tooltip: 'My QR', icon: const Icon(AppIcons.qrCode), onPressed: () => context.push(Routes.myQr)),
          IconButton(tooltip: 'Scan', icon: const Icon(AppIcons.scan), onPressed: () => context.push(Routes.scan)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(friendsProvider);
          ref.invalidate(friendRequestsProvider);
          ref.invalidate(friendSuggestionsProvider);
          await ref.read(friendsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _query,
                onChanged: (v) => setState(() => _q = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Add by username or name',
                  prefixIcon: const Icon(AppIcons.userPlus),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(AppIcons.x),
                          onPressed: () {
                            _query.clear();
                            setState(() => _q = '');
                          },
                        ),
                ),
              ),
            ),
            if (searching)
              results.when(
                loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
                data: (list) {
                  final people = list.where((p) => p.id != me).toList();
                  if (people.isEmpty) {
                    return Padding(padding: EdgeInsets.all(24), child: Text('Nobody by that name yet. Tell them to join TT Spot.', style: TextStyle(color: AppColors.textSecondary)));
                  }
                  return Column(
                    children: [
                      const _Section('PEOPLE'),
                      for (final p in people)
                        _PersonTile(
                          profile: p,
                          trailing: friendIds.contains(p.id)
                              ? const _Chip('Friends')
                              : outgoing.contains(p.id)
                                  ? const _Chip('Requested')
                                  : requests.any((r) => r.from.id == p.id)
                                      ? FilledButton(
                                          onPressed: () => _run(() => actions.accept(p.id)),
                                          style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 16)),
                                          child: const Text('Accept'),
                                        )
                                      : addButton(p),
                        ),
                    ],
                  );
                },
              )
            else ...[
              if (requests.isNotEmpty) ...[
                _Section('REQUESTS · ${requests.length}'),
                for (final r in requests)
                  _PersonTile(
                    profile: r.from,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: () => _run(() => actions.accept(r.from.id)),
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                          child: const Text('Accept'),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Decline',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(AppIcons.x),
                          onPressed: () => _run(() => actions.decline(r.from.id)),
                        ),
                      ],
                    ),
                  ),
              ],
              friends.when(
                loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                        child: EmptyState(
                          emoji: '🫂',
                          title: 'No friends yet',
                          subtitle: 'Friends see each other on the map and get pinged for TT now. Start with the people below.',
                        ),
                      )
                    : Column(
                        children: [
                          _Section('FRIENDS · ${list.length}'),
                          for (final p in list)
                            _PersonTile(
                              profile: p,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Message',
                                    icon: const Icon(AppIcons.chatCircle),
                                    onPressed: () => _run(() async {
                                      final conv = await ref.read(chatActionsProvider).openDm(p.id);
                                      if (context.mounted) context.push(Routes.chat(conv));
                                    }),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'remove') _run(() => actions.remove(p.id));
                                    },
                                    itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove friend'))],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              if (suggestions.isNotEmpty) ...[
                const _Section('PEOPLE YOU MAY KNOW'),
                for (final sgg in suggestions)
                  _PersonTile(
                    profile: sgg.profile,
                    subtitle: sgg.reason,
                    trailing: outgoing.contains(sgg.profile.id)
                        ? const _Chip('Requested')
                        : requests.any((r) => r.from.id == sgg.profile.id)
                            ? FilledButton(
                                onPressed: () => _run(() => actions.accept(sgg.profile.id)),
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 16)),
                                child: const Text('Accept'),
                              )
                            : addButton(sgg.profile),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.profile, required this.trailing, this.subtitle});
  final Profile profile;
  final Widget trailing;
  /// Replaces the @handle line (e.g. "2 mutual friends").
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return ListTile(
      onTap: () => context.push(Routes.profile(p.id)),
      leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, size: 44),
      title: Text(p.displayName ?? '@${p.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle ?? '@${p.username ?? ''}', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
      trailing: trailing,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
