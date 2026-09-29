import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../events/application/event_providers.dart';
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
  const FloorplanScreen({super.key, required this.eventId, this.initialLevelId});
  final String eventId;
  final String? initialLevelId;

  @override
  ConsumerState<FloorplanScreen> createState() => _FloorplanScreenState();
}

class _FloorplanScreenState extends ConsumerState<FloorplanScreen> {
  String? _levelId;
  final Set<PinKind> _filter = {};
  bool _placing = false;
  bool _busy = false;
  bool _jumpedToMine = false;

  FloorplanRepository get _repo => ref.read(floorplanRepositoryProvider);

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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
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
      body: levelsAsync.when(
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

          return Column(
            children: [
              if (kinds.length > 1) _FilterRow(kinds: kinds, selected: _filter, onChanged: () => setState(() {})),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: AppColors.surfaceGray,
                        child: FloorplanCanvas(
                          level: level,
                          padding: const EdgeInsets.fromLTRB(12, 12, 72, 12),
                          pinVisible: (p) => _filter.isEmpty || _filter.contains(p.kind),
                          onPinTap: _busy
                              ? null
                              : _placing
                                  ? (p) => _save(level: level, x: p.x, y: p.y, zonePinId: p.id, done: 'You are at ${p.title}.')
                                  : (p) => _openPin(level, p),
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
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.kinds, required this.selected, required this.onChanged});
  final List<PinKind> kinds;
  final Set<PinKind> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip({required String label, IconData? icon, Color? color, required bool on, required VoidCallback onTap}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Material(
            color: on ? AppColors.textPrimary : AppColors.surfaceGray,
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
                    Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? AppColors.onInk : AppColors.textPrimary)),
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
          chip(label: 'All', on: selected.isEmpty, onTap: () {
            selected.clear();
            onChanged();
          }),
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
