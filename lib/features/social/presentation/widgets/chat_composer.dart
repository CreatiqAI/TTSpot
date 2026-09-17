import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import 'chat_media.dart' show fmtMs;

/// What the "+" sheet can start.
enum ComposerAction { photos, video, camera, location, meet, car, sticker }

/// The bottom bar of a chat: [+] [Message…] [camera] [mic].
/// Typing swaps the mic for Send. Tapping the mic swaps the whole row for a
/// "Hold to speak" bar; hold it to record, slide left to cancel, X to close.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onPlus,
    required this.onCamera,
    required this.recording,
    required this.cancelling,
    required this.elapsed,
    required this.onRecordStart,
    required this.onRecordMove,
    required this.onRecordEnd,
    this.hint = 'Message…',
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPlus;
  final VoidCallback onCamera;
  final bool recording;
  final bool cancelling;
  final Duration elapsed;
  final VoidCallback onRecordStart;
  final void Function(double dx) onRecordMove;
  final void Function({required bool send}) onRecordEnd;
  final String hint;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  bool _micBar = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: _micBar || widget.recording ? _voiceBar() : _textRow(),
          ),
        ),
      ),
    );
  }

  Widget _round(IconData icon, VoidCallback? onTap, {bool filled = false, String? tooltip}) => Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: filled ? AppColors.ink : AppColors.surfaceGray,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 20, color: filled ? Colors.white : AppColors.ink)),
          ),
        ),
      );

  Widget _textRow() {
    return ValueListenableBuilder<TextEditingValue>(
      key: const ValueKey('text'),
      valueListenable: widget.controller,
      builder: (_, v, _) {
        final typing = v.text.trim().isNotEmpty;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _round(AppIcons.plus, widget.sending ? null : widget.onPlus, tooltip: 'Attach'),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: widget.controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  filled: true,
                  fillColor: AppColors.surfaceGray,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: AppColors.textMuted)),
                ),
                onSubmitted: (_) => widget.onSend(),
              ),
            ),
            const SizedBox(width: 8),
            if (typing || widget.sending)
              Material(
                color: AppColors.brand,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.sending ? null : widget.onSend,
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: widget.sending
                        ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(AppIcons.paperPlaneRight, size: 20, color: Colors.white),
                  ),
                ),
              )
            else ...[
              _round(AppIcons.camera, widget.onCamera, tooltip: 'Camera'),
              const SizedBox(width: 8),
              _round(AppIcons.microphone, () => setState(() => _micBar = true), tooltip: 'Voice note'),
            ],
          ],
        );
      },
    );
  }

  Widget _voiceBar() {
    final rec = widget.recording;
    final cancel = widget.cancelling;
    return Row(
      key: const ValueKey('voice'),
      children: [
        _round(AppIcons.x, rec ? null : () => setState(() => _micBar = false), tooltip: 'Close'),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onLongPressStart: (_) => widget.onRecordStart(),
            onLongPressMoveUpdate: (d) => widget.onRecordMove(d.offsetFromOrigin.dx),
            onLongPressEnd: (_) {
              widget.onRecordEnd(send: !cancel);
              setState(() => _micBar = false);
            },
            onLongPressCancel: () {
              widget.onRecordEnd(send: false);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 46,
              decoration: BoxDecoration(
                color: rec ? (cancel ? AppColors.textSecondary : AppColors.brand) : AppColors.ink,
                borderRadius: BorderRadius.circular(23),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(cancel ? AppIcons.trash : AppIcons.microphone, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rec ? (cancel ? 'Release to cancel' : '${fmtMs(widget.elapsed.inMilliseconds)}  ·  slide left to cancel') : 'Hold to speak',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                  if (rec && !cancel)
                    const Padding(
                      padding: EdgeInsets.only(right: 14),
                      child: _Pulse(),
                    ),
                  if (!rec) const Padding(padding: EdgeInsets.only(right: 14), child: Text('2 min max', style: TextStyle(color: Colors.white54, fontSize: 11.5))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse();
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
        child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      );
}

/// The "+" sheet: big tiles, one tap each.
Future<ComposerAction?> showComposerSheet(BuildContext context) {
  return showModalBottomSheet<ComposerAction>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in const [
              (ComposerAction.photos, AppIcons.images, 'Photos'),
              (ComposerAction.video, AppIcons.record, 'Video'),
              (ComposerAction.camera, AppIcons.camera, 'Camera'),
              (ComposerAction.location, AppIcons.mapPin, 'Spot'),
              (ComposerAction.meet, AppIcons.flagCheckered, 'Meet'),
              (ComposerAction.car, AppIcons.car, 'My car'),
              (ComposerAction.sticker, AppIcons.smiley, 'Sticker'),
            ])
              SizedBox(
                width: (MediaQuery.sizeOf(ctx).width - 32 - 30) / 4,
                child: Column(
                  children: [
                    Material(
                      color: AppColors.surfaceGray,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(ctx, t.$1),
                        child: SizedBox(width: double.infinity, height: 68, child: Icon(t.$2, size: 26, color: AppColors.ink)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(t.$3, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
