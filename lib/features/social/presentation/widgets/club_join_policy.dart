import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../events/presentation/plan_steps/wizard_parts.dart';
import '../../application/community_providers.dart';
import '../../domain/club.dart';

/// One line on what each kind of club means, as the choice and the club page say it.
const kPublicClubLine = 'Anyone can join right away.';
const kPrivateClubLine = 'People ask to join, you approve.';

/// Who can join: Public (the default, listed first) or Private.
class ClubJoinPolicyChoice extends StatelessWidget {
  const ClubJoinPolicyChoice({super.key, required this.isPublic, required this.onChanged});
  final bool isPublic;
  /// Null while saving.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoiceCard(
            key: const Key('club-join-public'),
            selected: isPublic,
            icon: AppIcons.globe,
            title: 'Public',
            subtitle: kPublicClubLine,
            onTap: onChanged == null ? null : () => onChanged!(true),
          ),
          const SizedBox(height: 10),
          ChoiceCard(
            key: const Key('club-join-private'),
            selected: !isPublic,
            icon: AppIcons.lock,
            title: 'Private',
            subtitle: kPrivateClubLine,
            onTap: onChanged == null ? null : () => onChanged!(false),
          ),
        ],
      );
}

/// Officers on the club page: public or private, with Change.
class ClubJoinPolicyTile extends StatelessWidget {
  const ClubJoinPolicyTile({super.key, required this.club});
  final Club club;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        // Material, not a coloured box: the tile's ink shows on it.
        child: Material(
          color: AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: const Key('club-join-policy'),
            leading: Icon(club.isPublic ? AppIcons.globe : AppIcons.lock),
            title: Text(club.isPublic ? 'Public club' : 'Private club', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(club.isPublic ? kPublicClubLine : kPrivateClubLine, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            trailing: TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => showClubJoinPolicySheet(context, club), child: const Text('Change')),
            onTap: () => showClubJoinPolicySheet(context, club),
          ),
        ),
      );
}

Future<void> showClubJoinPolicySheet(BuildContext context, Club club) => showModalBottomSheet<void>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ClubJoinPolicySheet(club: club),
    );

/// Pick public or private; it saves on tap and closes.
class ClubJoinPolicySheet extends ConsumerStatefulWidget {
  const ClubJoinPolicySheet({super.key, required this.club});
  final Club club;
  @override
  ConsumerState<ClubJoinPolicySheet> createState() => _ClubJoinPolicySheetState();
}

class _ClubJoinPolicySheetState extends ConsumerState<ClubJoinPolicySheet> {
  late bool _public = widget.club.isPublic;
  bool _busy = false;

  Future<void> _pick(bool isPublic) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (isPublic == widget.club.isPublic) {
      nav.pop();
      return;
    }
    setState(() {
      _public = isPublic;
      _busy = true;
    });
    try {
      await ref.read(communityActionsProvider).setClubJoinPolicy(widget.club.id, isPublic: isPublic);
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(isPublic ? 'Public club. Anyone can join right away.' : 'Private club. People ask to join, you approve.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _public = widget.club.isPublic;
          _busy = false;
        });
      }
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Who can join', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Members stay in either way. Change it any time.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: 14),
              ClubJoinPolicyChoice(isPublic: _public, onChanged: _busy ? null : _pick),
            ],
          ),
        ),
      );
}
