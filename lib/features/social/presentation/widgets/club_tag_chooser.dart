import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/sheet_header.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/data/auth_repository.dart' show currentProfileProvider;
import '../../application/club_tag_providers.dart';
import '../../application/community_providers.dart' show myClubRolesProvider;
import '../../domain/club.dart';
import '../../domain/club_tag.dart';
import 'club_name_tag.dart';
import 'club_tier_widgets.dart' show clubRoleLabel;

/// Settings > Club tag on my name: which of my official clubs' tags shows
/// beside my name (posts, comments, my profile), or none. Every member
/// chooses, presidents too (a president who never chose wears their own
/// club's). Underground clubs have no tag, so they aren't listed.
Future<void> showClubTagChooser(BuildContext context) => showModalBottomSheet<void>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const ClubTagChooserSheet(),
    );

class ClubTagChooserSheet extends ConsumerStatefulWidget {
  const ClubTagChooserSheet({super.key});

  @override
  ConsumerState<ClubTagChooserSheet> createState() => _ClubTagChooserSheetState();
}

class _ClubTagChooserSheetState extends ConsumerState<ClubTagChooserSheet> {
  /// What I just tapped, shown at once while it saves (null = None).
  String? _picked;
  bool _hasPick = false;
  bool _saving = false;

  Future<void> _choose(String? clubId, String? current) async {
    if (_saving || clubId == current) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _picked = clubId;
      _hasPick = true;
      _saving = true;
    });
    try {
      await ref.read(clubTagActionsProvider).choose(clubId);
    } catch (e) {
      if (mounted) setState(() => _hasPick = false); // back to what the server has
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final clubs = ref.watch(myOfficialClubsProvider);
    final current = me == null ? null : ref.watch(clubTagProvider(me));
    final roles = ref.watch(myClubRolesProvider).value ?? const <String, String>{};
    final profile = ref.watch(currentProfileProvider).value;
    final list = clubs.value ?? const <Club>[];
    final serverPick = current?.value?.clubId;
    final selected = _hasPick ? _picked : serverPick;
    final loading = (clubs.isLoading && !clubs.hasValue) || (current != null && current.isLoading && !current.hasValue);

    String roleOf(Club c) => c.ownerId == me ? 'owner' : (roles[c.id] ?? 'member');
    final selectedClub = list.where((c) => c.id == selected).firstOrNull;
    final previewTag = selectedClub == null
        ? null
        : ClubTag(clubId: selectedClub.id, name: selectedClub.name, handle: selectedClub.handle, avatarUrl: selectedClub.avatarUrl, role: roleOf(selectedClub));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(title: 'Club tag on my name'),
              const SizedBox(height: 4),
              Text(
                'Pick the official club whose tag shows beside your name on posts, comments and your profile. One at a time.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 12),
              // How my name reads with the pick.
              _Preview(name: profile?.displayName ?? '@${profile?.username ?? ''}', avatarUrl: profile?.avatarUrl, seed: me, tag: previewTag),
              const SizedBox(height: 6),
              Flexible(
                child: loading
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                    : list.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'You\'re not in an official club yet. Official clubs have a gold tag their members can wear. Underground clubs don\'t have one.',
                              style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final c in list)
                                _Option(
                                  key: Key('club-tag-option-${c.id}'),
                                  selected: selected == c.id,
                                  busy: _saving && _picked == c.id,
                                  leading: UserAvatar(url: c.avatarUrl, name: c.name, size: 40, borderColor: officialGold(), fallbackAsset: crestAsset(c.id)),
                                  title: c.name,
                                  subtitle: clubRoleLabel(roleOf(c)),
                                  onTap: () => _choose(c.id, selected),
                                ),
                              _Option(
                                key: const Key('club-tag-option-none'),
                                selected: selected == null,
                                busy: _saving && _hasPick && _picked == null,
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceGray),
                                  child: Icon(AppIcons.prohibit, size: 20, color: AppColors.textSecondary),
                                ),
                                title: 'None',
                                subtitle: 'No club tag beside my name',
                                onTap: () => _choose(null, selected),
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

/// My avatar and name as others see them, with the tag I picked.
class _Preview extends StatelessWidget {
  const _Preview({required this.name, this.avatarUrl, this.seed, this.tag});
  final String name;
  final String? avatarUrl;
  final String? seed;
  final ClubTag? tag;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('club-tag-preview'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            UserAvatar(url: avatarUrl, name: name, seed: seed, size: 32),
            const SizedBox(width: 10),
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
            const SizedBox(width: 6),
            if (tag != null)
              // Not tappable here: it's a preview.
              IgnorePointer(child: ClubNameTag(tag: tag))
            else
              Text('No tag', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ],
        ),
      );
}

/// A radio row: picture, name, role, the radio (a spinner while it saves).
class _Option extends StatelessWidget {
  const _Option({super.key, required this.selected, required this.busy, required this.leading, required this.title, required this.subtitle, required this.onTap});
  final bool selected;
  final bool busy;
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: busy
                      ? Padding(padding: const EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                      : AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: selected ? AppColors.brand : AppColors.textMuted, width: selected ? 7 : 1.6),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
}
