import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart';
import '../../../core/widgets/thumb_image.dart';
import '../application/titi_controller.dart';
import '../domain/titi_message.dart';
import 'titi_text.dart';
import 'titi_thinking.dart';

/// Chat with TiTi, the app's assistant: meets, spots, clubs, app how-to and
/// car talk. Answers stream in as bubbles and cards; follow-up chips sit
/// under the latest one.
class TitiScreen extends ConsumerStatefulWidget {
  const TitiScreen({super.key});

  @override
  ConsumerState<TitiScreen> createState() => _TitiScreenState();
}

class _TitiScreenState extends ConsumerState<TitiScreen> {
  final _text = TextEditingController();

  static const _starters = ['Meets this weekend near me', 'Car cafés near me', 'How do points work?', 'Road tax renewal tips'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send([String? pick]) {
    final t = (pick ?? _text.text).trim();
    if (t.isEmpty || ref.read(titiControllerProvider).streaming) return;
    if (pick == null) _text.clear();
    ref.read(titiControllerProvider.notifier).send(t);
  }

  Future<void> _clear() async {
    final ok = await confirmSheet(context, title: 'Clear chat?', body: 'Your chat with TiTi is deleted from this account.', confirm: 'Clear', icon: AppIcons.trash);
    if (!ok) return;
    try {
      await ref.read(titiControllerProvider.notifier).clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(titiControllerProvider);
    final c = ref.read(titiControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        titleSpacing: 0,
        title: Row(
          children: [
            const TitiAvatar(TitiPose.chat, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TiTi', style: AppText.screenTitle),
                  Text(
                    s.streaming ? (s.thinking ? 'Thinking…' : 'Typing…') : 'Your pit crew · AI',
                    style: TextStyle(fontSize: 12, color: s.streaming ? AppColors.brand : AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (s.messages.isNotEmpty) IconButton(tooltip: 'Clear chat', icon: const Icon(AppIcons.trash), onPressed: s.streaming ? null : _clear),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body(s, c)),
          _Composer(controller: _text, streaming: s.streaming, onSend: _send, onStop: c.stop),
        ],
      ),
    );
  }

  Widget _body(TitiState s, TitiController c) {
    if (s.loading && s.messages.isEmpty) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (s.messages.isEmpty) {
      return _Empty(starters: _starters, onPick: _send, error: s.loadError, onReload: c.load);
    }

    // Oldest first, then drawn bottom-up (reverse) so new words keep the view pinned to the bottom.
    final last = s.messages.last;
    final rows = <Widget>[
      for (final m in s.messages)
        if (m.mine) _Mine(m.text, key: ValueKey(m.key)) else if (m.parts.isNotEmpty) _Answer(m, key: ValueKey(m.key)),
      if (s.streaming && s.thinking) TitiThinking(status: s.status, tool: s.tool),
      if (!s.streaming && !last.mine && last.error != null) _ErrorRow(text: last.error!, onRetry: c.retry),
      if (!s.streaming && last.mine) _ErrorRow(text: 'TiTi didn\'t answer that one.', onRetry: c.retry),
      if (!s.streaming && !last.mine && last.error == null && last.chips.isNotEmpty) _Chips(options: last.chips, onTap: _send),
    ];
    return ListView.builder(
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[rows.length - 1 - i],
    );
  }
}

// ------------------------------------------------------------- messages ---

double _maxBubble(BuildContext context) => math.min(MediaQuery.sizeOf(context).width * 0.78, 420);

class _Mine extends StatelessWidget {
  const _Mine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 40),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: _maxBubble(context)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surfaceGray,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4)),
            ),
            child: Text(text, style: TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.35)),
          ),
        ),
      );
}

/// One answer: TiTi at the bottom-left, his bubbles and cards stacked beside him.
class _Answer extends StatelessWidget {
  const _Answer(this.m, {super.key});
  final TitiMessage m;

  @override
  Widget build(BuildContext context) {
    final maxW = _maxBubble(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const TitiAvatar(TitiPose.chat, size: 30),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < m.parts.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == m.parts.length - 1 ? 0 : 5),
                    child: switch (m.parts[i]) {
                      TitiTextPart(:final text) => _Bubble(text: text, maxWidth: maxW, last: i == m.parts.length - 1),
                      TitiCardPart(:final card) => TitiCardTile(card, width: math.min(maxW, 300)),
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.maxWidth, required this.last});
  final String text;
  final double maxWidth;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomRight: const Radius.circular(18),
            bottomLeft: Radius.circular(last ? 4 : 18),
          ),
        ),
        child: TitiText(text.trim()),
      );
}

/// A meet, spot, club or car TiTi found: photo on the left, words on the right. Tap to open.
class TitiCardTile extends StatelessWidget {
  const TitiCardTile(this.card, {super.key, this.width = 280});
  final TitiCard card;
  final double width;

  static const _eyebrow = {'meet': 'MEET', 'spot': 'SPOT', 'club': 'CLUB', 'car': 'CAR'};

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(card.route),
          child: SizedBox(
            width: width,
            height: 76,
            child: Row(
              children: [
                SizedBox(width: 76, height: 76, child: _image()),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 8, 6, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_eyebrow[card.kind] ?? 'OPEN', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.brand)),
                        Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.textPrimary)),
                        if (card.subtitle.isNotEmpty)
                          Text(card.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, height: 1.25, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
                Padding(padding: const EdgeInsets.only(right: 8), child: Icon(AppIcons.caretRight, size: 15, color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
      );

  Widget _image() {
    final src = card.image;
    Widget fallback() => switch (card.kind) {
          'club' => Image.asset(crestAsset(card.id), fit: BoxFit.cover),
          'car' => const CarPlaceholder(),
          'spot' => _icon(kindIconAsset('other')),
          _ => Image.asset('assets/covers/meet.jpg', fit: BoxFit.cover),
        };
    if (src == null || src.isEmpty) return fallback();
    // Spot kinds are 3D icons: shown whole on grey, not cropped.
    if (src.startsWith('assets/kinds/')) return _icon(src);
    if (src.startsWith('assets/')) return Image.asset(src, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback());
    if (src.startsWith('https://')) return ThumbImage(src, error: fallback(), placeholder: ColoredBox(color: AppColors.surfaceGray));
    return fallback();
  }

  Widget _icon(String asset) => ColoredBox(
        color: AppColors.surfaceGray,
        child: Padding(padding: const EdgeInsets.all(14), child: Image.asset(asset, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink())),
      );
}

class _Chips extends StatelessWidget {
  const _Chips({required this.options, required this.onTap});
  final List<String> options;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 38, top: 2, bottom: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final o in options) _Chip(o, onTap: () => onTap(o))],
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.onTap});
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
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const TitiAvatar(TitiPose.sad, size: 30),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary))),
            TextButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.arrowsClockwise, size: 16), label: const Text('Retry')),
          ],
        ),
      );
}

// ---------------------------------------------------------------- empty ---

class _Empty extends StatelessWidget {
  const _Empty({required this.starters, required this.onPick, required this.onReload, this.error});
  final List<String> starters;
  final ValueChanged<String> onPick;
  final VoidCallback onReload;
  final String? error;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Titi(TitiPose.wave, height: 128),
              const SizedBox(height: 14),
              TitiBubble(
                'Hi, I\'m TiTi, your pit crew. Ask me about meets, spots, the app or your car.',
                dark: !AppColors.dark,
                maxWidth: 300,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [for (final t in starters) _Chip(t, onTap: () => onPick(t))],
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(onPressed: onReload, icon: const Icon(AppIcons.arrowsClockwise, size: 16), label: const Text('Load our chat')),
              ],
            ],
          ),
        ),
      );
}

// ------------------------------------------------------------- composer ---

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.streaming, required this.onSend, required this.onStop});
  final TextEditingController controller;
  final bool streaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, v, _) {
                final canSend = !streaming && v.text.trim().isNotEmpty;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        decoration: InputDecoration(
                          hintText: 'Ask TiTi anything…',
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.surfaceGray,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: AppColors.textMuted)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: streaming
                          ? _Round(key: const ValueKey('stop'), icon: AppIcons.stop, color: AppColors.textPrimary, iconColor: AppColors.onInk, tooltip: 'Stop', onTap: onStop)
                          : _Round(
                              key: const ValueKey('send'),
                              icon: AppIcons.paperPlaneRight,
                              color: canSend ? AppColors.brand : AppColors.surfaceGray,
                              iconColor: canSend ? Colors.white : AppColors.textMuted,
                              tooltip: 'Send',
                              onTap: canSend ? onSend : null,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
}

class _Round extends StatelessWidget {
  const _Round({super.key, required this.icon, required this.color, required this.iconColor, required this.tooltip, required this.onTap});
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: iconColor)),
          ),
        ),
      );
}
