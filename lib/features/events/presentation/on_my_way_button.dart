import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/directions/directions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/on_my_way.dart';
import '../domain/event.dart';

/// "I'm on my way" on a meet page: posts my ETA in the meet chat, offers
/// Undo, then directions.
class OnMyWayButton extends ConsumerStatefulWidget {
  const OnMyWayButton({super.key, required this.event});
  final Event event;

  @override
  ConsumerState<OnMyWayButton> createState() => _OnMyWayButtonState();
}

class _OnMyWayButtonState extends ConsumerState<OnMyWayButton> {
  bool _busy = false;

  Future<void> _go() async {
    final actions = ref.read(onMyWayActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    void snack(String msg, {SnackBarAction? action}) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action, duration: Duration(seconds: action == null ? 4 : 10)));

    setState(() => _busy = true);
    OnMyWayPost? post;
    try {
      post = await actions.post(widget.event);
    } catch (e) {
      snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (post == null || !mounted) return;
    final sent = post;

    Future<void> undo() async {
      try {
        await actions.undo(sent);
        snack('Taken back. It\'s gone from the meet chat.');
      } catch (e) {
        snack(friendlyError(e));
      }
    }

    final app = await rememberedDirectionsApp(ref);
    if (!mounted) return;
    final choice = await _postedSheet(context, sent, app: app);
    if (!mounted) return;
    if (choice == _Choice.undo) return undo();

    snack('Posted in the meet chat.', action: sent.messageId == null ? null : SnackBarAction(label: 'Undo', onPressed: undo));
    if (choice == _Choice.directions) {
      await openDirections(context, lat: widget.event.lat, lng: widget.event.lng, label: widget.event.venueName);
    }
  }

  @override
  Widget build(BuildContext context) => SecondaryButton(
        label: _busy ? 'Getting ETA…' : 'I\'m on my way',
        icon: _busy ? AppIcons.timer : AppIcons.car,
        onPressed: _busy ? null : _go,
      );
}

enum _Choice { undo, directions }

/// "Posted in the meet chat": the message, Undo, and the remembered app
/// ("Waze") or "Directions" (the chooser). Swiping it away keeps the message.
Future<_Choice?> _postedSheet(BuildContext context, OnMyWayPost post, {DirectionsApp? app}) => showModalBottomSheet<_Choice>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(AppIcons.checkCircleFill, color: AppColors.success, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Posted in the meet chat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(16)),
                child: Text(post.text, style: TextStyle(fontSize: 15, height: 1.35, color: AppColors.textPrimary)),
              ),
              if (post.estimate.estimated) ...[
                const SizedBox(height: 6),
                Text('Rough guess from the distance. Live traffic wasn\'t available.', style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: SecondaryButton(label: 'Undo', onPressed: post.messageId == null ? null : () => Navigator.pop(ctx, _Choice.undo))),
                  const SizedBox(width: 10),
                  // Short so it stays on one line at large text sizes.
                  Expanded(child: PrimaryButton(label: app?.label ?? 'Directions', icon: AppIcons.navigationArrow, onPressed: () => Navigator.pop(ctx, _Choice.directions))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
