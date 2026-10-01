import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../friends/application/friends_providers.dart';
import '../../application/plan_draft.dart';
import 'wizard_parts.dart';

/// Step "Who?": who can see it (friends or everyone; a club's version says
/// friends and members), then friends to invite. Inviting is optional; only
/// personal plans invite, a club or partner reaches its people itself.
class WhoStep extends ConsumerWidget {
  const WhoStep({super.key, required this.draft, this.clubName, this.canInvite = true});
  final PlanDraft draft;
  final String? clubName;
  final bool canInvite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = canInvite ? (ref.watch(friendsProvider).value ?? const <Profile>[]) : const <Profile>[];
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final picked = draft.invitees;
        final all = friends.isNotEmpty && picked.length == friends.length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            StepHeading('Who\'s it for?', subtitle: canInvite ? 'Choose who sees it, then invite a few friends if you like.' : 'Choose who sees it on the map.'),
            ChoiceCard(
              key: const Key('plan-audience-friends'),
              selected: draft.friendsOnly,
              icon: clubName == null ? AppIcons.users : AppIcons.usersThree,
              title: clubName == null ? 'Friends' : 'Friends and members',
              subtitle: clubName == null ? 'Your friends and anyone you invite.' : 'Your friends and $clubName members.',
              onTap: () => draft.setFriendsOnly(true),
            ),
            const SizedBox(height: 10),
            ChoiceCard(
              key: const Key('plan-audience-everyone'),
              selected: !draft.friendsOnly,
              icon: AppIcons.globe,
              title: 'Everyone',
              subtitle: 'Shows on the map for all of TT Spot.',
              onTap: () => draft.setFriendsOnly(false),
            ),
            if (canInvite) ...[
              const SizedBox(height: 22),
              SectionLabel(
                picked.isEmpty ? 'INVITE FRIENDS · OPTIONAL' : 'INVITE FRIENDS · ${picked.length} PICKED',
                trailing: friends.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => draft.setInvites(all ? const <String>[] : friends.map((f) => f.id)),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                        child: Text(all ? 'Clear' : 'Select all'),
                      ),
              ),
              if (friends.isEmpty)
                Text('No friends yet. Add friends and you can invite them next time.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))
              else ...[
                Text('Each one gets an invite card in your chat.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                for (final f in friends)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(url: f.avatarUrl, name: f.displayName ?? f.username, seed: f.id, size: 40),
                    title: Text(f.displayName ?? '@${f.username ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text('@${f.username ?? ''}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    trailing: Icon(picked.contains(f.id) ? AppIcons.checkCircleFill : AppIcons.checkCircle, color: picked.contains(f.id) ? AppColors.brand : AppColors.textMuted),
                    onTap: () => draft.toggleInvite(f.id),
                  ),
              ],
            ],
          ],
        );
      },
    );
  }
}
