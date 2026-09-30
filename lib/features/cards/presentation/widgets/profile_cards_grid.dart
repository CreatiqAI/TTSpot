import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../application/cards_providers.dart';
import '../../domain/cards.dart';
import 'card_face.dart';

/// The Cards tab on a profile: all 7 designs, owned ones in colour with a
/// count, missing ones greyed. Mine links to boxes and trades; a friend's
/// offers a trade; a stranger's suggests adding them first.
class ProfileCardsGrid extends ConsumerWidget {
  const ProfileCardsGrid({super.key, required this.userId, required this.isMe, required this.isFriend, this.onAddFriend});
  final String userId;
  final bool isMe;
  final bool isFriend;
  final VoidCallback? onAddFriend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(cardTypesProvider);
    final counts = isMe
        ? ref.watch(myCollectionProvider).whenData((c) => c.counts)
        : ref.watch(userCardCountsProvider(userId));
    final sealed = isMe ? ref.watch(sealedBoxesProvider) : const <CardBox>[];

    return types.when(
      loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e))),
      data: (all) {
        final active = all.where((t) => t.active).toList();
        final have = counts.value ?? const <String, int>{};
        final owned = active.where((t) => (have[t.id] ?? 0) > 0).length;
        final total = have.values.fold(0, (a, b) => a + b);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          owned == active.length && active.isNotEmpty ? 'Full set collected' : '$owned of ${active.length} collected',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(
                          total == 0 ? (isMe ? 'Open a box to get your first card.' : 'No cards yet.') : '$total card${total == 1 ? '' : 's'} in the collection',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (isMe)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: sealed.isNotEmpty ? AppColors.brand : AppColors.textPrimary,
                        foregroundColor: sealed.isNotEmpty ? Colors.white : AppColors.onInk,
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: () => context.push(sealed.isNotEmpty ? Routes.openBox(sealed.first.id) : Routes.cards),
                      icon: Icon(sealed.isNotEmpty ? AppIcons.gift : AppIcons.handshake, size: 16),
                      label: Text(sealed.isNotEmpty ? 'Open box${sealed.length > 1 ? ' (${sealed.length})' : ''}' : 'Trade & prizes'),
                    )
                  else if (isFriend)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.textPrimary, foregroundColor: AppColors.onInk, visualDensity: VisualDensity.compact, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: () => context.push(Routes.newTradeWith(userId)),
                      icon: const Icon(AppIcons.handshake, size: 16),
                      label: const Text('Trade'),
                    )
                  else if (onAddFriend != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: onAddFriend,
                      icon: const Icon(AppIcons.userPlus, size: 16),
                      label: const Text('Add to trade'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (_, c) {
                  const gap = 10.0;
                  final w = (c.maxWidth - gap * 3) / 4;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap + 4, // room for the ×N badge hanging off each card
                    children: [
                      for (final t in active)
                        GestureDetector(
                          onTap: isMe ? () => context.push(Routes.cards) : null,
                          child: CardFace(card: t, width: w, count: have[t.id], locked: (have[t.id] ?? 0) == 0),
                        ),
                    ],
                  );
                },
              ),
              if (!isMe && !isFriend && total > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const ArtIcon(AppArt.handshake, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Cards trade between friends. Add them and you can swap.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
