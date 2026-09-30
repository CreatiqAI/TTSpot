import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart';
import '../application/titi_controller.dart';
import '../domain/titi_message.dart';

/// The history button's sheet: my chats with TiTi, latest first, with New chat
/// on top. Tap one to open it; swipe it left or long-press it to delete it
/// (asks first; its photos go too).
Future<void> showTitiSessions(BuildContext context) => showModalBottomSheet<void>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SessionsSheet(),
    );

class _SessionsSheet extends ConsumerStatefulWidget {
  const _SessionsSheet();

  @override
  ConsumerState<_SessionsSheet> createState() => _SessionsSheetState();
}

class _SessionsSheetState extends ConsumerState<_SessionsSheet> {
  /// Deleted here: hidden at once, before the list reloads.
  final _gone = <String>{};

  Future<bool> _delete(TitiSession s) async {
    final ok = await confirmSheet(context, title: 'Delete this chat?', body: '"${s.title ?? 'New chat'}" and its photos are deleted.', confirm: 'Delete', icon: AppIcons.trash);
    if (!ok) return false;
    setState(() => _gone.add(s.id));
    try {
      await ref.read(titiControllerProvider.notifier).deleteSession(s.id);
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _gone.remove(s.id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
      return false;
    }
  }

  void _open(TitiSession s) {
    Navigator.pop(context);
    final c = ref.read(titiControllerProvider.notifier);
    if (ref.read(titiControllerProvider).sessionId != s.id) c.open(s.id, title: s.title);
  }

  void _new() {
    Navigator.pop(context);
    ref.read(titiControllerProvider.notifier).newChat();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(titiSessionsProvider);
    final current = ref.watch(titiControllerProvider.select((s) => s.sessionId));
    final list = [for (final s in sessions.value ?? const <TitiSession>[]) if (!_gone.contains(s.id)) s];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('Chats with TiTi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  FilledButton.icon(
                    onPressed: _new,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: Colors.white, shape: const StadiumBorder(), minimumSize: const Size(0, 38)),
                    icon: const Icon(AppIcons.notePencil, size: 17),
                    label: const Text('New chat'),
                  ),
                ],
              ),
            ),
            if (sessions.isLoading && list.isEmpty)
              const Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator(strokeWidth: 2))
            else if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: Text(sessions.hasError ? friendlyError(sessions.error!) : 'No chats yet. Ask TiTi anything to start one.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final s = list[i];
                    final open = s.id == current;
                    return Dismissible(
                      key: ValueKey(s.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _delete(s),
                      background: Container(
                        color: AppColors.danger,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(AppIcons.trash, color: Colors.white),
                      ),
                      child: ListTile(
                        leading: TitiAvatar(open ? TitiPose.chat : TitiPose.thumbsUp, size: 40),
                        title: Text(s.title ?? 'New chat', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: open ? FontWeight.w800 : FontWeight.w600)),
                        subtitle: Text(open ? 'Open now · ${timeAgo(s.updatedAt)}' : timeAgo(s.updatedAt), style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        trailing: open ? const Icon(AppIcons.checkCircleFill, color: AppColors.brand, size: 20) : null,
                        onTap: () => _open(s),
                        onLongPress: () => _delete(s),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
