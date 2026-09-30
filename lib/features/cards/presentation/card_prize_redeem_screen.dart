import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/cards_providers.dart';
import '../domain/cards.dart';

/// Counter side, after scanning a member's prize QR: who they are, what they
/// won, then "Hand it over". Partners see only their own prizes; admins see all.
class CardPrizeRedeemScreen extends ConsumerStatefulWidget {
  const CardPrizeRedeemScreen({super.key, required this.claimId, required this.code});
  final String claimId;
  final String code;

  @override
  ConsumerState<CardPrizeRedeemScreen> createState() => _CardPrizeRedeemScreenState();
}

class _CardPrizeRedeemScreenState extends ConsumerState<CardPrizeRedeemScreen> {
  late Future<CardClaimLookup> _lookup;
  final _note = TextEditingController();
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _lookup = ref.read(cardsActionsProvider).lookup(claimId: widget.claimId, code: widget.code);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    setState(() => _busy = true);
    try {
      await ref.read(cardsActionsProvider).redeem(claimId: widget.claimId, code: widget.code, note: _note.text.trim().isEmpty ? null : _note.text.trim());
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Prize pickup'),
      ),
      body: FutureBuilder<CardClaimLookup>(
        future: _lookup,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(snap.error!), textAlign: TextAlign.center)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          final c = snap.data!;
          if (_done) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ArtIcon(AppArt.confetti, size: 72),
                    const SizedBox(height: 16),
                    Text('Handed over', style: AppText.sectionTitle),
                    const SizedBox(height: 6),
                    Text('${c.title} for ${c.displayName ?? '@${c.username}'}. They get a note in the app.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
                  ],
                ),
              ),
            );
          }
          final ready = c.status == ClaimState.active;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Row(
                children: [
                  UserAvatar(url: c.avatarUrl, name: c.displayName ?? c.username, seed: c.userId, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.displayName ?? '@${c.username}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        if (c.username != null) Text('@${c.username}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: ready ? AppColors.ink : AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ready ? Colors.white : AppColors.textPrimary)),
                    if (c.description != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.description!, style: TextStyle(fontSize: 13.5, color: ready ? Colors.white70 : AppColors.textSecondary, height: 1.4))),
                    const SizedBox(height: 8),
                    Text(
                      ready ? 'Paid with ${c.cardsUsed} card${c.cardsUsed == 1 ? '' : 's'} · valid till ${formatDate(c.expiresAt)}' : c.status.label + (c.redeemedAt == null ? '' : ' ${timeAgo(c.redeemedAt!)}'),
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ready ? Colors.white : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (c.terms != null) ...[
                const SizedBox(height: 12),
                Text('TERMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(c.terms!, style: const TextStyle(fontSize: 13, height: 1.4)),
              ],
              if (ready) ...[
                const SizedBox(height: 16),
                TextField(controller: _note, decoration: const InputDecoration(hintText: 'Note (optional)')),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: PrimaryButton(label: 'Hand it over', loading: _busy, onPressed: _redeem)),
                const SizedBox(height: 8),
                Text('Tap once the prize is in their hands. This cannot be undone.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ] else ...[
                const SizedBox(height: 16),
                Text(
                  switch (c.status) {
                    ClaimState.redeemed => 'This prize was already handed over.',
                    ClaimState.expired => 'This claim ran out. The member got their cards back and can claim again.',
                    _ => 'This claim is no longer valid.',
                  },
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
