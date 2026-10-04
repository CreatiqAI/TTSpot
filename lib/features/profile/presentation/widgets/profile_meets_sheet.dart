import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/event_list_tile.dart';
import '../../../events/domain/event.dart';
import '../../application/profile_meets_provider.dart';
import '../../domain/profile_meets.dart';

/// What the profile's "Meets" number counts, listed. [count] is that number
/// (private meets are in it but not in the list). On my own profile
/// [onSeeAll] opens all my meets, upcoming ones too.
Future<void> showProfileMeetsSheet(BuildContext context, {required String userId, required bool isMe, int? count, VoidCallback? onSeeAll}) {
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => ProfileMeetsSheet(
      userId: userId,
      isMe: isMe,
      count: count,
      // From the profile, once the sheet is down (not under it).
      onOpen: (e) {
        Navigator.pop(sheet);
        if (context.mounted) context.push(Routes.event(e.id));
      },
      onSeeAll: isMe && onSeeAll != null
          ? () {
              Navigator.pop(sheet);
              onSeeAll();
            }
          : null,
    ),
  );
}

class ProfileMeetsSheet extends ConsumerWidget {
  const ProfileMeetsSheet({super.key, required this.userId, required this.isMe, this.count, required this.onOpen, this.onSeeAll});
  final String userId;
  final bool isMe;
  final int? count;
  final void Function(Event e) onOpen;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meets = ref.watch(profileMeetsProvider(userId));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(count == null ? 'Meets' : 'Meets · $count', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  if (onSeeAll != null) TextButton(onPressed: onSeeAll, child: const Text('All my meets')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
              child: Text(meetsExplainer(isMe: isMe), style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
            ),
            const Divider(height: 1),
            Expanded(
              child: meets.when(
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(friendlyError(e), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      TextButton(onPressed: () => ref.invalidate(profileMeetsProvider(userId)), child: const Text('Retry')),
                    ],
                  ),
                ),
                data: (m) {
                  final hidden = privateMeetsLine(m.hiddenOf(count));
                  if (m.events.isEmpty && hidden == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          isMe ? 'No meets yet. Join a meet or a TT session and it counts here once it starts.' : 'No meets yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }
                  return ListView(
                    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16),
                    children: [
                      for (final e in m.events)
                        EventListTile(
                          event: e,
                          isOrganiser: e.organizerId == userId,
                          onTap: () => onOpen(e),
                          trailing: m.wentTo(e) ? const _CheckedIn() : null,
                        ),
                      if (hidden != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          child: Text(hidden, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                        ),
                    ],
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

class _CheckedIn extends StatelessWidget {
  const _CheckedIn();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text('Checked in', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.success)),
      );
}
