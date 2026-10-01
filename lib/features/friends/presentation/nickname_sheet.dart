import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../auth/domain/profile.dart';
import '../application/nicknames.dart';

/// "Nickname" (备注): a private name for [p] that only I see. Save stores
/// it, Remove clears it.
Future<void> showNicknameSheet(BuildContext context, WidgetRef ref, Profile p) async {
  final current = ref.read(nicknamesProvider)[p.id];
  await showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true, // rides up with the keyboard
    builder: (ctx) => _NicknameSheet(profile: p, current: current),
  );
}

class _NicknameSheet extends ConsumerStatefulWidget {
  const _NicknameSheet({required this.profile, required this.current});
  final Profile profile;
  final String? current;

  @override
  ConsumerState<_NicknameSheet> createState() => _NicknameSheetState();
}

class _NicknameSheetState extends ConsumerState<_NicknameSheet> {
  late final _text = TextEditingController(text: widget.current ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(String? value) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ref.read(contactNicknamesProvider.notifier).setNickname(widget.profile.id, value);
      nav.pop();
      final v = value?.trim() ?? '';
      messenger.showSnackBar(SnackBar(content: Text(v.isEmpty ? 'Nickname removed.' : 'Saved. Only you see "$v".')));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final real = resolveDisplayName(displayName: p.displayName, username: p.username);
    final handle = (p.username ?? '').isEmpty ? '' : ' · @${p.username}';
    final hasCurrent = (widget.current ?? '').isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nickname', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(AppIcons.lock, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 5),
                  Expanded(child: Text('Only you can see this', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                autofocus: true,
                enabled: !_busy,
                maxLength: kNicknameMaxLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => _busy ? null : _save(v),
                decoration: InputDecoration(hintText: real, prefixIcon: const Icon(AppIcons.tag)),
              ),
              Text('Real name: $real$handle', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : () => _save(_text.text),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
              ),
              if (hasCurrent) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _busy ? null : () => _save(null),
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  child: const Text('Remove', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The name block on someone's profile: my nickname big with "Real name ·
/// @handle" under it, else their name and @handle as before.
class ProfileNameLines extends ConsumerWidget {
  const ProfileNameLines({super.key, required this.profile, required this.isMe});
  final Profile profile;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final where = (p.homeState ?? '').isNotEmpty ? ' · ${p.homeState}' : '';
    final nick = isMe ? null : ref.nicknameFor(p.id);
    final real = p.displayName ?? '@${p.username}';
    final big = nick ?? real;
    final small = nick == null ? '@${p.username}$where' : '${(p.displayName ?? '').trim().isEmpty ? '' : '${p.displayName!.trim()} · '}@${p.username}$where';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(big, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 1, 16, 0),
          child: Text(small, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
