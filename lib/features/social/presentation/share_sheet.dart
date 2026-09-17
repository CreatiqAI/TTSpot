import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/profile.dart';
import '../../friends/application/friends_providers.dart';
import '../application/chat_providers.dart';

/// "Send to…" sheet: tick friends, add a note, Send. Drops the post or moment
/// into each friend's chat as a preview card.
Future<void> showShareSheet(BuildContext context, {String? postId, String? storyId, String? preset}) {
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(postId: postId, storyId: storyId, preset: preset),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({this.postId, this.storyId, this.preset});
  final String? postId;
  final String? storyId;
  final String? preset;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _picked = <String>{};
  final _note = TextEditingController();
  final _search = TextEditingController();
  String _q = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.preset != null) _picked.add(widget.preset!);
  }

  @override
  void dispose() {
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_picked.isEmpty) return;
    setState(() => _busy = true);
    final actions = ref.read(chatActionsProvider);
    try {
      for (final id in _picked) {
        final conv = await actions.openDm(id);
        await actions.share(conv, postId: widget.postId, storyId: widget.storyId, note: _note.text);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_picked.length == 1 ? 'Sent.' : 'Sent to ${_picked.length} friends.')));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? friends : friends.where((f) => (f.displayName ?? '').toLowerCase().contains(q) || (f.username ?? '').toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Send to', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(hintText: 'Search friends', prefixIcon: Icon(AppIcons.magnifyingGlass), isDense: true),
                ),
              ),
              Expanded(
                child: friends.isEmpty
                    ? Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Add friends first, then you can send them things.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary))))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final f = list[i];
                          final on = _picked.contains(f.id);
                          return ListTile(
                            leading: UserAvatar(url: f.avatarUrl, name: f.displayName ?? f.username, size: 44),
                            title: Text(f.displayName ?? '@${f.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('@${f.username ?? ''}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            trailing: Icon(on ? AppIcons.checkCircleFill : AppIcons.checkCircle, color: on ? AppColors.brand : AppColors.textMuted),
                            onTap: () => setState(() => on ? _picked.remove(f.id) : _picked.add(f.id)),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _note,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: 'Write a message…', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _busy || _picked.isEmpty ? null : _send,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 18)),
                      child: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_picked.isEmpty ? 'Send' : 'Send (${_picked.length})'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
