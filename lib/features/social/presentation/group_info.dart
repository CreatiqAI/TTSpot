import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../friends/application/nicknames.dart';
import '../../safety/application/name_check.dart';
import '../application/chat_providers.dart';
import '../application/community_providers.dart';
import '../application/group_chat_providers.dart';
import '../domain/chat.dart';
import '../domain/group_chat.dart';
import 'new_group_screen.dart';
import 'widgets/club_tier_widgets.dart' show clubRoleShort;
import 'widgets/group_avatar.dart';

/// The info page of a group chat.
/// A friends' group: its photo and name (admins change them), its members
/// (anyone adds their friends; admins remove people and make admins), the
/// chat settings, then Leave group.
/// A club chat: the club's name and logo (it follows the club), its members
/// with their club roles, the chat settings, and the way out (leave the club).
class GroupInfo extends ConsumerWidget {
  const GroupInfo({super.key, required this.conv, required this.me, required this.settings, this.shared});
  final Conversation conv;
  final String? me;
  /// What's been shared here (photos, posts), from the chat info page.
  final Widget? shared;
  /// Pin, mute, wallpaper and delete, from the chat info page.
  final List<Widget> settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nick = ref.watch(nicknamesProvider);
    final members = ref.watch(groupMembersProvider(conv.id));
    final clubId = conv.clubId;
    final roles = conv.isClubChat && clubId != null ? (ref.watch(clubMemberRolesProvider(clubId)).value ?? const <String, String>{}) : const <String, String>{};
    final admin = conv.amGroupAdmin;
    final count = members.value?.length ?? conv.size;
    final full = count >= kGroupMaxMembers;
    final title = conversationTitle(conv, nick);

    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 32),
      children: [
        const SizedBox(height: 18),
        Center(
          child: admin
              ? GroupPhotoSlot(url: conv.photoUrl, size: 96, onTap: () => _photoMenu(context, ref))
              : GestureDetector(
                  onTap: clubId != null && conv.isClubChat ? () => context.push(Routes.club(clubId)) : null,
                  child: GroupAvatar(conv: conv, size: 96),
                ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(title, key: const Key('group-info-title'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              ),
              if (admin)
                IconButton(
                  key: const Key('group-rename'),
                  tooltip: 'Rename group',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(AppIcons.pencilSimple, size: 18, color: AppColors.textSecondary),
                  onPressed: () => _rename(context, ref),
                ),
            ],
          ),
        ),
        Text(
          conv.isClubChat ? 'Club chat · $count ${count == 1 ? 'member' : 'members'}' : 'Group · $count ${count == 1 ? 'member' : 'members'}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (conv.isClubChat)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
            child: Text("Every member of the club is in here. It takes the club's name and logo.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
          ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (conv.isFriendGroup)
                Expanded(
                  child: _InfoButton(
                    key: const Key('group-add-members'),
                    icon: AppIcons.userPlus,
                    label: full ? 'Group full' : 'Add members',
                    onTap: full ? null : () => context.push(Routes.addGroupMembers(conv.id)),
                  ),
                ),
              if (conv.isClubChat && clubId != null) Expanded(child: _InfoButton(icon: AppIcons.usersThree, label: 'Open club', onTap: () => context.push(Routes.club(clubId)))),
            ],
          ),
        ),
        ?shared,
        _Section('MEMBERS · $count'),
        ...members.when(
          loading: () => [const Padding(padding: EdgeInsets.all(20), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))],
          error: (e, _) => [Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e), style: TextStyle(color: AppColors.textSecondary)))],
          data: (list) => [
            for (final m in list)
              _MemberTile(
                member: m,
                conv: conv,
                me: me,
                badge: conv.isClubChat
                    ? ((roles[m.id] ?? 'member') == 'member' ? null : clubRoleShort(roles[m.id]!))
                    : (m.isAdmin ? 'Admin' : null),
                manage: admin && m.id != me,
              ),
          ],
        ),
        const _Section('THIS CHAT'),
        ...settings,
        const Divider(height: 16),
        if (conv.isFriendGroup)
          ListTile(
            key: const Key('group-leave'),
            leading: const Icon(AppIcons.signOut, color: AppColors.danger),
            title: const Text('Leave group', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            subtitle: const Text("You stop getting its messages. A friend in it can add you back.", style: TextStyle(fontSize: 12)),
            onTap: () => _leave(context, ref),
          )
        else if (clubId != null)
          ListTile(
            leading: Icon(AppIcons.signOut, color: AppColors.textSecondary),
            title: const Text('Leave the club to leave this chat', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Or mute it to keep it quiet.', style: TextStyle(fontSize: 12)),
            trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            onTap: () => context.push(Routes.club(clubId)),
          ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(context: context, builder: (_) => _RenameDialog(initial: conv.groupName ?? ''));
    if (name == null || !context.mounted) return;
    await _run(context, () => ref.read(groupChatActionsProvider).rename(conv.id, name));
  }

  Future<void> _photoMenu(BuildContext context, WidgetRef ref) async {
    final hasPhoto = (conv.photoUrl ?? '').isNotEmpty;
    final pick = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.image), title: Text(hasPhoto ? 'Change photo' : 'Add a photo'), onTap: () => Navigator.pop(ctx, 'pick')),
            if (hasPhoto) ListTile(leading: const Icon(AppIcons.trash, color: AppColors.danger), title: Text('Remove photo', style: TextStyle(color: AppColors.danger)), onTap: () => Navigator.pop(ctx, 'remove')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || pick == null) return;
    if (pick == 'remove') {
      await _run(context, () => ref.read(groupChatActionsProvider).setPhoto(conv.id, null));
      return;
    }
    final file = await pickGroupPhoto(context);
    if (file == null || !context.mounted) return;
    await _run(context, () => ref.read(groupChatActionsProvider).setPhoto(conv.id, file));
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this group?'),
        content: const Text("You'll stop getting its messages. Someone in it can add you back."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(key: const Key('group-leave-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () async {
      await ref.read(groupChatActionsProvider).leave(conv.id);
      if (context.mounted) context.go(Routes.inbox);
    });
  }
}

/// The rename box. It owns its text controller, so the controller outlives the
/// dialog's closing animation.
class _RenameDialog extends ConsumerStatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  ConsumerState<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends ConsumerState<_RenameDialog> {
  late final _ctl = TextEditingController(text: widget.initial);
  /// The name filter, while typing. The current name is always fine.
  late final LiveNameCheck _check;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _check = LiveNameCheck(controller: _ctl, kind: NameKind.title, check: ref.read(nameCheckProvider), saved: widget.initial)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _check.dispose();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final problem = await _check.verify();
    if (!mounted) return;
    if (problem != null) {
      setState(() => _saving = false);
      return;
    }
    Navigator.pop(context, _ctl.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Group name'),
        content: TextField(
          key: const Key('group-rename-field'),
          controller: _ctl,
          autofocus: true,
          maxLength: kGroupNameMax,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: 'Name the group', helperText: "Leave it blank to show everyone's names.", helperMaxLines: 2, errorText: _check.problem, errorMaxLines: 2),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(key: const Key('group-rename-save'), onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      );
}

/// One member: tap for their profile, a DM, and (for admins) admin / remove.
class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member, required this.conv, required this.me, required this.badge, required this.manage});
  final GroupMember member;
  final Conversation conv;
  final String? me;
  final String? badge;
  final bool manage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = member.profile;
    final mine = p.id == me;
    final b = badge;
    return ListTile(
      key: Key('group-member-${p.id}'),
      leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, seed: p.id, size: 40),
      title: Row(
        children: [
          Flexible(child: Text(mine ? 'You' : ref.displayNameFor(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (b != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Text(b, maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ),
          ],
        ],
      ),
      subtitle: Text('@${p.username ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: mine ? null : Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
      onTap: mine ? null : () => _menu(context, ref),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final p = member.profile;
    final name = ref.read(nicknamesProvider)[p.id] ?? shortNameOf(p);
    final creator = p.id == conv.createdBy;
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.user), title: const Text('View profile'), onTap: () => Navigator.pop(ctx, 'profile')),
            ListTile(leading: const Icon(AppIcons.chatCircle), title: Text('Message $name', maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => Navigator.pop(ctx, 'dm')),
            if (manage && !creator)
              ListTile(
                key: const Key('group-member-admin'),
                leading: const Icon(AppIcons.shieldCheck),
                title: Text(member.isAdmin ? 'Remove as admin' : 'Make group admin'),
                onTap: () => Navigator.pop(ctx, member.isAdmin ? 'unadmin' : 'admin'),
              ),
            if (manage && !creator)
              ListTile(
                key: const Key('group-member-remove'),
                leading: const Icon(AppIcons.userMinus, color: AppColors.danger),
                title: Text('Remove from group', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    final actions = ref.read(groupChatActionsProvider);
    switch (action) {
      case 'profile':
        context.push(Routes.profile(p.id));
      case 'dm':
        await _run(context, () async {
          final id = await ref.read(chatActionsProvider).openDm(p.id);
          if (context.mounted) context.push(Routes.chat(id));
        });
      case 'admin':
        await _run(context, () => actions.setAdmin(conv.id, p.id, true));
      case 'unadmin':
        await _run(context, () => actions.setAdmin(conv.id, p.id, false));
      case 'remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Remove $name?'),
            content: const Text('They leave the group and stop getting its messages.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
              TextButton(key: const Key('group-member-remove-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
            ],
          ),
        );
        if (ok == true && context.mounted) await _run(context, () => actions.removeMember(conv.id, p.id));
    }
  }
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null ? AppColors.textSecondary : AppColors.textPrimary;
    return Material(
      color: AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: fg))),
              ],
            ),
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
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

Future<void> _run(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}
