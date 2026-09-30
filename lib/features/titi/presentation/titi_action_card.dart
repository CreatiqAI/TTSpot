import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/titi_actions.dart';
import '../application/titi_controller.dart';
import '../domain/titi_message.dart';
import 'titi_answer.dart' show TitiAppear, titiCardImage, titiMaxBubble;
import 'titi_text.dart';

/// Something TiTi offers to do: what it is (photo, title, detail) and one
/// clear button. Nothing happens until the member taps it; then the app does
/// it (runTitiAction) and the card says Done, with TiTi's follow-up line
/// under it. One-off actions also get "Not now".
class TitiActionCard extends ConsumerStatefulWidget {
  const TitiActionCard(this.action, {super.key, this.width = 300});
  final TitiAction action;
  final double width;

  @override
  ConsumerState<TitiActionCard> createState() => _TitiActionCardState();
}

class _TitiActionCardState extends ConsumerState<TitiActionCard> {
  var _busy = false;
  String? _error;

  static const _eyebrow = {
    'join_meet': 'JOIN MEET',
    'leave_meet': 'LEAVE MEET',
    'save_spot': 'SAVE SPOT',
    'directions': 'DIRECTIONS',
    'tt_here': 'TT HERE',
    'open_page': 'OPEN',
    'open_box': 'BLIND BOX',
    'claim_voucher': 'CLAIM VOUCHER',
  };

  static IconData _icon(String kind) => switch (kind) {
        'join_meet' => AppIcons.calendarCheck,
        'leave_meet' => AppIcons.signOut,
        'save_spot' => AppIcons.bookmarkSimple,
        'directions' => AppIcons.navigationArrow,
        'tt_here' => AppIcons.flag,
        'open_box' => AppIcons.gift,
        'claim_voucher' => AppIcons.ticket,
        _ => AppIcons.arrowRight,
      };

  Future<void> _run() async {
    final a = widget.action;
    if (_busy) return;
    // One-offs show a spinner; directions, TT here and pages open a sheet or page.
    if (!a.repeatable) setState(() => _busy = true);
    setState(() => _error = null);
    try {
      final route = await runTitiAction(context, ref, a);
      if (!a.repeatable) unawaited(ref.read(titiControllerProvider.notifier).markAction(a, TitiActionStatus.done, resultRoute: route));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  void _dismiss() => unawaited(ref.read(titiControllerProvider.notifier).markAction(widget.action, TitiActionStatus.dismissed));

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final done = a.status == TitiActionStatus.done;
    final skipped = a.status == TitiActionStatus.dismissed;
    final card = Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: done ? AppColors.brand.withValues(alpha: 0.45) : AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: a.route == null || a.kind == 'open_page' || a.kind == 'open_box' ? null : () => context.push(a.route!),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Row(
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 52, height: 52, child: titiCardImage(a.kind, a.target ?? a.id, a.image))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_eyebrow[a.kind] ?? 'TITI CAN', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.brand)),
                          Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.textPrimary)),
                          if (a.detail.isNotEmpty)
                            Text(a.detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, height: 1.25, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, thickness: 0.5, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: done
                    ? _DoneRow(key: const ValueKey('done'), resultRoute: a.resultRoute)
                    : skipped
                        ? Row(
                            key: const ValueKey('skipped'),
                            children: [Text('Skipped', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))],
                          )
                        : Row(
                            key: const ValueKey('open'),
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : _run,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.brand,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: AppColors.brand.withValues(alpha: 0.7),
                                    disabledForegroundColor: Colors.white,
                                    minimumSize: const Size(0, 40),
                                    shape: const StadiumBorder(),
                                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                  ),
                                  icon: _busy
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : Icon(_icon(a.kind), size: 17),
                                  label: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              ),
                              if (!a.repeatable) ...[
                                const SizedBox(width: 6),
                                TextButton(
                                  onPressed: _busy ? null : _dismiss,
                                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, minimumSize: const Size(0, 40)),
                                  child: const Text('Not now'),
                                ),
                              ],
                            ],
                          ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
              ),
          ],
        ),
      ),
    );

    final after = a.after;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        card,
        // TiTi's follow-up once it's done ("You're in. Want directions?").
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: done && after != null && after.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: TitiAppear(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: titiMaxBubble(context)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4)),
                      ),
                      child: TitiText(after),
                    ),
                  ),
                )
              : const SizedBox(width: 0, height: 0),
        ),
      ],
    );
  }
}

class _DoneRow extends StatelessWidget {
  const _DoneRow({super.key, this.resultRoute});
  final String? resultRoute;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Icon(AppIcons.checkCircleFill, size: 20, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('Done', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const Spacer(),
          if (resultRoute != null)
            TextButton.icon(
              onPressed: () => context.push(resultRoute!),
              icon: const Icon(AppIcons.qrCode, size: 16),
              label: const Text('Show QR'),
            ),
        ],
      );
}
