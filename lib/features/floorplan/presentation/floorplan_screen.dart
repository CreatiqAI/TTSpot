import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/router/pop_or_home.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../events/application/event_providers.dart';
import '../../expo/door/presentation/door_welcome_banner.dart';
import '../../expo/exhibitors/application/exhibitors_providers.dart';
import '../../expo/exhibitors/domain/exhibitor.dart';
import '../../expo/exhibitors/presentation/exhibitor_sheet.dart';
import '../../expo/exhibitors/presentation/exhibitor_widgets.dart';
import '../../expo/expo_routes.dart';
import '../../vendors/application/vendors_providers.dart';
import '../../vendors/domain/vendor.dart';
import '../application/floorplan_providers.dart';
import '../data/floorplan_repository.dart';
import '../domain/floorplan.dart';
import 'floorplan_canvas.dart';
import 'zone_scanner_screen.dart';

/// Paths for the floorplan feature (registered under /event/:id in app_router).
abstract final class FloorplanRoutes {
  static String view(String eventId) => '/event/$eventId/floorplan';
  static String edit(String eventId) => '/event/$eventId/floorplan/edit';
  static String invite(String eventId) => '/event/$eventId/invite';
}

/// Member view of an event's floorplan: pick a level, find booths, toilets,
/// the stage, and say where you are (tap the plan or scan a zone QR).
class FloorplanScreen extends ConsumerStatefulWidget {
  const FloorplanScreen({super.key, required this.eventId, this.initialLevelId, this.highlightExhibitorId, this.welcome = false});
  final String eventId;
  final String? initialLevelId;

  /// Zoom to and highlight this exhibitor's booths (Expo mode).
  final String? highlightExhibitorId;

  /// Just checked in at the door: show DoorWelcomeBanner on top.
  final bool welcome;

  @override
  ConsumerState<FloorplanScreen> createState() => _FloorplanScreenState();
}

/// What the plan is pointing at: an exhibitor's booths or one pin.
class _Highlight {
  const _Highlight({required this.title, required this.pinIds, this.exhibitorId, this.subtitle});
  final String title;
  final String? subtitle;
  final Set<String> pinIds;
  final String? exhibitorId;
}

class _FloorplanScreenState extends ConsumerState<FloorplanScreen> {
  String? _levelId;
  final Set<PinKind> _filter = {};
  bool _partnersOnly = false;
  bool _placing = false;
  bool _busy = false;
  bool _jumpedToMine = false;
  bool _openedHighlight = false;
  _Highlight? _hl;
  FloorplanFocus? _focus;
  int _focusToken = 0;

  FloorplanRepository get _repo => ref.read(floorplanRepositoryProvider);

  @override
  void initState() {
    super.initState();
    // Opening on an exhibitor: don't jump to my spot's level first.
    if (widget.highlightExhibitorId != null) _jumpedToMine = true;
  }

  /// Switches to the level holding most of [pins], zooms to them there and
  /// outlines them.
  void _point(List<FloorPin> pins, {required String title, String? subtitle, String? exhibitorId}) {
    if (pins.isEmpty) {
      setState(() => _hl = _Highlight(title: title, subtitle: 'Not on the plan yet', pinIds: const {}, exhibitorId: exhibitorId));
      return;
    }
    final perLevel = <String, int>{};
    for (final p in pins) {
      perLevel[p.levelId] = (perLevel[p.levelId] ?? 0) + 1;
    }
    final levelId = (perLevel.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final here = mainCluster([for (final p in pins) if (p.levelId == levelId) p.rect]);
    setState(() {
      _levelId = levelId;
      _filter.clear();
      _partnersOnly = false;
      _placing = false;
      _hl = _Highlight(title: title, subtitle: subtitle, pinIds: {for (final p in pins) p.id}, exhibitorId: exhibitorId);
      _focus = FloorplanFocus(boundsOf(here)!, ++_focusToken);
    });
  }

  void _pointAtExhibitor(Exhibitor e, List<FloorLevel> levels) {
    final pins = boothPinsFor(levels, exhibitorId: e.id, boothCodes: e.booths);
    _point(pins, title: e.name, subtitle: e.booths.isEmpty ? null : e.boothsLabel, exhibitorId: e.id);
  }

  void _pointAtPin(FloorPin p, List<FloorLevel> levels, Map<String, Exhibitor> byId) {
    final e = p.exhibitorId == null ? null : byId[p.exhibitorId];
    final level = levels.where((l) => l.id == p.levelId).firstOrNull;
    _point([p], title: e?.name ?? p.title, subtitle: [if (e != null) p.title, if (level != null) level.name].join(' · '), exhibitorId: e?.id);
  }

  void _openExhibitor(String exhibitorId, List<FloorLevel> levels) {
    showExhibitorSheet(context, widget.eventId, exhibitorId, onShowOnPlan: () {
      final e = exhibitorById(ref.read(eventExhibitorsProvider(widget.eventId)).value, exhibitorId);
      if (e != null && mounted) _pointAtExhibitor(e, levels);
    });
  }

  void _tapPin(FloorLevel level, FloorPin pin, List<FloorLevel> levels, Map<String, Exhibitor> byId) {
    final id = pin.exhibitorId;
    if (id != null && byId.containsKey(id)) {
      _openExhibitor(id, levels);
    } else {
      _openPin(level, pin);
    }
  }

  Future<void> _find(List<FloorLevel> levels, List<Exhibitor> exhibitors) async {
    final byId = {for (final e in exhibitors) e.id: e};
    final picked = await showModalBottomSheet<Object>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FindSheet(levels: levels, exhibitors: exhibitors),
    );
    if (!mounted || picked == null) return;
    if (picked is Exhibitor) _pointAtExhibitor(picked, levels);
    if (picked is FloorPin) _pointAtPin(picked, levels, byId);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  FloorLevel _current(List<FloorLevel> levels) => levels.firstWhere((l) => l.id == _levelId, orElse: () => levels.first);

  FloorPin? _pinById(List<FloorLevel> levels, String? id) {
    if (id == null) return null;
    for (final l in levels) {
      for (final p in l.pins) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  Future<void> _save({required FloorLevel level, double? x, double? y, String? zonePinId, String? done}) async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    setState(() => _busy = true);
    try {
      await _repo.setMyPosition(eventId: widget.eventId, userId: me, levelId: level.id, x: x, y: y, zonePinId: zonePinId);
      ref.invalidate(myEventPositionProvider(widget.eventId));
      ref.invalidate(floorLevelCountsProvider(widget.eventId));
      if (mounted) {
        setState(() => _placing = false);
        _toast(done ?? 'Spot saved on ${level.name}.');
      }
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tap-to-place: snaps to a zone / parking pin if you tapped right next to one.
  Future<void> _placeAt(FloorLevel level, Offset f) async {
    FloorPin? near;
    var best = 0.05;
    for (final p in level.pins) {
      if (p.kind != PinKind.zone && p.kind != PinKind.parking) continue;
      final d = math.sqrt(math.pow(p.x - f.dx, 2) + math.pow(p.y - f.dy, 2));
      if (d < best) {
        best = d;
        near = p;
      }
    }
    await _save(level: level, x: f.dx, y: f.dy, zonePinId: near?.id, done: near == null ? null : 'Spot saved: ${near.title}, ${level.name}.');
  }

  Future<void> _startPlacing(List<FloorLevel> levels, MyPosition? mine) async {
    setState(() {
      _placing = true;
      if (mine != null && levels.any((l) => l.id == mine.levelId)) _levelId = mine.levelId;
    });
  }

  Future<void> _scanZone() async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ZoneScannerScreen(), fullscreenDialog: true));
    if (raw == null || !mounted) return;
    final pinId = parseZoneQr(raw);
    if (pinId == null) return _toast('That is not a zone code.');
    setState(() => _busy = true);
    try {
      final r = await _repo.setPositionFromZone(pinId);
      ref.invalidate(myEventPositionProvider(widget.eventId));
      ref.invalidate(floorLevelCountsProvider(widget.eventId));
      if (!mounted) return;
      if (r.eventId != widget.eventId) {
        context.pushReplacement('${FloorplanRoutes.view(r.eventId)}?level=${r.levelId}');
        return;
      }
      final levels = ref.read(floorLevelsProvider(widget.eventId)).value ?? const [];
      final pin = _pinById(levels, pinId);
      setState(() {
        _levelId = r.levelId;
        _placing = false;
      });
      _toast(pin == null ? 'Spot saved.' : 'You are at ${pin.title}.');
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    try {
      await _repo.clearMyPosition(widget.eventId, me);
      ref.invalidate(myEventPositionProvider(widget.eventId));
      ref.invalidate(floorLevelCountsProvider(widget.eventId));
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  void _openPin(FloorLevel level, FloorPin pin) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: pin.kind.color, shape: BoxShape.circle),
                    child: Icon(pin.kind.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pin.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('${pin.kind.label} · ${level.name}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (pin.partnerVendorId != null) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push(Routes.partner(pin.partnerVendorId!));
                  },
                  icon: const Icon(AppIcons.storefront, size: 18),
                  label: const Text('Open partner page'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  final parked = pin.kind == PinKind.parking;
                  _save(level: level, x: pin.x, y: pin.y, zonePinId: pin.id, done: parked ? 'Saved where you parked: ${pin.title}, ${level.name}.' : 'You are at ${pin.title}.');
                },
                icon: Icon(pin.kind == PinKind.parking ? AppIcons.car : AppIcons.mapPin, size: 18),
                label: Text(pin.kind == PinKind.parking ? 'I parked here' : 'I\'m here'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final levelsAsync = ref.watch(floorLevelsProvider(widget.eventId));
    final mine = ref.watch(myEventPositionProvider(widget.eventId)).value;
    final isHost = ref.watch(isMeetHostProvider(widget.eventId)).value ?? false;
    final counts = ref.watch(floorLevelCountsProvider(widget.eventId)).value ?? const <String, int>{};
    final title = ref.watch(eventDetailProvider(widget.eventId)).value?.event.title;
    final exAsync = ref.watch(eventExhibitorsProvider(widget.eventId));
    final exhibitors = exAsync.value ?? const <Exhibitor>[];
    final byId = {for (final e in exhibitors) e.id: e};
    final allLevels = levelsAsync.value ?? const <FloorLevel>[];
    final pinPartners = allLevels.any((l) => l.pins.any((p) => p.partnerVendorId != null));
    final partnerShops = pinPartners ? (ref.watch(partnersDirectoryProvider).value ?? const <PublicVendor>[]) : const <PublicVendor>[];

    // Opened from "Show on floor plan": point at the exhibitor once both load.
    final wantId = widget.highlightExhibitorId;
    if (!_openedHighlight && wantId != null && exAsync.hasValue && levelsAsync.hasValue) {
      _openedHighlight = true;
      final e = exhibitorById(exhibitors, wantId);
      final levels = allLevels.where((l) => l.hasImage).toList();
      if (e != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pointAtExhibitor(e, levels);
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Floorplan'),
            if (title != null) Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          if (isHost)
            IconButton(
              tooltip: 'Edit floorplan',
              icon: const Icon(AppIcons.pencilSimple),
              onPressed: () async {
                await context.push(FloorplanRoutes.edit(widget.eventId));
                ref.invalidate(floorLevelsProvider(widget.eventId));
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.welcome) DoorWelcomeBanner(eventId: widget.eventId),
          Expanded(child: _body(levelsAsync, mine, isHost, counts, exhibitors, byId, partnerShops)),
        ],
      ),
    );
  }

  Widget _body(
    AsyncValue<List<FloorLevel>> levelsAsync,
    MyPosition? mine,
    bool isHost,
    Map<String, int> counts,
    List<Exhibitor> exhibitors,
    Map<String, Exhibitor> byId,
    List<PublicVendor> partnerShops,
  ) {
    return levelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => EmptyState(icon: AppIcons.wifiSlash, title: 'Couldn\'t load the plan', subtitle: friendlyError(e), actionLabel: 'Try again', onAction: () => ref.invalidate(floorLevelsProvider(widget.eventId))),
        data: (all) {
          final levels = all.where((l) => l.hasImage).toList();
          if (levels.isEmpty) {
            return EmptyState(
              titi: TitiPose.clipboard,
              icon: AppIcons.mapTrifold,
              title: 'No floorplan yet',
              subtitle: isHost ? 'Add each level of the venue and pin the booths, stage and zones.' : 'The organiser hasn\'t added a plan for this meet.',
              actionLabel: isHost ? 'Build the floorplan' : null,
              onAction: isHost ? () => context.push(FloorplanRoutes.edit(widget.eventId)) : null,
            );
          }
          if (_levelId == null || !levels.any((l) => l.id == _levelId)) {
            final want = widget.initialLevelId;
            _levelId = levels.any((l) => l.id == want) ? want : levels.first.id;
          }
          if (!_jumpedToMine && mine != null && widget.initialLevelId == null) {
            _jumpedToMine = true;
            if (levels.any((l) => l.id == mine.levelId)) _levelId = mine.levelId;
          }
          final level = _current(levels);
          final kinds = {for (final p in level.pins) p.kind}.toList()..sort((a, b) => a.index.compareTo(b.index));
          final myPin = _pinById(levels, mine?.zonePinId);
          final parked = myPin?.kind == PinKind.parking;
          final mineHere = mine != null && mine.levelId == level.id && mine.hasPoint;
          final logos = partnerLogosFor(level, byId, {for (final v in partnerShops) v.id: v.logoUrl});
          final partnersOnly = _partnersOnly && logos.isNotEmpty;
          final kindFilter = {..._filter};
          final hasBooths = levels.any((l) => l.pins.any((p) => p.kind == PinKind.booth));
          final hl = _hl;

          return Column(
            children: [
              if (exhibitors.isNotEmpty || hasBooths)
                _FindBar(
                  showExhibitors: exhibitors.isNotEmpty,
                  onFind: () => _find(levels, exhibitors),
                  onExhibitors: () => context.push(ExpoRoutes.exhibitors(widget.eventId)),
                ),
              if (kinds.length > 1 || logos.isNotEmpty)
                _FilterRow(
                  kinds: kinds,
                  selected: _filter,
                  showPartners: logos.isNotEmpty,
                  partnersOn: partnersOnly,
                  onPartners: () => setState(() {
                    _partnersOnly = !_partnersOnly;
                    if (_partnersOnly) _filter.clear();
                  }),
                  onChanged: () => setState(() {
                    if (_filter.isNotEmpty) _partnersOnly = false;
                  }),
                  onAll: () => setState(() => _partnersOnly = false),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: AppColors.surfaceGray,
                        child: FloorplanCanvas(
                          level: level,
                          padding: const EdgeInsets.fromLTRB(12, 12, 72, 12),
                          pinVisible: partnersOnly
                              ? (p) => logos.containsKey(p.id)
                              : kindFilter.isEmpty
                                  ? null
                                  : (p) => kindFilter.contains(p.kind),
                          partnerLogos: logos,
                          highlightPinIds: hl?.pinIds ?? const {},
                          focus: _focus,
                          onPinTap: _busy
                              ? null
                              : _placing
                                  ? (p) => _save(level: level, x: p.x, y: p.y, zonePinId: p.id, done: 'You are at ${p.title}.')
                                  : (p) => _tapPin(level, p, levels, byId),
                          onTapPlan: _placing && !_busy ? (f) => _placeAt(level, f) : null,
                          youAreHere: mineHere ? Offset(mine.x!, mine.y!) : null,
                          youLabel: parked ? 'Parked here' : 'You',
                          selectedPinId: mine?.zonePinId,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      bottom: 10,
                      child: Center(
                        child: _LevelSwitcher(
                          levels: levels,
                          currentId: level.id,
                          myLevelId: mine?.levelId,
                          counts: isHost ? counts : const {},
                          onPick: (id) => setState(() => _levelId = id),
                        ),
                      ),
                    ),
                    if (_placing)
                      Positioned(
                        left: 12,
                        right: 80,
                        top: 12,
                        child: Material(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                            child: Row(
                              children: [
                                const Icon(AppIcons.crosshair, color: Colors.white, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Tap where you are on ${level.name}. Wrong level? Switch on the right.',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                                  ),
                                ),
                                TextButton(onPressed: () => setState(() => _placing = false), child: const Text('Cancel', style: TextStyle(color: Colors.white))),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (hl != null && !_placing)
                      Positioned(
                        left: 12,
                        right: 80,
                        bottom: 12,
                        child: _HighlightCard(
                          title: hl.title,
                          subtitle: hl.subtitle,
                          exhibitor: hl.exhibitorId == null ? null : byId[hl.exhibitorId],
                          onDetails: hl.exhibitorId == null || !byId.containsKey(hl.exhibitorId) ? null : () => _openExhibitor(hl.exhibitorId!, levels),
                          onClose: () => setState(() => _hl = null),
                        ),
                      ),
                    if (_busy) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(minHeight: 2)),
                  ],
                ),
              ),
              _MySpotPanel(
                levels: levels,
                mine: mine,
                myPin: myPin,
                busy: _busy,
                placing: _placing,
                onShowMine: mine == null ? null : () => setState(() => _levelId = mine.levelId),
                onClear: _clear,
                onImHere: () => _startPlacing(levels, mine),
                onScan: _scanZone,
              ),
            ],
          );
        },
    );
  }
}

/// Partner booths on [level]: pin id -> logo URL (null = no logo). A booth
/// counts when its exhibitor is linked to a partner, or the pin itself is.
Map<String, String?> partnerLogosFor(FloorLevel level, Map<String, Exhibitor> exhibitors, Map<String, String?> shopLogos) {
  final out = <String, String?>{};
  for (final p in level.pins) {
    if (p.kind != PinKind.booth) continue;
    final exId = p.exhibitorId;
    final e = exId == null ? null : exhibitors[exId];
    if (e != null && e.isPartner) {
      out[p.id] = e.partnerLogo ?? e.logoUrl;
    } else if (p.partnerVendorId != null) {
      out[p.id] = shopLogos[p.partnerVendorId];
    }
  }
  return out;
}

/// "Find booth or exhibitor" plus the Exhibitors list button.
class _FindBar extends StatelessWidget {
  const _FindBar({required this.showExhibitors, required this.onFind, required this.onExhibitors});
  final bool showExhibitors;
  final VoidCallback onFind;
  final VoidCallback onExhibitors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: AppColors.surfaceGray,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onFind,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(AppIcons.magnifyingGlass, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Find booth or exhibitor', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showExhibitors) ...[
            const SizedBox(width: 8),
            Material(
              color: AppColors.textPrimary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onExhibitors,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.storefront, size: 18, color: AppColors.onInk),
                      const SizedBox(width: 6),
                      Text('Exhibitors', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onInk)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Search sheet: exhibitors (name, booth, category) and pins (booth codes,
/// stage, toilets...). Pops with the picked [Exhibitor] or [FloorPin].
class _FindSheet extends StatefulWidget {
  const _FindSheet({required this.levels, required this.exhibitors});
  final List<FloorLevel> levels;
  final List<Exhibitor> exhibitors;

  @override
  State<_FindSheet> createState() => _FindSheetState();
}

class _FindSheetState extends State<_FindSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final lower = q.toLowerCase();
    final upper = q.toUpperCase();
    final levelName = {for (final l in widget.levels) l.id: l.name};
    final byId = {for (final e in widget.exhibitors) e.id: e};
    final exhibitors = q.isEmpty ? const <Exhibitor>[] : widget.exhibitors.where((e) => e.matches(q)).take(40).toList();
    final pins = <FloorPin>[];
    if (q.isNotEmpty) {
      for (final l in widget.levels) {
        for (final p in l.pins) {
          final hit = p.kind == PinKind.booth ? p.code.contains(upper) : (p.title.toLowerCase().contains(lower) || p.kind.label.toLowerCase().contains(lower));
          if (hit) pins.add(p);
        }
      }
      // Exact booth codes first.
      pins.sort((a, b) => (a.code == upper ? 0 : 1).compareTo(b.code == upper ? 0 : 1));
    }
    final shownPins = pins.take(30).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(
                    hintText: 'Booth code, exhibitor, stage...',
                    prefixIcon: Icon(AppIcons.magnifyingGlass, size: 20),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: q.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Type a booth code like A019 or a name.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      )
                    : exhibitors.isEmpty && shownPins.isEmpty
                        ? Center(child: Text('Nothing found.', style: TextStyle(color: AppColors.textSecondary)))
                        : ListView(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            children: [
                              for (final e in exhibitors)
                                ListTile(
                                  leading: ExhibitorLogo(exhibitor: e, size: 40),
                                  title: Row(
                                    children: [
                                      Flexible(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                                      if (e.isPartner) ...[const SizedBox(width: 6), const PartnerTag()],
                                    ],
                                  ),
                                  subtitle: Text([if (e.booths.isNotEmpty) e.boothsLabel, if (e.category != null) e.category!].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () => Navigator.pop(context, e),
                                ),
                              for (final p in shownPins)
                                ListTile(
                                  leading: CircleAvatar(backgroundColor: p.kind.color, child: Icon(p.kind.icon, color: Colors.white, size: 18)),
                                  title: Text(p.kind == PinKind.booth ? 'Booth ${p.title}' : p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    [if (p.exhibitorId != null && byId[p.exhibitorId] != null) byId[p.exhibitorId]!.name, levelName[p.levelId] ?? ''].where((s) => s.isNotEmpty).join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => Navigator.pop(context, p),
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

/// Bottom card while the plan points at something: name, Details, close.
class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.title, required this.onClose, this.subtitle, this.exhibitor, this.onDetails});
  final String title;
  final String? subtitle;
  final Exhibitor? exhibitor;
  final VoidCallback? onDetails;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final e = exhibitor;
    return Material(
      color: AppColors.surface,
      elevation: 6,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            if (e != null) ...[ExhibitorLogo(exhibitor: e, size: 40), const SizedBox(width: 10)] else ...[
              Icon(AppIcons.mapPinFill, color: AppColors.brand, size: 24),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (onDetails != null) TextButton(onPressed: onDetails, child: const Text('Details')),
            IconButton(tooltip: 'Close', icon: Icon(AppIcons.x, size: 18, color: AppColors.textSecondary), onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.kinds,
    required this.selected,
    required this.onChanged,
    this.showPartners = false,
    this.partnersOn = false,
    this.onPartners,
    this.onAll,
  });
  final List<PinKind> kinds;
  final Set<PinKind> selected;
  final VoidCallback onChanged;
  final bool showPartners;
  final bool partnersOn;
  final VoidCallback? onPartners;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    Widget chip({required String label, IconData? icon, Color? color, required bool on, required VoidCallback onTap, bool gold = false}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Material(
            color: on ? AppColors.textPrimary : (gold ? kPartnerGold.withValues(alpha: 0.16) : AppColors.surfaceGray),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 15, color: on ? AppColors.onInk : color), const SizedBox(width: 5)],
                    Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? AppColors.onInk : (gold ? kPartnerGoldDeep : AppColors.textPrimary))),
                  ],
                ),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        children: [
          chip(label: 'All', on: selected.isEmpty && !partnersOn, onTap: () {
            selected.clear();
            onAll?.call();
            onChanged();
          }),
          if (showPartners && onPartners != null)
            chip(label: 'Partners', icon: AppIcons.sealCheck, color: kPartnerGoldDeep, gold: true, on: partnersOn, onTap: onPartners!),
          for (final k in kinds)
            chip(
              label: k.label,
              icon: k.icon,
              color: k.color,
              on: selected.contains(k),
              onTap: () {
                if (!selected.remove(k)) selected.add(k);
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}

/// Vertical level picker, top floor at the top (Rooftop … B2).
class _LevelSwitcher extends StatelessWidget {
  const _LevelSwitcher({required this.levels, required this.currentId, required this.onPick, this.myLevelId, this.counts = const {}});
  final List<FloorLevel> levels;
  final String currentId;
  final String? myLevelId;
  final Map<String, int> counts;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final top = levels.reversed.toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in top)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _levelChip(l),
              ),
          ],
        ),
      ),
    );
  }

  Widget _levelChip(FloorLevel l) {
    final on = l.id == currentId;
    final n = counts[l.id];
    return Material(
      color: on ? AppColors.textPrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onPick(l.id),
        child: SizedBox(
          width: 52,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(l.name, style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800, color: on ? AppColors.onInk : AppColors.textPrimary)),
                ),
              ),
              if (l.id == myLevelId)
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5))),
                ),
              if (n != null && n > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                    child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MySpotPanel extends StatelessWidget {
  const _MySpotPanel({
    required this.levels,
    required this.mine,
    required this.myPin,
    required this.busy,
    required this.placing,
    required this.onShowMine,
    required this.onClear,
    required this.onImHere,
    required this.onScan,
  });
  final List<FloorLevel> levels;
  final MyPosition? mine;
  final FloorPin? myPin;
  final bool busy;
  final bool placing;
  final VoidCallback? onShowMine;
  final VoidCallback onClear;
  final VoidCallback onImHere;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final m = mine;
    final levelName = m == null ? null : levels.where((l) => l.id == m.levelId).map((l) => l.name).firstOrNull;
    final parked = myPin?.kind == PinKind.parking;
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.divider))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (m != null && levelName != null) ...[
                InkWell(
                  onTap: onShowMine,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(parked ? AppIcons.car : AppIcons.mapPinFill, color: AppColors.brand, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                parked ? 'Where I parked: ${myPin!.title}, $levelName' : 'You: $levelName${myPin == null ? '' : ' · ${myPin!.title}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              Text('Set ${timeAgo(m.updatedAt).toLowerCase()}${timeAgo(m.updatedAt) == 'Just now' ? '' : ' ago'}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        IconButton(tooltip: 'Clear my spot', icon: Icon(AppIcons.x, size: 18, color: AppColors.textSecondary), onPressed: busy ? null : onClear),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy || placing ? null : onImHere,
                      icon: const Icon(AppIcons.crosshair, size: 18),
                      label: Text(m == null ? 'I\'m here' : 'Move my spot'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onScan,
                      icon: const Icon(AppIcons.scan, size: 18),
                      label: const Text('Scan a zone QR'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.lock, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Text('Only you see your spot. Cleared after the event.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
