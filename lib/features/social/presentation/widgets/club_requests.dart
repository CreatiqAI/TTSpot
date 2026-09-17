import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../application/community_providers.dart';
import '../../domain/club.dart';

/// "Request to join" for people outside the club, with the pending / declined
/// states after. Owners and admins see the queue in [ClubRequestsSection].
class JoinRequestButton extends ConsumerStatefulWidget {
  const JoinRequestButton({super.key, required this.clubId, required this.clubName});
  final String clubId;
  final String clubName;
  @override
  ConsumerState<JoinRequestButton> createState() => _JoinRequestButtonState();
}

class _JoinRequestButtonState extends ConsumerState<JoinRequestButton> {
  bool _busy = false;

  Future<void> _ask() async {
    final ctrl = TextEditingController();
    final send = await showModalBottomSheet<bool>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Join ${widget.clubName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('The club owner and admins decide. A line about you and your car helps.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 200,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. Myvi daily, TTDI regular, saw you guys at Sunway…'),
            ),
            const SizedBox(height: 8),
            PrimaryButton(label: 'Send request', onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ),
    );
    if (send != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(communityActionsProvider).requestClubJoin(widget.clubId, ctrl.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent. You\'ll hear back in Activity.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel your request?'),
        content: Text('${widget.clubName} has not answered yet. You can ask again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep waiting')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel request')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(communityActionsProvider).cancelClubRequest(widget.clubId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(myClubRequestProvider(widget.clubId)).value;
    return switch (status) {
      'pending' => SecondaryButton(label: 'Requested', icon: AppIcons.clock, onPressed: _busy ? null : _cancel),
      'declined' => const SecondaryButton(label: 'Not this time', icon: AppIcons.xCircle, onPressed: null),
      _ => PrimaryButton(label: 'Request to join', loading: _busy, onPressed: _busy ? null : _ask),
    };
  }
}

/// Pending requests with Approve / Decline. Only rendered for managers.
class ClubRequestsSection extends ConsumerWidget {
  const ClubRequestsSection({super.key, required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(clubJoinRequestsProvider(clubId)).value ?? const <ClubJoinRequest>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('WANT TO JOIN · ${list.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
        ),
        for (final r in list) _RequestRow(r: r, clubId: clubId),
      ],
    );
  }
}

class _RequestRow extends ConsumerStatefulWidget {
  const _RequestRow({required this.r, required this.clubId});
  final ClubJoinRequest r;
  final String clubId;
  @override
  ConsumerState<_RequestRow> createState() => _RequestRowState();
}

class _RequestRowState extends ConsumerState<_RequestRow> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    try {
      await ref.read(communityActionsProvider).reviewClubRequest(widget.r.id, clubId: widget.clubId, approve: approve);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(onTap: () => context.push(Routes.profile(r.userId)), child: UserAvatar(url: r.avatarUrl, name: r.displayName ?? r.username, size: 40)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.displayName ?? r.username ?? 'Member', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('@${r.username ?? ''} · ${timeAgo(r.createdAt)}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if ((r.message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('“${r.message!.trim()}”', style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(onPressed: _busy ? null : () => _decide(false), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: AppColors.surface), child: const Text('Decline')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton(onPressed: _busy ? null : () => _decide(true), style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: AppColors.textPrimary, foregroundColor: AppColors.onInk), child: const Text('Approve')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
