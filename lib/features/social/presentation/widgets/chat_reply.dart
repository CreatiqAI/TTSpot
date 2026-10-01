import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../events/application/event_providers.dart';
import '../../../profile/application/profile_providers.dart';
import '../../application/chat_providers.dart';
import '../../application/community_providers.dart';
import '../../domain/chat.dart';
import 'chat_media.dart' show fmtMs;

/// Swipe a message to the right to reply, WhatsApp style: the bubble follows
/// the finger, a reply arrow fades in behind it, there's a haptic tick once
/// it's far enough, and letting go past that point calls [onReply].
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.child, required this.onReply, this.enabled = true});
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  /// How far (logical px) the bubble has to travel before a release replies.
  static const threshold = 64.0;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  static const _max = 96.0;
  double _dx = 0;
  double _releasedAt = 0;
  bool _armed = false;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() => _dx = _releasedAt * (1 - Curves.easeOut.transform(_back.value))));

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    // Past the threshold the bubble drags heavier, so it reads as "that's enough".
    final k = _dx >= SwipeToReply.threshold ? 0.35 : 0.85;
    final next = (_dx + d.delta.dx * k).clamp(0.0, _max);
    setState(() => _dx = next);
    if (!_armed && next >= SwipeToReply.threshold) {
      _armed = true;
      HapticFeedback.selectionClick();
    } else if (_armed && next < SwipeToReply.threshold) {
      _armed = false;
    }
  }

  void _release() {
    if (_armed) widget.onReply();
    _armed = false;
    _releasedAt = _dx;
    if (_dx > 0) _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final p = (_dx / SwipeToReply.threshold).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _back.stop(),
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: (_) => _release(),
      onHorizontalDragCancel: _release,
      child: Stack(
        children: [
          Positioned(
            left: 2,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: p,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * p,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
                    child: Icon(AppIcons.arrowBendUpLeft, size: 17, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// Accent of a quote: "You" in green, everyone else in the brand red.
Color replyAccent({required bool mine}) => mine ? AppColors.success : AppColors.brand;

/// The quoted message: a coloured bar, who sent it, one line of what it was,
/// a thumbnail for a photo or video. Used at the top of a reply bubble and,
/// with a close button as [trailing], above the composer.
/// When [original] is null the quote reads "Original message unavailable".
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({super.key, required this.original, required this.name, required this.mine, this.onTap, this.trailing, this.background, this.loading = false});
  final Message? original;
  final String name;
  final bool mine;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? background;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final o = original;
    final accent = o == null ? AppColors.textMuted : replyAccent(mine: mine);
    final thumb = o == null ? null : _thumb(o);
    return Material(
      color: background ?? AppColors.textPrimary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (o != null) Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: accent)),
                      if (o != null)
                        ReplySnippet(message: o)
                      else
                        Text(
                          loading ? 'Loading…' : 'Original message unavailable',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
              if (thumb != null) SizedBox(width: 44, child: thumb),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  static Widget? _thumb(Message m) {
    if (m.imageUrl != null) return Image(image: CachedNetworkImageProvider(m.imageUrl!), fit: BoxFit.cover);
    if (m.videoUrl != null) {
      return const ColoredBox(color: Color(0xFF2A2D33), child: Center(child: Icon(AppIcons.playFill, size: 16, color: Colors.white)));
    }
    return null;
  }
}

/// One line saying what a message was: "Photo", "Voice note 0:07", "Video",
/// "Sticker", "Meet: Friday TT" or the text itself.
class ReplySnippet extends ConsumerWidget {
  const ReplySnippet({super.key, required this.message});
  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = message;
    final typed = m.autoBody ? null : m.body;
    final (IconData? icon, String text) = switch (m) {
      _ when m.imageUrl != null => (AppIcons.camera, typed ?? 'Photo'),
      _ when m.audioUrl != null => (AppIcons.microphone, 'Voice note ${fmtMs(m.audioMs ?? 0)}'),
      _ when m.videoUrl != null => (AppIcons.videoCamera, typed ?? 'Video'),
      _ when m.sticker != null => (AppIcons.smiley, 'Sticker'),
      _ when m.eventId != null => (AppIcons.flagCheckered, 'Meet: ${ref.watch(eventDetailProvider(m.eventId!)).value?.event.title ?? '…'}'),
      _ when m.placeId != null => (AppIcons.mapPin, 'Spot: ${ref.watch(placeProvider(m.placeId!)).value?.name ?? '…'}'),
      _ when m.carId != null => (AppIcons.car, () {
          final c = ref.watch(carProvider(m.carId!)).value;
          return c == null ? 'Car' : 'Car: ${c.make} ${c.model}';
        }()),
      _ when m.postId != null => (AppIcons.image, typed ?? 'Post'),
      _ when m.storyId != null => (AppIcons.image, typed ?? 'Moment'),
      _ => (null, m.body.replaceAll('\n', ' ')),
    };
    final style = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: AppColors.textSecondary), const SizedBox(width: 4)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      ],
    );
  }
}

/// The quote at the top of a reply. Finds the original in the loaded page
/// ([loaded]); if it's older than that, fetches it once. A deleted original,
/// or one from someone you blocked, reads "Original message unavailable".
class ReplyQuoteFor extends ConsumerWidget {
  const ReplyQuoteFor({super.key, required this.replyToId, required this.loaded, required this.nameOf, required this.isMine, required this.hidden, this.onTap});
  final String replyToId;
  final Message? loaded;
  final String Function(Message original) nameOf;
  final bool Function(Message original) isMine;
  final bool Function(Message original) hidden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fetched = loaded == null ? ref.watch(chatMessageProvider(replyToId)) : null;
    var o = loaded ?? fetched?.value;
    if (o != null && hidden(o)) o = null;
    return ReplyQuote(
      original: o,
      name: o == null ? '' : nameOf(o),
      mine: o != null && isMine(o),
      loading: o == null && (fetched?.isLoading ?? false),
      onTap: onTap,
    );
  }
}

/// "Replying to …" above the composer, with an X to drop the reply.
class ReplyComposerStrip extends StatelessWidget {
  const ReplyComposerStrip({super.key, required this.original, required this.name, required this.mine, required this.onCancel});
  final Message original;
  final String name;
  final bool mine;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: ReplyQuote(
          original: original,
          name: name,
          mine: mine,
          background: AppColors.surfaceGray,
          trailing: SizedBox(
            width: 40,
            child: IconButton(
              tooltip: 'Cancel reply',
              padding: EdgeInsets.zero,
              icon: Icon(AppIcons.x, size: 18, color: AppColors.textSecondary),
              onPressed: onCancel,
            ),
          ),
        ),
      );
}
