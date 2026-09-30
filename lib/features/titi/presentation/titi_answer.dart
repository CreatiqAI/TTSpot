import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/thumb_image.dart';
import '../domain/titi_message.dart';
import 'titi_action_card.dart';
import 'titi_text.dart';
import 'titi_thinking.dart';

double titiMaxBubble(BuildContext context) => math.min(MediaQuery.sizeOf(context).width * 0.78, 420);

/// One answer: TiTi at the bottom-left, his bubbles, cards and action cards
/// stacked beside him, and (on the latest answer) the follow-up chips or the
/// error with Retry.
///
/// While it streams ([TitiMessage.live]) only this widget redraws: the
/// words go into a buffer and a ticker types them out at a calm, even pace
/// (fractions of a letter per frame, the newest letters inking in), a little
/// faster only when a long backlog builds up, so text flows instead of
/// landing in chunks. Bubbles, cards and chips come strictly in order, each
/// once the text before it has typed out, and the thinking bubble fades out
/// as the first words appear. The time shows on the last bubble once done.
class TitiAnswer extends StatefulWidget {
  const TitiAnswer(this.m, {super.key, required this.latest, required this.onChip, required this.onRetry});
  final TitiMessage m;

  /// The latest answer, with nothing streaming after it: chips and errors show.
  final bool latest;
  final ValueChanged<String> onChip;
  final VoidCallback onRetry;

  @override
  State<TitiAnswer> createState() => _TitiAnswerState();
}

class _TitiAnswerState extends State<TitiAnswer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  TitiLive? _live;

  /// The pace, in letters a second: a steady [_rate] (smoothness over speed),
  /// easing up to twice that only while more than [_rampFrom] letters wait,
  /// fully at [_rampTo]. The model is faster than this, so a long answer keeps
  /// flowing after the stream has ended.
  static const _rate = 42.0;
  static const _rampFrom = 300.0;
  static const _rampTo = 600.0;

  @override
  void initState() {
    super.initState();
    _attach(widget.m.live);
  }

  @override
  void didUpdateWidget(TitiAnswer old) {
    super.didUpdateWidget(old);
    if (old.m.live != widget.m.live) {
      _detach();
      _attach(widget.m.live);
    }
  }

  @override
  void dispose() {
    _detach();
    _ticker.dispose();
    super.dispose();
  }

  void _attach(TitiLive? live) {
    if (live == null || live.revealed) return;
    if (live.done) {
      // Came back (or scrolled back) after it finished: all of it, at once.
      live.shown = live.total;
      live.markRevealed();
      return;
    }
    _live = live..addListener(_changed);
    _wake();
  }

  void _detach() {
    _live?.removeListener(_changed);
    _live = null;
    if (_ticker.isActive) _ticker.stop();
  }

  void _changed() {
    if (!mounted) return;
    _wake();
    setState(() {});
  }

  void _wake() {
    if (_live == null || _live!.revealed || _ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final live = _live;
    if (live == null) return;
    final dt = _last == Duration.zero ? 1 / 60 : math.min((elapsed - _last).inMicroseconds / 1e6, 0.05);
    _last = elapsed;
    final total = live.total;
    final backlog = total - live.shown;
    if (backlog <= 0.01) {
      live.shown = total;
      _ticker.stop();
      if (live.done) {
        _detach();
        live.markRevealed();
        if (mounted) setState(() {});
      }
      return;
    }
    final boost = ((backlog - _rampFrom) / (_rampTo - _rampFrom)).clamp(0.0, 1.0);
    live.shown = math.min(total, live.shown + _rate * (1 + boost) * dt);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final live = m.live;
    final maxW = titiMaxBubble(context);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final typing = live != null && !live.revealed && !still;
    final parts = live != null ? live.parts : m.parts;
    final cursor = typing ? live.shown : double.infinity;
    final settled = live == null || live.revealed || still;
    // The time goes on the last text bubble, once the answer is done.
    final time = settled && m.at != null ? formatTime(m.at!) : null;
    final timeAt = time == null ? -1 : parts.lastIndexWhere((p) => p is TitiTextPart);

    // What the typing has reached so far.
    final shown = <Widget>[];
    var at = 0.0;
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      if (cursor <= at) break;
      final units = TitiLive.unitsOf(p);
      final whole = cursor >= at + units;
      final isLast = i == parts.length - 1 && whole;
      final into = cursor - at; // letters of this part typed so far
      final Widget child = switch (p) {
        TitiTextPart(:final text) => whole
            ? _Bubble(text: text, maxWidth: maxW, tail: isLast, time: i == timeAt ? time : null)
            // The newest letter is [into]'s fraction of the way in.
            : _Bubble(text: _cut(text, into.ceil()), maxWidth: maxW, tail: false, fade: into - into.ceil() + 1),
        TitiCardPart(:final card) => TitiCardTile(card, width: math.min(maxW, 300)),
        TitiActionPart(:final action) => TitiActionCard(action, width: math.min(maxW, 300)),
      };
      shown.add(Padding(
        key: ValueKey('p$i'),
        padding: EdgeInsets.only(top: shown.isEmpty ? 0 : 5),
        // Streamed pieces fade and slide in; history just sits there.
        child: live != null ? _Appear(child: child) : child,
      ));
      at += units;
    }

    // TiTi is thinking (the start, or a tool running) once the typing has caught up.
    final caughtUp = !typing || live.shown >= live.total - 0.5;
    final thinking = live != null && !live.done && (live.waiting || shown.isEmpty) && caughtUp;
    final error = live?.error ?? m.error;

    final answer = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 32,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: thinking
                ? TitiHop(key: const ValueKey('hop'), pose: titiPoseFor(live.tool), size: 32)
                : const TitiAvatar(TitiPose.chat, key: ValueKey('still'), size: 32),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...shown,
              // Cards only, no words: the time sits under them.
              if (time != null && timeAt < 0 && shown.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: TitiTime(time)),
              // The thinking bubble fades and folds away as the words come.
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                  child: thinking
                      ? Padding(
                          key: const ValueKey('thinking'),
                          padding: EdgeInsets.only(top: shown.isEmpty ? 0 : 5),
                          child: TitiThinkingBubble(status: live.status),
                        )
                      : const SizedBox(key: ValueKey('none')),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final after = <Widget>[
      if (widget.latest && settled && error != null) _ErrorRow(text: error, onRetry: widget.onRetry),
      if (widget.latest && settled && error == null && (live?.chips ?? m.chips).isNotEmpty)
        live != null ? _Appear(child: _Chips(options: live.chips, onTap: widget.onChip)) : _Chips(options: m.chips, onTap: widget.onChip),
    ];

    final body = Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 24),
      child: after.isEmpty ? answer : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [answer, ...after]),
    );
    // A streamed answer tells the list when it grows, so the list can follow.
    return live != null ? SizeChangedLayoutNotifier(child: body) : body;
  }

  /// The first [n] characters, never splitting an emoji or leaving a lone
  /// "*" that is about to become "**".
  static String _cut(String s, int n) {
    if (n >= s.length) return s;
    var k = n;
    if (k > 0 && s.codeUnitAt(k - 1) >= 0xD800 && s.codeUnitAt(k - 1) <= 0xDBFF) k--;
    while (k > 0 && s[k - 1] == '*') {
      k--;
    }
    return s.substring(0, k);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.maxWidth, required this.tail, this.time, this.fade});
  final String text;
  final double maxWidth;
  final bool tail;

  /// "9:41 PM", tucked into the bottom-right corner.
  final String? time;

  /// While typing: how far the newest letter is in (see [TitiText.fade]).
  final double? fade;

  @override
  Widget build(BuildContext context) {
    final t = time;
    final words = TitiText(text.trim(), fade: fade, trailing: t == null ? null : titiTimeRoom(context, t));
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomRight: const Radius.circular(18),
          bottomLeft: Radius.circular(tail ? 4 : 18),
        ),
      ),
      child: t == null ? words : Stack(children: [words, Positioned(right: 0, bottom: 0, child: TitiTime(t))]),
    );
  }
}

// ----------------------------------------------------------------- time ---

TextStyle _timeStyle(Color? color) => TextStyle(fontSize: 11, height: 1.2, color: color ?? AppColors.textSecondary);

/// A message's time, WhatsApp style: small, secondary, one line.
class TitiTime extends StatelessWidget {
  const TitiTime(this.time, {super.key, this.color});
  final String time;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(time, maxLines: 1, softWrap: false, style: _timeStyle(color));
}

/// The room a [TitiTime] needs at the end of a bubble's last line (at the
/// phone's text size), plus a gap before it.
Size titiTimeRoom(BuildContext context, String time) {
  final p = TextPainter(
    text: TextSpan(text: time, style: _timeStyle(null)),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final size = Size(p.width + 8, p.height);
  p.dispose();
  return size;
}

/// "Today", "Yesterday" or "Mon, 28 Sep", in a small centred pill between days.
class TitiDayPill extends StatelessWidget {
  const TitiDayPill(this.day, {super.key});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = DateUtils.dateOnly(now).difference(DateUtils.dateOnly(day)).inDays;
    final label = diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : formatDate(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
      ),
    );
  }
}

/// Fades and slides a new piece in once, on its first build.
class _Appear extends StatefulWidget {
  const _Appear({required this.child});
  final Widget child;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
}

/// Fades and slides in whatever it wraps the first time it builds. For new
/// messages in the chat list.
class TitiAppear extends StatelessWidget {
  const TitiAppear({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => _Appear(child: child);
}

/// A meet, spot, club, car, voucher or deal TiTi found: photo on the left,
/// words on the right. Tap to open.
class TitiCardTile extends StatelessWidget {
  const TitiCardTile(this.card, {super.key, this.width = 280});
  final TitiCard card;
  final double width;

  static const _eyebrow = {'meet': 'MEET', 'spot': 'SPOT', 'club': 'CLUB', 'car': 'CAR', 'voucher': 'MY VOUCHER', 'offer': 'DEAL'};

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(card.route),
          // Sized by its content (no fixed height): the photo is a fixed
          // square, the words wrap and grow with the phone's text size.
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 60, height: 60, child: _image())),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_eyebrow[card.kind] ?? 'OPEN', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.brand)),
                        Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.textPrimary)),
                        if (card.subtitle.isNotEmpty)
                          Text(card.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, height: 1.25, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Padding(padding: const EdgeInsets.only(left: 4), child: Icon(AppIcons.caretRight, size: 15, color: AppColors.textMuted)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _image() => titiCardImage(card.kind, card.id, card.image);
}

/// A card's picture: a photo, a bundled cover, or the kind's own art.
Widget titiCardImage(String kind, String id, String? src) {
  Widget icon(String asset) => ColoredBox(
        color: AppColors.surfaceGray,
        child: Padding(padding: const EdgeInsets.all(14), child: Image.asset(asset, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink())),
      );
  Widget fallback() => switch (kind) {
        'club' => Image.asset(crestAsset(id), fit: BoxFit.cover),
        'car' => const CarPlaceholder(),
        'spot' || 'save_spot' || 'tt_here' || 'directions' => icon(kindIconAsset('other')),
        'voucher' || 'offer' || 'claim_voucher' => icon('assets/vouchers/voucher.png'),
        _ => Image.asset('assets/covers/meet.jpg', fit: BoxFit.cover),
      };
  if (src == null || src.isEmpty) return fallback();
  // Spot kinds, vouchers and TiTi's box are 3D icons: shown whole on grey, not cropped.
  if (src.startsWith('assets/kinds/') || src.startsWith('assets/vouchers/') || src.startsWith('assets/titi/')) return icon(src);
  if (src.startsWith('assets/')) return Image.asset(src, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback());
  if (src.startsWith('https://')) return ThumbImage(src, error: fallback(), placeholder: ColoredBox(color: AppColors.surfaceGray));
  return fallback();
}

class _Chips extends StatelessWidget {
  const _Chips({required this.options, required this.onTap});
  final List<String> options;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 40, top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final o in options) TitiChip(o, onTap: () => onTap(o))],
        ),
      );
}

/// A follow-up or starter question to tap.
class TitiChip extends StatelessWidget {
  const TitiChip(this.text, {super.key, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: AppColors.brand.withValues(alpha: AppColors.dark ? 0.55 : 0.35))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ),
      );
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TitiErrorRow(text: text, onRetry: onRetry),
      );
}

/// "TiTi didn't answer" with Retry.
class TitiErrorRow extends StatelessWidget {
  const TitiErrorRow({super.key, required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const TitiAvatar(TitiPose.sad, size: 32),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary))),
          TextButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.arrowsClockwise, size: 16), label: const Text('Retry')),
        ],
      );
}
