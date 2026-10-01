import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/geo/latlng.dart';
import '../../../core/places/places_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart' show confirmSheet;
import '../../social/application/community_providers.dart';
import '../../vendors/application/vendors_providers.dart';
import '../application/create_event_controller.dart';
import '../application/plan_draft.dart';
import 'plan_steps/kind_step.dart';
import 'plan_steps/review_step.dart';
import 'plan_steps/style_step.dart';
import 'plan_steps/when_step.dart';
import 'plan_steps/where_step.dart';
import 'plan_steps/who_step.dart';
import 'plan_steps/wizard_parts.dart';

/// Plan something for later, one question per screen, so it never feels
/// like a long form:
/// * `session` = a TT session anyone can plan: Where → When (+ how long) →
///   Who → Make it yours → Review.
/// * otherwise a meet hosted by a club (`clubId`) or a partner (`vendorId`):
///   What kind → Where → When → Who → Make it yours → Review.
/// Every answer lives in one [PlanDraft], so Back / Next / Edit never lose
/// anything. [at] + [venue] start on that place ("TT here" from a map card),
/// in which case a TT session opens on When.
class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key, this.clubId, this.vendorId, this.session = false, this.at, this.venue, this.showMap = true});
  final String? clubId;
  final String? vendorId;
  final bool session;
  final LatLng? at;
  final String? venue;
  /// False in widget tests (the map is a platform view).
  final bool showMap;

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  late final PlanDraft _draft = PlanDraft(session: widget.session, at: widget.at, venue: widget.venue);
  final _nearby = ValueNotifier<List<PlaceDetails>>(const []);
  late int _index = widget.session && widget.at != null && (widget.venue ?? '').trim().isNotEmpty ? _draft.steps.indexOf(PlanStep.when) : 0;
  /// Came here from an Edit link on the review: Next goes straight back.
  bool _fromReview = false;
  String? _error;

  List<PlanStep> get _steps => _draft.steps;
  PlanStep get _step => _steps[_index];
  late bool _dirty = _draft.isDirty;

  @override
  void initState() {
    super.initState();
    // Rebuild when the draft goes from empty to started: an empty wizard can
    // be swiped away (iOS edge swipe, Android back) without a question.
    _draft.addListener(_onDraft);
  }

  void _onDraft() {
    if (_draft.isDirty != _dirty && mounted) setState(() => _dirty = _draft.isDirty);
  }

  @override
  void dispose() {
    _draft.removeListener(_onDraft);
    _draft.dispose();
    _nearby.dispose();
    super.dispose();
  }

  void _show(int i, {bool fromReview = false}) {
    FocusScope.of(context).unfocus();
    setState(() {
      _index = i.clamp(0, _steps.length - 1);
      _fromReview = fromReview;
      _error = null;
    });
  }

  void _next() {
    final problem = _draft.problem(_step);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (_step == PlanStep.review) {
      _submit();
      return;
    }
    _show(_fromReview ? _steps.indexOf(PlanStep.review) : _index + 1);
  }

  Future<void> _back() async {
    if (_index == 0) return _close();
    _show(_fromReview ? _steps.indexOf(PlanStep.review) : _index - 1);
  }

  Future<void> _close() async {
    if (_draft.isDirty) {
      final ok = await confirmSheet(context, title: 'Discard this plan?', body: 'What you filled in so far will be lost.', confirm: 'Discard', cancel: 'Keep going', icon: AppIcons.trash);
      if (!ok || !mounted) return;
    }
    if (mounted) context.pop();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final d = _draft;
    final id = await ref.read(createEventControllerProvider.notifier).submit(
          title: d.title,
          description: d.notesCtrl.text,
          type: d.type,
          startsAt: d.startsAt,
          endsAt: d.endsAt,
          venueName: d.venue,
          location: d.pin,
          cover: d.coverFile,
          coverUrl: d.presetUrl,
          clubId: widget.clubId,
          vendorId: widget.vendorId,
          friendsOnly: d.friendsOnly,
          address: d.address,
          invitees: d.invitees.toList(),
        );
    if (id != null && mounted) context.pushReplacement(Routes.event(id));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(createEventControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(friendlyError(next.error!))));
      }
    });
    final busy = ref.watch(createEventControllerProvider).isLoading;
    final club = widget.clubId == null ? null : ref.watch(clubProvider(widget.clubId!)).value;
    final vendor = widget.vendorId == null ? null : ref.watch(myVendorProvider).value;
    // Underground clubs plan up to a week out (the server says so too).
    _draft.underground = club != null && !club.isOfficial;
    final hostName = club?.name ?? vendor?.name;
    final personal = widget.clubId == null && widget.vendorId == null;
    final step = _step;

    final Widget body = switch (step) {
      PlanStep.kind => KindStep(draft: _draft, hostName: hostName),
      PlanStep.where => WhereStep(draft: _draft, showMap: widget.showMap, nearby: _nearby),
      PlanStep.when => WhenStep(draft: _draft),
      PlanStep.who => WhoStep(draft: _draft, clubName: club?.name, canInvite: personal),
      PlanStep.style => StyleStep(draft: _draft),
      PlanStep.review => ReviewStep(draft: _draft, hostName: hostName, clubName: club?.name, onEdit: (s) => _show(_steps.indexOf(s), fromReview: true)),
    };

    final last = step == PlanStep.review;
    final primary = last ? (widget.session ? 'Post TT session' : 'Publish meet') : (_fromReview ? 'Back to review' : 'Next');

    return PopScope(
      canPop: _index == 0 && !_dirty && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: 'Close', icon: const Icon(AppIcons.x), onPressed: busy ? null : _close),
          title: Text(widget.session ? 'Plan a TT session' : 'Plan a meet'),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(26 + MediaQuery.textScalerOf(context).scale(12) * 1.4),
            child: WizardProgress(index: _index, count: _steps.length, label: step.title),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a), child: child),
                  ),
                  child: KeyedSubtree(key: ValueKey(step), child: body),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.divider))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(AppIcons.warning, size: 16, color: AppColors.danger),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_error!, key: const Key('plan-error'), style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600))),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        if (_index > 0) ...[
                          OutlinedButton(
                            key: const Key('plan-back'),
                            onPressed: busy ? null : _back,
                            style: OutlinedButton.styleFrom(minimumSize: const Size(96, 50)),
                            child: const Text('Back'),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: FilledButton(
                            key: const Key('plan-next'),
                            onPressed: busy ? null : _next,
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                            child: busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(primary, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
