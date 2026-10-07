import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/router/pop_or_home.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../events/application/event_providers.dart';
import '../application/floorplan_providers.dart';
import '../data/floorplan_repository.dart';
import '../domain/floorplan.dart';

final _inviteCodeProvider = FutureProvider.autoDispose.family<String, String>((ref, eventId) => ref.watch(floorplanRepositoryProvider).inviteCode(eventId));
final _linkedCountProvider = FutureProvider.autoDispose.family<int, String>((ref, eventId) => ref.watch(floorplanRepositoryProvider).linkedCount(eventId));

/// Host: a big QR that brings people without the app into TT Spot and links
/// them to this event, so the organizer can reach them during the meet.
/// Members who already have the app can scan it too: it opens the event.
class EventInviteScreen extends ConsumerWidget {
  const EventInviteScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(isMeetHostProvider(eventId));
    final title = ref.watch(eventDetailProvider(eventId)).value?.event.title;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Invite QR'),
      ),
      body: host.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => EmptyState(icon: AppIcons.wifiSlash, title: 'Couldn\'t check access', subtitle: friendlyError(e)),
        data: (isHost) => !isHost
            ? const EmptyState(icon: AppIcons.lock, title: 'Host only', subtitle: 'Only the meet\'s host can show its invite code.')
            : _InviteBody(eventId: eventId, title: title),
      ),
    );
  }
}

class _InviteBody extends ConsumerWidget {
  const _InviteBody({required this.eventId, this.title});
  final String eventId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(_inviteCodeProvider(eventId));
    final linked = ref.watch(_linkedCountProvider(eventId));
    return code.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => EmptyState(
        icon: AppIcons.qrCode,
        title: 'Couldn\'t get the invite code',
        subtitle: friendlyError(e),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(_inviteCodeProvider(eventId)),
      ),
      data: (c) {
        final url = eventInviteUrl(c);
        final n = linked.value;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_linkedCountProvider(eventId));
            await ref.read(_linkedCountProvider(eventId).future).catchError((_) => 0);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              if (title != null) Text(title!, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4))],
                  ),
                  child: QrImageView(data: url, size: 260, padding: EdgeInsets.zero, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  c.split('').join(' '),
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: 2, height: 1, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'New to TT Spot? Scan to download. Enter code $c when you sign up to join this event.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: c));
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(content: Text('Code copied')));
                      },
                      icon: const Icon(AppIcons.copy, size: 18),
                      label: const Text('Copy code'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => SharePlus.instance.share(ShareParams(
                        text: 'Join ${title ?? 'our meet'} on TT Spot: $url\nNew to TT Spot? Enter code $c when you sign up.',
                        subject: title,
                      )),
                      icon: const Icon(AppIcons.shareFat, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(AppIcons.usersThree, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        linked.hasError
                            ? 'Linked to this event: unavailable'
                            : 'Linked to this event: ${n ?? '…'} ${n == 1 ? 'person' : 'people'}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    IconButton(tooltip: 'Refresh', icon: const Icon(AppIcons.arrowsClockwise, size: 20), onPressed: () => ref.invalidate(_linkedCountProvider(eventId))),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Members who already have TT Spot can scan this from Me → Scan to open the event.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }
}
