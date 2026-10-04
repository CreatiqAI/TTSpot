import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/auth/domain/profile.dart';
import '../../features/friends/application/friends_providers.dart';
import '../../features/friends/application/nicknames.dart';
import '../../features/social/application/chat_providers.dart';
import '../../features/social/domain/chat.dart';
import '../../features/social/presentation/widgets/group_avatar.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/titi.dart';
import '../utils/friendly_error.dart';
import '../utils/open_external.dart';
import '../utils/share_links.dart';
import 'empty_state.dart';
import 'sheet_header.dart';
import 'user_avatar.dart';

/// Something to share: a meet, a spot, a car, a partner. [type] + [id] make
/// the public link. With [eventId], [placeId] or [carId], "Send in TT Spot"
/// drops the preview card into the chat instead of a bare link.
class ShareItem {
  const ShareItem({required this.type, required this.id, required this.title, this.text, this.eventId, this.placeId, this.carId});
  final String type;
  final String id;
  final String title;

  /// The whole message for WhatsApp and More, link included. Defaults to
  /// "[title] on TT Spot" and the link.
  final String? text;
  final String? eventId;
  final String? placeId;
  final String? carId;

  String get link => shareLink(type, id);
  String get message => text ?? '$title on TT Spot\n$link';
}

/// An extra row above the usual four, like the meet's story image.
class ShareExtra {
  const ShareExtra({required this.icon, required this.label, this.subtitle, required this.onTap});
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
}

/// Share sheet: Send in TT Spot · WhatsApp · Copy link · More (the phone's
/// own sheet). Each choice runs after the sheet closes, on [context].
Future<void> showShareOptions(BuildContext context, ShareItem item, {List<ShareExtra> extras = const []}) async {
  final choice = await showModalBottomSheet<Object>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Share ${item.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
          _Option(
            icon: AppIcons.paperPlaneTilt,
            tint: AppColors.brand,
            title: 'Send in TT Spot',
            subtitle: 'To a friend or one of your chats',
            onTap: () => Navigator.pop(ctx, 'send'),
          ),
          _Option(
            icon: AppIcons.whatsappLogo,
            tint: const Color(0xFF1E9E4A),
            title: 'WhatsApp',
            subtitle: 'A chat or group, with the link',
            onTap: () => Navigator.pop(ctx, 'whatsapp'),
          ),
          for (final e in extras) _Option(icon: e.icon, title: e.label, subtitle: e.subtitle, onTap: () => Navigator.pop(ctx, e)),
          _Option(icon: AppIcons.link, title: 'Copy link', onTap: () => Navigator.pop(ctx, 'copy')),
          _Option(icon: AppIcons.dotsThree, title: 'More', subtitle: 'Telegram, Instagram, email…', onTap: () => Navigator.pop(ctx, 'more')),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case ShareExtra(:final onTap):
      onTap();
    case 'send':
      await showModalBottomSheet<void>(
        useRootNavigator: true,
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _SendSheet(item: item),
      );
    case 'whatsapp':
      await openExternal(context, 'whatsapp://send?text=${Uri.encodeComponent(item.message)}', fallbackUrl: whatsappUrl(item.message), appName: 'WhatsApp');
    case 'copy':
      await Clipboard.setData(ClipboardData(text: item.link));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Link copied.')));
      }
    case 'more':
      await SharePlus.instance.share(ShareParams(text: item.message));
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.title, this.subtitle, this.tint, required this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  /// Brand colour for the icon box; neutral grey without one.
  final Color? tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tint?.withValues(alpha: 0.14) ?? AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: tint ?? AppColors.textPrimary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        onTap: onTap,
      );
}

// ------------------------------------------------------ send in TT Spot ---

/// Pick chats and friends, add a note, Send. Recent chats first (DMs and meet
/// chats), then friends you haven't chatted with yet.
class _SendSheet extends ConsumerStatefulWidget {
  const _SendSheet({required this.item});
  final ShareItem item;

  @override
  ConsumerState<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends ConsumerState<_SendSheet> {
  /// `c:` + a conversation id for a chat, `u:` + a user id for a friend.
  final _picked = <String>{};
  final _note = TextEditingController();
  String _q = '';
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_picked.isEmpty) return;
    setState(() => _busy = true);
    final actions = ref.read(chatActionsProvider);
    final item = widget.item;
    final note = _note.text.trim();
    try {
      for (final key in _picked) {
        final conv = key.startsWith('c:') ? key.substring(2) : await actions.openDm(key.substring(2));
        if (item.eventId != null || item.placeId != null || item.carId != null) {
          // The meet / spot / car card, then the note under it.
          await actions.attach(conv, eventId: item.eventId, placeId: item.placeId, carId: item.carId);
          if (note.isNotEmpty) await actions.send(conv, note);
        } else {
          await actions.send(conv, note.isEmpty ? item.message : '$note\n${item.link}');
        }
      }
      ref.invalidate(inboxProvider);
      if (!mounted) return;
      final n = _picked.length;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 1 ? 'Sent.' : 'Sent to $n chats.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  bool _matches(String? a, [String? b, String? c]) => _q.isEmpty || (a ?? '').toLowerCase().contains(_q) || (b ?? '').toLowerCase().contains(_q) || (c ?? '').toLowerCase().contains(_q);

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider).value ?? const <Conversation>[];
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final nick = ref.watch(nicknamesProvider); // my private names for people (备注)
    // Chats with something in them (an empty DM counts as "not chatted yet"),
    // and only ones we can name: a DM whose other side is gone just says "Chat".
    // Group and club chats count from the start, like meet chats.
    final chats = inbox.where((c) => (c.isMulti || c.lastMessage != null) && (c.isMulti || c.showEntity || c.other != null)).toList();
    final dmWith = {for (final c in chats) if (!c.isMulti && !c.hasEntity && c.other != null) c.other!.id};
    final shownChats = chats.where((c) => _matches(conversationTitle(c, nick), c.other?.username, c.title)).toList();
    final shownFriends = friends.where((f) => !dmWith.contains(f.id) && _matches(f.displayName, f.username, nick[f.id])).toList();
    final nobody = chats.isEmpty && friends.every((f) => dmWith.contains(f.id));

    Widget tick(String key) {
      final on = _picked.contains(key);
      return Icon(on ? AppIcons.checkCircleFill : AppIcons.checkCircle, color: on ? AppColors.brand : AppColors.textMuted);
    }

    void toggle(String key) => setState(() => _picked.contains(key) ? _picked.remove(key) : _picked.add(key));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: [
              const Padding(padding: EdgeInsets.fromLTRB(20, 0, 16, 8), child: SheetHeader(title: 'Send to')),
              if (!nobody)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                    decoration: const InputDecoration(hintText: 'Search chats and friends', prefixIcon: Icon(AppIcons.magnifyingGlass), isDense: true),
                  ),
                ),
              Expanded(
                child: nobody
                    ? const EmptyState(titi: TitiPose.chat, title: 'No one to send to yet', subtitle: 'Add friends or join a meet chat, then share it here.')
                    : ListView(
                        children: [
                          if (shownChats.isNotEmpty) const _Section('RECENT CHATS'),
                          for (final c in shownChats)
                            ListTile(
                              leading: c.isGroup ? GroupAvatar(conv: c, size: 44) : UserAvatar(url: c.avatarUrl, name: c.title, seed: c.other?.id ?? c.id, size: 44),
                              title: Text(conversationTitle(c, nick), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                c.isGroup
                                    ? '${c.isClubChat ? 'Club chat' : 'Group'} · ${c.size} ${c.size == 1 ? 'person' : 'people'}'
                                    : c.isMeet
                                    ? 'Meet chat · ${c.members.length} ${c.members.length == 1 ? 'person' : 'people'}'
                                    : c.showEntity
                                        ? (c.clubId != null ? 'Club chat' : 'Partner chat')
                                        : '@${c.other?.username ?? ''}',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                              trailing: tick('c:${c.id}'),
                              onTap: () => toggle('c:${c.id}'),
                            ),
                          if (shownFriends.isNotEmpty) const _Section('FRIENDS'),
                          for (final f in shownFriends)
                            ListTile(
                              leading: UserAvatar(url: f.avatarUrl, name: f.displayName ?? f.username, seed: f.id, size: 44),
                              title: Text(displayNameFor(f, nick), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('@${f.username ?? ''}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              trailing: tick('u:${f.id}'),
                              onTap: () => toggle('u:${f.id}'),
                            ),
                          if (shownChats.isEmpty && shownFriends.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text('No one called "$_q".', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                            ),
                        ],
                      ),
              ),
              if (!nobody)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _note,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Add a message…', isDense: true),
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

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
