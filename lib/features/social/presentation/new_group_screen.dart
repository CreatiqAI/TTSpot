import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/image_crop_screen.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/profile.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/application/nicknames.dart';
import '../../safety/application/name_check.dart';
import '../application/chat_providers.dart';
import '../application/group_chat_providers.dart';
import '../domain/group_chat.dart';

/// Pick a photo and frame it as a round group picture. Null when cancelled.
Future<XFile?> pickGroupPhoto(BuildContext context) async {
  final files = await pickPhotos(context, max: 1, multi: false, small: true);
  if (files.isEmpty || !context.mounted) return null;
  return cropImage(context, files.first, aspect: 1, outputWidth: 600, round: true, title: 'Frame the photo');
}

/// Chats > compose > New group: pick 2+ friends, then an optional name and
/// photo, then Create. Opens the new chat.
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _picked = <String>[];
  final _name = TextEditingController();
  XFile? _photo;
  bool _naming = false;
  bool _busy = false;
  /// The name filter on the group name, while typing.
  late final LiveNameCheck _nameCheck;

  @override
  void initState() {
    super.initState();
    _nameCheck = LiveNameCheck(controller: _name, kind: NameKind.title, check: ref.read(nameCheckProvider))
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _nameCheck.dispose();
    _name.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));

  Future<void> _pickPhoto() async {
    final f = await pickGroupPhoto(context);
    if (f != null && mounted) setState(() => _photo = f);
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    if (await _nameCheck.verify() != null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final id = await ref.read(groupChatActionsProvider).create(memberIds: List.of(_picked), name: _name.text, photo: _photo);
      if (mounted) context.pushReplacement(Routes.chat(id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final enough = _picked.length >= kGroupMinFriends;
    return PopScope(
      canPop: !_naming,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _naming = false);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => _naming ? setState(() => _naming = false) : context.pop()),
          title: Text(_naming ? 'Name the group' : 'New group'),
          actions: [
            if (!_naming)
              TextButton(
                key: const Key('new-group-next'),
                onPressed: enough ? () => setState(() => _naming = true) : null,
                child: const Text('Next'),
              ),
          ],
        ),
        body: _naming
            ? _NameStep(
                name: _name,
                nameProblem: _nameCheck.problem,
                photo: _photo,
                busy: _busy,
                members: [for (final f in friends.value ?? const <Profile>[]) if (_picked.contains(f.id)) f],
                onPhoto: _pickPhoto,
                onCreate: _create,
              )
            : friends.when(
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), textAlign: TextAlign.center))),
                data: (list) => list.length < kGroupMinFriends
                    ? Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: EmptyState(
                          art: AppArt.speech,
                          title: 'Add friends first',
                          subtitle: 'A group needs at least 2 friends in it. Add some, then come back.',
                          actionLabel: 'Find friends',
                          onAction: () => context.push(Routes.friends),
                        ),
                      )
                    : FriendPicker(
                        friends: list,
                        picked: _picked,
                        onToggle: _toggle,
                        limit: kGroupMaxMembers - 1,
                        hint: enough ? '${_picked.length} picked' : 'Pick at least 2 friends',
                      ),
              ),
      ),
    );
  }
}

class _NameStep extends StatelessWidget {
  const _NameStep({required this.name, this.nameProblem, required this.photo, required this.busy, required this.members, required this.onPhoto, required this.onCreate});
  final TextEditingController name;
  /// Why the name filter refuses the name, shown under the field.
  final String? nameProblem;
  final XFile? photo;
  final bool busy;
  final List<Profile> members;
  final VoidCallback onPhoto;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.paddingOf(context).bottom + 24),
        children: [
          Center(child: GroupPhotoSlot(file: photo, onTap: busy ? null : onPhoto)),
          const SizedBox(height: 20),
          TextField(
            key: const Key('new-group-name'),
            controller: name,
            maxLength: kGroupNameMax,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Group name (optional)', helperText: "Leave it blank to show everyone's names.", helperMaxLines: 2, errorText: nameProblem, errorMaxLines: 2),
          ),
          const SizedBox(height: 14),
          Text('MEMBERS · ${members.length + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final p in members) _PickedFace(profile: p)],
          ),
          const SizedBox(height: 24),
          PrimaryButton(key: const Key('new-group-create'), label: 'Create group', loading: busy, onPressed: onCreate),
        ],
      );
}

class _PickedFace extends ConsumerWidget {
  const _PickedFace({required this.profile, this.onRemove});
  final Profile profile;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nick = ref.nicknameFor(profile.id);
    final name = nick ?? shortNameOf(profile);
    return SizedBox(
      width: 60,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(url: profile.avatarUrl, name: profile.displayName ?? profile.username, seed: profile.id, size: 48),
              if (onRemove != null)
                Positioned(
                  right: -4,
                  top: -4,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: AppColors.textSecondary, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
                      child: const Icon(AppIcons.x, size: 11, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// The round photo slot on the new-group form (and in group info).
class GroupPhotoSlot extends StatelessWidget {
  const GroupPhotoSlot({super.key, this.file, this.url, required this.onTap, this.size = 104});
  final XFile? file;
  final String? url;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final f = file;
    final u = url;
    final ImageProvider? image = f != null ? FileImage(File(f.path)) : (u != null && u.isNotEmpty ? NetworkImage(u) : null);
    return Semantics(
      button: true,
      label: image == null ? 'Add a group photo' : 'Change group photo',
      child: GestureDetector(
        key: const Key('group-photo-slot'),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceGray,
                border: Border.all(color: AppColors.border, width: 1.5),
                image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
              ),
              child: image == null ? Icon(AppIcons.usersThree, size: size * 0.38, color: AppColors.textSecondary) : null,
            ),
            if (onTap != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 3)),
                  child: Icon(image == null ? AppIcons.cameraPlus : AppIcons.pencilSimple, size: 16, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Search your friends and tick the ones to add. [taken] are already in the
/// group (shown, not pickable); at most [limit] can be ticked.
class FriendPicker extends ConsumerStatefulWidget {
  const FriendPicker({super.key, required this.friends, required this.picked, required this.onToggle, required this.limit, required this.hint, this.taken = const {}});
  final List<Profile> friends;
  final List<String> picked;
  final ValueChanged<String> onToggle;
  final int limit;
  final String hint;
  final Set<String> taken;

  @override
  ConsumerState<FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends ConsumerState<FriendPicker> {
  String _q = '';

  bool _matches(Profile p, String? nick) {
    if (_q.isEmpty) return true;
    return [p.displayName, p.username, nick].any((s) => (s ?? '').toLowerCase().contains(_q));
  }

  void _tap(String id) {
    if (!widget.picked.contains(id) && widget.picked.length >= widget.limit) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('A group holds up to $kGroupMaxMembers members.')));
      return;
    }
    widget.onToggle(id);
  }

  @override
  Widget build(BuildContext context) {
    final nick = ref.watch(nicknamesProvider);
    final byId = {for (final f in widget.friends) f.id: f};
    final shown = widget.friends.where((f) => _matches(f, nick[f.id])).toList()
      ..sort((a, b) => displayNameFor(a, nick).toLowerCase().compareTo(displayNameFor(b, nick).toLowerCase()));
    final picked = [for (final id in widget.picked) if (byId[id] != null) byId[id]!];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            textInputAction: TextInputAction.search,
            key: const Key('friend-picker-search'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            decoration: const InputDecoration(hintText: 'Search friends', prefixIcon: Icon(AppIcons.magnifyingGlass), isDense: true),
          ),
        ),
        if (picked.isNotEmpty)
          SizedBox(
            height: 86,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              children: [
                for (final p in picked)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _PickedFace(profile: p, onRemove: () => widget.onToggle(p.id))),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Expanded(child: Text('FRIENDS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
              Flexible(child: Text(widget.hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_q.isEmpty ? 'No friends to add yet.' : 'No friends match "$_q".', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16),
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final f = shown[i];
                    final inGroup = widget.taken.contains(f.id);
                    final on = inGroup || widget.picked.contains(f.id);
                    return ListTile(
                      key: Key('friend-pick-${f.id}'),
                      enabled: !inGroup,
                      leading: UserAvatar(url: f.avatarUrl, name: f.displayName ?? f.username, seed: f.id, size: 44),
                      title: Text(displayNameFor(f, nick), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(inGroup ? 'Already in the group' : '@${f.username ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      trailing: Icon(on ? AppIcons.checkCircleFill : AppIcons.checkCircle, color: on ? AppColors.brand : AppColors.textMuted),
                      onTap: inGroup ? null : () => _tap(f.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Group info > Add members: my friends who aren't in it yet.
class AddGroupMembersScreen extends ConsumerStatefulWidget {
  const AddGroupMembersScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<AddGroupMembersScreen> createState() => _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState extends ConsumerState<AddGroupMembersScreen> {
  final _picked = <String>[];
  bool _busy = false;

  Future<void> _add() async {
    setState(() => _busy = true);
    try {
      final n = await ref.read(groupChatActionsProvider).addMembers(widget.conversationId, List.of(_picked));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 1 ? 'Added 1 friend.' : 'Added $n friends.')));
      context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final members = ref.watch(groupMembersProvider(widget.conversationId)).value;
    final conv = ref.watch(conversationProvider(widget.conversationId)).value;
    final inGroup = members == null ? {for (final p in conv?.members ?? const <Profile>[]) p.id} : {for (final m in members) m.id};
    final room = kGroupMaxMembers - (members?.length ?? conv?.size ?? 0);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Add members'),
        actions: [
          TextButton(
            key: const Key('add-members-confirm'),
            onPressed: _picked.isEmpty || _busy ? null : _add,
            child: Text(_picked.isEmpty ? 'Add' : 'Add ${_picked.length}'),
          ),
        ],
      ),
      body: friends.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) => FriendPicker(
          friends: list,
          picked: _picked,
          taken: inGroup,
          onToggle: (id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id)),
          limit: room < 0 ? 0 : room,
          hint: room <= 0 ? 'The group is full' : (room == 1 ? '1 spot left' : '$room spots left'),
        ),
      ),
    );
  }
}
