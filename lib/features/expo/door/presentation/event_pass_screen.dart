import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/router/app_router.dart' show Routes;
import '../../../../core/router/pop_or_home.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../events/application/event_providers.dart';
import '../../../organizer/application/organizer_providers.dart';
import '../../../organizer/presentation/widgets/lucky_draw_card.dart';
import '../../stamps/presentation/my_leads_section.dart';
import '../application/door_providers.dart';
import '../domain/door_models.dart';
import 'door_welcome_banner.dart';
import 'event_hub_card.dart';
import 'registration_sheet.dart';

/// My pass for an event: entry number, pass QR, registration, draw status, links.
class EventPassScreen extends ConsumerStatefulWidget {
  const EventPassScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventPassScreen> createState() => _EventPassScreenState();
}

class _EventPassScreenState extends ConsumerState<EventPassScreen> {
  @override
  void initState() {
    super.initState();
    // Straight here after a door check-in (no floor plan): the form opens once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) openPendingRegistration(context, ref, widget.eventId);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(eventHubProvider(widget.eventId));
    ref.invalidate(myDrawStatusProvider(widget.eventId));
    await ref.read(eventHubProvider(widget.eventId).future).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(eventHubProvider(widget.eventId));
    final title = ref.watch(eventDetailProvider(widget.eventId)).value?.event.title;
    final going = ref.watch(eventDetailProvider(widget.eventId)).value?.isAttending ?? false;
    final h = hub.value;

    Widget body;
    if (h == null) {
      body = hub.hasError
          ? ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(hub.error!), textAlign: TextAlign.center))])
          : hub.isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView(children: const [SizedBox(height: 40), EmptyState(titi: TitiPose.stop, title: 'Sign in to see your pass')]);
    } else if (!h.checkedIn) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (title != null) _EventTitle(title),
          const SizedBox(height: 24),
          EmptyState(
            titi: TitiPose.mapPin,
            title: 'No pass yet',
            subtitle: 'How to check in: scan the QR at the entrance with TT Spot.',
            actionLabel: 'Scan',
            onAction: () => context.push(Routes.scan),
          ),
          const SizedBox(height: 16),
          if (h.registration.open && going) ...[
            RegistrationNudge(eventId: widget.eventId, questions: h.registration.questions),
            const SizedBox(height: 12),
          ],
          LuckyDrawCard(eventId: widget.eventId),
        ],
      );
    } else {
      final links = hubTiles(widget.eventId, h, pass: false, booths: false);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _PassCard(eventId: widget.eventId, eventTitle: title, hub: h),
          const SizedBox(height: 12),
          _ShareContactSwitch(eventId: widget.eventId, on: h.shareContact),
          if (h.registration.hasForm) ...[
            const SizedBox(height: 8),
            _RegistrationRow(eventId: widget.eventId, reg: h.registration),
          ],
          const SizedBox(height: 12),
          LuckyDrawCard(eventId: widget.eventId),
          if (links.isNotEmpty) ...[
            const SizedBox(height: 4),
            HubTileGrid(tiles: links),
          ],
          const SizedBox(height: 12),
          MyLeadsSection(eventId: widget.eventId),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Your pass'),
      ),
      body: RefreshIndicator(onRefresh: _refresh, child: body),
    );
  }
}

class _EventTitle extends StatelessWidget {
  const _EventTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      );
}

/// The dark ticket: event, big entry number, me, my car, the pass QR.
class _PassCard extends ConsumerWidget {
  const _PassCard({required this.eventId, required this.eventTitle, required this.hub});
  final String eventId;
  final String? eventTitle;
  final EventHub hub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentProfileProvider).value;
    final name = me?.displayName?.trim().isNotEmpty == true ? me!.displayName!.trim() : (me?.username ?? 'Me');
    final car = hub.car;
    final img = car?.image;
    final isToy = car?.toyUrl != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eventTitle != null)
            Text(
              eventTitle!.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white60),
            ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hub.entry ?? 'Checked in',
                        style: const TextStyle(fontFamily: AppFonts.display, fontSize: 64, height: 1.0, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                    if (me?.username != null)
                      Text('@${me!.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    if (car?.title != null && car!.title!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(AppIcons.car, size: 15, color: Colors.white70),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(car.title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (img != null) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(isToy ? 0 : AppRadius.md),
                  child: SizedBox(
                    width: 110,
                    height: 82,
                    child: CachedNetworkImage(
                      imageUrl: img,
                      fit: isToy ? BoxFit.contain : BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 120),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (hub.passCode != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: QrImageView(
                  data: passPayload(eventId, hub.passCode!),
                  size: 200,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Booths scan this to save your contact.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.white70, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShareContactSwitch extends ConsumerStatefulWidget {
  const _ShareContactSwitch({required this.eventId, required this.on});
  final String eventId;
  final bool on;

  @override
  ConsumerState<_ShareContactSwitch> createState() => _ShareContactSwitchState();
}

class _ShareContactSwitchState extends ConsumerState<_ShareContactSwitch> {
  bool? _pending;

  Future<void> _set(bool v) async {
    setState(() => _pending = v);
    try {
      await ref.read(doorActionsProvider).setShareContact(widget.eventId, v);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SwitchListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        value: _pending ?? widget.on,
        onChanged: _pending != null ? null : _set,
        secondary: const Icon(AppIcons.addressBook),
        title: const Text('Share my phone and email with booths I let scan me', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Text('Off: they only get your name, state and car.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      ),
    );
  }
}

class _RegistrationRow extends StatelessWidget {
  const _RegistrationRow({required this.eventId, required this.reg});
  final String eventId;
  final HubRegistration reg;

  @override
  Widget build(BuildContext context) {
    final done = reg.done;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: done ? AppColors.surfaceGray : AppColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Icon(done ? AppIcons.checkCircle : AppIcons.clipboardText, size: 22, color: done ? AppColors.success : AppColors.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(done ? 'Registered' : 'Registration', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  done ? 'Your answers went to the organizer.' : (reg.required ? 'The organizer needs this.' : 'A few quick questions.'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          done
              ? TextButton(onPressed: () => showRegistrationSheet(context, eventId), child: const Text('Edit'))
              : FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => showRegistrationSheet(context, eventId),
                  child: const Text('Fill in'),
                ),
        ],
      ),
    );
  }
}
