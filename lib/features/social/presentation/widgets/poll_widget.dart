import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../application/social_providers.dart';
import '../../domain/post.dart';

/// Threads-style poll: tap an option to vote; bars show results once voted or closed.
class PollWidget extends ConsumerWidget {
  const PollWidget({super.key, required this.feed});
  final FeedPost feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = feed.post;
    final options = p.pollOptions ?? const [];
    final showResults = feed.myVote != null || p.pollClosed;
    final results = showResults ? ref.watch(pollResultsProvider(p.id)).value ?? const <int, int>{} : const <int, int>{};
    final total = results.values.fold<int>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.title != null) ...[
          Text(p.title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3)),
          const SizedBox(height: 10),
        ],
        for (var i = 0; i < options.length; i++) ...[
          _Option(
            option: options[i],
            index: i,
            selected: feed.myVote == i,
            fraction: total == 0 ? 0 : (results[i] ?? 0) / total,
            showResults: showResults,
            onTap: p.pollClosed
                ? null
                : () async {
                    try {
                      await ref.read(socialActionsProvider).vote(feed, i);
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                    }
                  },
          ),
          const SizedBox(height: 8),
        ],
        Text(
          '${p.voteCount} ${p.voteCount == 1 ? 'vote' : 'votes'}${p.pollClosed ? ' · Final' : p.pollEndsAt == null ? '' : ' · ${_left(p.pollEndsAt!)} left'}',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  static String _left(DateTime end) {
    final d = end.difference(DateTime.now());
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inHours < 48) return '${d.inHours}h';
    return '${(d.inHours / 24).ceil()}d';
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.option, required this.index, required this.selected, required this.fraction, required this.showResults, required this.onTap});
  final PollOption option;
  final int index;
  final bool selected;
  final double fraction;
  final bool showResults;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: AppColors.surfaceRaised)),
            if (showResults)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: ColoredBox(color: selected ? AppColors.primary.withValues(alpha: 0.22) : AppColors.surfaceGray),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  if (option.photoUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image(image: CachedNetworkImageProvider(option.photoUrl!), width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 40, height: 40)),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(option.text, style: TextStyle(fontSize: 14.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500))),
                  if (showResults) Text('${(fraction * 100).round()}%', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if (selected) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(AppIcons.checkCircleFill, size: 18, color: AppColors.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
