import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/consent/ai_consent.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/thumb_image.dart';
import '../../../profile/domain/car.dart';
import '../../application/share_ride.dart';

/// Points for a first post, as the card words it: point_rules 'weekly_post'
/// (+10 for the first post of each points week, 20261006000108).
const kFirstPostPoints = 10;

/// "Share your ride" where it belongs (top of For you, my empty Posts tab):
/// shows itself only when [shareRideCarProvider] has a car for me, then the
/// thank-you after "Post it" until Done.
class ShareRideNudge extends ConsumerWidget {
  const ShareRideNudge({super.key, this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 8), this.hasPosts = false, this.openPost});
  final EdgeInsets padding;

  /// The screen already knows I have posts (my Posts tab): only the thank-you can show.
  final bool hasPosts;

  /// Opens the new post (default: its page). Tests swap it.
  final void Function(BuildContext context, String postId)? openPost;

  void _open(BuildContext context, String id) => openPost != null ? openPost!(context, id) : context.push(Routes.post(id));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shareRideControllerProvider);
    if (s.closed) return const SizedBox.shrink();
    final ctrl = ref.read(shareRideControllerProvider.notifier);
    final posted = s.posted;
    if (posted != null) {
      return Padding(
        padding: padding,
        child: ShareRideCard(
          car: posted.car,
          done: true,
          onPost: () => _open(context, posted.postId),
          onNotNow: ctrl.close,
        ),
      );
    }
    if (hasPosts) return const SizedBox.shrink();
    final car = ref.watch(shareRideCarProvider).value;
    if (car == null) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: ShareRideCard(
        car: car,
        busy: s.busy,
        error: s.error,
        onPost: () async {
          // First post: the note on the automated safety check (OpenAI).
          if (!await ensureAiConsent(context, ref, AiConsentKind.safety)) return;
          final id = await ctrl.post(car);
          if (id != null && context.mounted) _open(context, id);
        },
        onNotNow: ctrl.notNow,
      ),
    );
  }
}

/// The card itself: my car's photo, the offer, "Post it" and a small "Not
/// now"; with [done] it thanks me and offers "View post" and "Done".
class ShareRideCard extends StatelessWidget {
  const ShareRideCard({super.key, required this.car, required this.onPost, required this.onNotNow, this.busy = false, this.done = false, this.error});
  final Car car;
  final VoidCallback onPost;
  final VoidCallback onNotNow;
  final bool busy;
  final bool done;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final photo = car.photoUrls.isEmpty ? null : car.photoUrls.first;
    return Container(
      key: const Key('share-ride-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: photo == null ? ColoredBox(color: AppColors.surfaceGray) : ThumbImage(photo, error: ColoredBox(color: AppColors.surfaceGray)),
                    ),
                    if (done)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                          child: const Icon(AppIcons.check, size: 13, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done ? 'Your ride is up' : 'Share your ride',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const PointsCoin(size: 16),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            done ? 'Your $kFirstPostPoints points are on the way' : 'Your first post earns $kFirstPostPoints points',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, height: 1.3, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('share-ride-post'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 12)),
                  onPressed: busy ? null : onPost,
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(done ? 'View post' : 'Post it', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                key: const Key('share-ride-not-now'),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: busy ? null : onNotNow,
                child: Text(done ? 'Done' : 'Not now', maxLines: 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
