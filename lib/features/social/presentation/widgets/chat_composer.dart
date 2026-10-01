import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import 'voice_recorder.dart';

/// What the "+" sheet can start.
enum ComposerAction { photos, video, camera, location, meet, car, sticker }

/// The bottom bar of a chat: [+] [Message…] [camera] [mic].
/// Typing swaps the mic for Send. The mic works like WhatsApp's: tap it to
/// record hands-free (the bar becomes trash / pause / send), or hold it and
/// let go to send, sliding left to cancel or up to lock. [header] (the reply
/// being written) sits above the row.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onPlus,
    required this.onCamera,
    required this.recorder,
    this.hint = 'Message…',
    this.header,
    this.focusNode,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPlus;
  final VoidCallback onCamera;
  final VoiceRecorder recorder;
  final String hint;
  final Widget? header;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?header,
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: ListenableBuilder(
                listenable: recorder,
                builder: (context, _) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: recorder.locked ? VoiceLockedBar(key: const ValueKey('locked'), recorder: recorder) : _row(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _round(IconData icon, VoidCallback? onTap, {String? tooltip}) => Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: AppColors.surfaceGray,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 20, color: AppColors.textPrimary)),
          ),
        ),
      );

  Widget _row() {
    return ValueListenableBuilder<TextEditingValue>(
      key: const ValueKey('row'),
      valueListenable: controller,
      builder: (_, v, _) {
        final holding = recorder.holding;
        final typing = v.text.trim().isNotEmpty && !holding;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: holding
                    ? VoiceHoldStrip(key: const ValueKey('hold'), recorder: recorder)
                    : Row(
                        key: const ValueKey('text'),
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _round(AppIcons.plus, sending ? null : onPlus, tooltip: 'Attach'),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              focusNode: focusNode,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: hint,
                                filled: true,
                                fillColor: AppColors.surfaceGray,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: AppColors.textMuted)),
                              ),
                              onSubmitted: (_) => onSend(),
                            ),
                          ),
                          if (!typing && !sending) ...[
                            const SizedBox(width: 8),
                            _round(AppIcons.camera, onCamera, tooltip: 'Camera'),
                          ],
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 8),
            if (typing || sending)
              Material(
                color: AppColors.brand,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: sending ? null : onSend,
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: sending
                        ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(AppIcons.paperPlaneRight, size: 20, color: Colors.white),
                  ),
                ),
              )
            else
              VoiceMicButton(recorder: recorder),
          ],
        );
      },
    );
  }
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
                        child: SizedBox(width: double.infinity, height: 68, child: Icon(t.$2, size: 26, color: AppColors.textPrimary)),
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
