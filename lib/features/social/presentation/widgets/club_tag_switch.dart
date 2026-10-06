import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../application/club_tag_providers.dart';
import '../../domain/club.dart';
import '../../domain/club_tag.dart';
import 'club_name_tag.dart';

/// On an official club's page, for its people: "Show club tag on my name".
/// Members opt in (one club at a time: wearing this one takes off another);
/// the president always carries it, so they get a line saying so instead.
/// Nothing for underground clubs, which have no tag.
class ClubTagSwitch extends ConsumerStatefulWidget {
  const ClubTagSwitch({super.key, required this.club, required this.isOwner});
  final Club club;
  final bool isOwner;

  @override
  ConsumerState<ClubTagSwitch> createState() => _ClubTagSwitchState();
}

class _ClubTagSwitchState extends ConsumerState<ClubTagSwitch> {
  /// The answer shown while saving, so the switch moves at once.
  bool? _pending;

  Future<void> _set(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending = on);
    try {
      await ref.read(clubTagActionsProvider).setWearing(widget.club.id, on);
      messenger.showSnackBar(SnackBar(content: Text(on ? '${widget.club.name}\'s tag now shows beside your name.' : 'Club tag off.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.club;
    if (!c.isOfficial) return const SizedBox.shrink();
    final tag = ClubTag(clubId: c.id, name: c.name, handle: c.handle, avatarUrl: c.avatarUrl, role: widget.isOwner ? 'owner' : 'member');
    final wearing = _pending ?? ref.watch(wearingClubTagProvider(c.id)).value ?? false;
    final title = Row(
      children: [
        const Flexible(
          child: Text('Show club tag on my name', maxLines: 2, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        const SizedBox(width: 6),
        ClubNameTag(tag: tag, maxWidth: 96),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      // Material, not a coloured box: the tile's ink shows on it.
      child: Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: widget.isOwner
            ? ListTile(
                key: const Key('club-tag-president'),
                leading: Icon(AppIcons.sealCheck, color: officialGold()),
                title: title,
                subtitle: Text('As president you always carry it: beside your name on posts, comments and your profile.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              )
            : SwitchListTile.adaptive(
                key: const Key('club-tag-switch'),
                value: wearing,
                onChanged: _pending != null ? null : _set,
                secondary: Icon(AppIcons.sealCheck, color: officialGold()),
                title: title,
                subtitle: Text(
                  wearing ? 'Beside your name on posts, comments and your profile.' : 'Wear ${c.name}\'s tag beside your name. One club at a time.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
      ),
    );
  }
}
