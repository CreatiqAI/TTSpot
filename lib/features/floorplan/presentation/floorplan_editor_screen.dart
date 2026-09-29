import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../vendors/application/vendors_providers.dart';
import '../../vendors/domain/vendor.dart';
import '../application/floorplan_providers.dart';
import '../data/floorplan_repository.dart';
import '../domain/floorplan.dart';
import 'floorplan_canvas.dart';
import 'zone_qr_sheet_screen.dart';

/// Organizer: build the event's floorplan. Levels across the top, one plan
/// image per level, tap to drop pins, hold a pin to drag it, tap to edit.
class FloorplanEditorScreen extends ConsumerStatefulWidget {
  const FloorplanEditorScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<FloorplanEditorScreen> createState() => _FloorplanEditorScreenState();
}

class _FloorplanEditorScreenState extends ConsumerState<FloorplanEditorScreen> {
  List<FloorLevel>? _levels;
  String? _levelId;
  Object? _error;
  bool _busy = false;
  String? _busyText;
  String? _selectedPinId;

  FloorplanRepository get _repo => ref.read(floorplanRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final levels = await _repo.levels(widget.eventId);
      if (!mounted) return;
      setState(() {
        _levels = levels;
        _error = null;
        if (_levelId == null || !levels.any((l) => l.id == _levelId)) _levelId = levels.firstOrNull?.id;
      });
      ref.invalidate(floorLevelsProvider(widget.eventId));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Runs a server write with a spinner, then reloads.
  Future<void> _run(Future<void> Function() job, {String? text}) async {
    setState(() {
      _busy = true;
      _busyText = text;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      await _reload();
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = null;
        });
      }
    }
  }

  FloorLevel? get _level => _levels?.where((l) => l.id == _levelId).firstOrNull;

  // ------------------------------------------------------------- levels ---

  Future<String?> _askName({required String title, String initial = '', bool suggestions = false}) {
    final c = TextEditingController(text: initial);
    const quick = ['B3', 'B2', 'B1', 'G', 'L1', 'L2', 'L3', 'L4', 'Rooftop', 'Hall A', 'Outdoor'];
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              autofocus: true,
              maxLength: 24,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. B2, L3, Rooftop'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            if (suggestions)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final q in quick)
                    ActionChip(label: Text(q), onPressed: () => Navigator.pop(ctx, q)),
                ],
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _addLevel() async {
    final name = await _askName(title: 'Add a level', suggestions: true);
    if (name == null || name.isEmpty) return;
    final levels = _levels ?? const [];
    final sort = levels.isEmpty ? 0 : levels.map((l) => l.sort).reduce((a, b) => a > b ? a : b) + 1;
    String? id;
    await _run(() async => id = await _repo.addLevel(eventId: widget.eventId, name: name, sort: sort));
    if (id != null && mounted) setState(() => _levelId = id);
  }

  Future<void> _renameLevel(FloorLevel l) async {
    final name = await _askName(title: 'Rename level', initial: l.name);
    if (name == null || name.isEmpty || name == l.name) return;
    await _run(() => _repo.renameLevel(l.id, name));
  }

  Future<void> _deleteLevel(FloorLevel l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${l.name}?'),
        content: Text('Its plan image and ${l.pins.length} pin${l.pins.length == 1 ? '' : 's'} go too. Members who set their spot on this level lose it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _repo.deleteLevel(l));
  }

  Future<void> _pickImage(FloorLevel l) async {
    final source = await showPhotoSourceSheet(context);
    if (source == null) return;
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 85);
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
      return;
    }
    if (file == null) return;
    final picked = file;
    await _run(() async {
      final bytes = await picked.readAsBytes();
      final img = await decodeImageFromList(bytes);
      final w = img.width, h = img.height;
      img.dispose();
      final name = picked.name.toLowerCase();
      final ext = name.contains('.') ? name.split('.').last : 'jpg';
      await _repo.setLevelImage(level: l, bytes: bytes, ext: ext, width: w, height: h);
    }, text: 'Uploading plan…');
  }

  Future<void> _manageLevels() async {
    final levels = _levels;
    if (levels == null || levels.isEmpty) return;
    // Shown top floor first, like the member's level switcher.
    final order = levels.reversed.toList();
    final changed = await showModalBottomSheet<List<FloorLevel>>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _LevelsSheet(
        levels: order,
        onRename: (l) {
          Navigator.pop(ctx);
          _renameLevel(l);
        },
        onDelete: (l) {
          Navigator.pop(ctx);
          _deleteLevel(l);
        },
      ),
    );
    if (changed == null) return;
    final ids = changed.reversed.map((l) => l.id).toList();
    await _run(() => _repo.reorderLevels(ids));
  }

  Future<void> _levelMenu(FloorLevel l) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.pencilSimple), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
            ListTile(leading: const Icon(AppIcons.image), title: Text(l.hasImage ? 'Replace plan image' : 'Upload plan image'), onTap: () => Navigator.pop(ctx, 'image')),
            ListTile(leading: const Icon(AppIcons.stackSimple), title: const Text('Reorder levels'), onTap: () => Navigator.pop(ctx, 'order')),
            ListTile(
              leading: const Icon(AppIcons.trash, color: AppColors.danger),
              title: const Text('Delete level', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (action) {
      case 'rename':
        await _renameLevel(l);
      case 'image':
        await _pickImage(l);
      case 'order':
        await _manageLevels();
      case 'delete':
        await _deleteLevel(l);
    }
  }

  // --------------------------------------------------------------- pins ---

  Future<void> _addPinAt(FloorLevel l, Offset f) async {
    final kind = await showModalBottomSheet<PinKind>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What goes here?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _KindGrid(onPick: (k) => Navigator.pop(ctx, k)),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    final label = await _askLabel(kind);
    if (label == null) return;
    await _run(() async {
      final pin = await _repo.addPin(levelId: l.id, kind: kind, label: label, x: f.dx, y: f.dy);
      _selectedPinId = pin.id;
    });
    if (kind == PinKind.booth && mounted) _toast('Booth added. Tap it to link a partner.');
  }

  Future<String?> _askLabel(PinKind kind, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    final hint = switch (kind) {
      PinKind.zone => 'e.g. Zone A, JDM corner, B2-14',
      PinKind.booth => 'e.g. Wrap shop booth',
      PinKind.parking => 'e.g. Bay P3, Visitor parking',
      PinKind.entrance => 'e.g. Main entrance',
      PinKind.lift => 'e.g. Lift to L3',
      PinKind.ramp => 'e.g. Ramp up to L2',
      _ => kind.label,
    };
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [Icon(kind.icon, color: kind.color), const SizedBox(width: 8), Text(kind.label)]),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint, helperText: 'Optional. Members see this on the plan.'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add pin')),
        ],
      ),
    );
  }

  Future<void> _movePin(FloorPin p, Offset f) async {
    // Move locally first so the drag feels instant.
    setState(() {
      _selectedPinId = p.id;
      _levels = [
        for (final l in _levels ?? const <FloorLevel>[])
          l.id != p.levelId ? l : FloorLevel(id: l.id, eventId: l.eventId, name: l.name, sort: l.sort, imagePath: l.imagePath, imageUrl: l.imageUrl, imageW: l.imageW, imageH: l.imageH, pins: [for (final q in l.pins) q.id == p.id ? q.copyWith(x: f.dx, y: f.dy) : q]),
      ];
    });
    try {
      await _repo.updatePin(p.copyWith(x: f.dx, y: f.dy));
      ref.invalidate(floorLevelsProvider(widget.eventId));
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
      await _reload();
    }
  }

  Future<void> _editPin(FloorLevel l, FloorPin p) async {
    setState(() => _selectedPinId = p.id);
    final result = await showModalBottomSheet<_PinEdit>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _PinEditSheet(pin: p, levelName: l.name),
    );
    if (result == null) return;
    if (result.delete) {
      await _run(() => _repo.deletePin(p.id));
      _selectedPinId = null;
    } else if (result.pin != null) {
      await _run(() => _repo.updatePin(result.pin!));
    }
  }

  void _printQrs() {
    final levels = _levels ?? const [];
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ZoneQrSheetScreen(eventId: widget.eventId, levels: levels)));
  }

  // -------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(isMeetHostProvider(widget.eventId));
    final levels = _levels;
    final level = _level;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Edit floorplan'),
        actions: [
          if (levels != null && levels.isNotEmpty) ...[
            IconButton(tooltip: 'Print zone QRs', icon: const Icon(AppIcons.qrCode), onPressed: _printQrs),
            IconButton(tooltip: 'Reorder levels', icon: const Icon(AppIcons.stackSimple), onPressed: _busy ? null : _manageLevels),
          ],
        ],
      ),
      body: host.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => EmptyState(icon: AppIcons.wifiSlash, title: 'Couldn\'t check access', subtitle: friendlyError(e)),
        data: (isHost) {
          if (!isHost) {
            return const EmptyState(icon: AppIcons.lock, title: 'Host only', subtitle: 'Only the meet\'s host can edit its floorplan.');
          }
          if (_error != null && levels == null) {
            return EmptyState(icon: AppIcons.wifiSlash, title: 'Couldn\'t load the plan', subtitle: friendlyError(_error!), actionLabel: 'Try again', onAction: _reload);
          }
          if (levels == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          return Stack(
            children: [
              Column(
                children: [
                  _LevelTabs(
                    levels: levels,
                    currentId: level?.id,
                    onPick: (id) => setState(() {
                      _levelId = id;
                      _selectedPinId = null;
                    }),
                    onMenu: _levelMenu,
                    onAdd: _busy ? null : _addLevel,
                  ),
                  Expanded(child: _body(levels, level)),
                ],
              ),
              if (_busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black26,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 12),
                            Text(_busyText ?? 'Saving…', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _body(List<FloorLevel> levels, FloorLevel? level) {
    if (levels.isEmpty || level == null) {
      return EmptyState(
        titi: TitiPose.clipboard,
        icon: AppIcons.stackSimple,
        title: 'Add the first level',
        subtitle: 'One level per floor or hall: B2, L1, Rooftop, Hall A. Then upload a photo of the venue plan for each and pin the booths, stage and zones.',
        actionLabel: 'Add a level',
        onAction: _addLevel,
      );
    }
    if (!level.hasImage) {
      return EmptyState(
        icon: AppIcons.image,
        title: 'Upload the plan for ${level.name}',
        subtitle: 'A photo of the venue directory, fire-escape plan or your own sketch works. Keep it upright and well lit.',
        actionLabel: 'Choose image',
        onAction: () => _pickImage(level),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: AppColors.surfaceGray,
            child: FloorplanCanvas(
              level: level,
              padding: const EdgeInsets.all(12),
              selectedPinId: _selectedPinId,
              onTapPlan: _busy ? null : (f) => _addPinAt(level, f),
              onPinTap: _busy ? null : (p) => _editPin(level, p),
              onPinMoved: _busy ? null : _movePin,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.divider))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Icon(AppIcons.info, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap the plan to add a pin. Hold a pin to drag it. Tap a pin to edit. ${level.pins.length} pin${level.pins.length == 1 ? '' : 's'} on ${level.name}.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                    ),
                  ),
                  TextButton.icon(onPressed: _busy ? null : () => _pickImage(level), icon: const Icon(AppIcons.image, size: 16), label: const Text('Replace')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LevelTabs extends StatelessWidget {
  const _LevelTabs({required this.levels, required this.currentId, required this.onPick, required this.onMenu, required this.onAdd});
  final List<FloorLevel> levels;
  final String? currentId;
  final ValueChanged<String> onPick;
  final ValueChanged<FloorLevel> onMenu;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.divider))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        children: [
          for (final l in levels)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: l.id == currentId ? AppColors.textPrimary : AppColors.surfaceGray,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => l.id == currentId ? onMenu(l) : onPick(l.id),
                  onLongPress: () => onMenu(l),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.name,
                          style: TextStyle(fontFamily: AppFonts.display, fontSize: 17, fontWeight: FontWeight.w800, color: l.id == currentId ? AppColors.onInk : AppColors.textPrimary),
                        ),
                        const SizedBox(width: 4),
                        if (!l.hasImage)
                          Icon(AppIcons.warning, size: 14, color: l.id == currentId ? AppColors.onInk : AppColors.brand)
                        else if (l.id == currentId)
                          Icon(AppIcons.caretDown, size: 14, color: AppColors.onInk),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Material(
            color: AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onAdd,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.plus, size: 16, color: AppColors.textPrimary),
                    const SizedBox(width: 4),
                    Text('Level', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindGrid extends StatelessWidget {
  const _KindGrid({required this.onPick, this.selected});
  final ValueChanged<PinKind> onPick;
  final PinKind? selected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in PinKind.values)
          SizedBox(
            width: 84,
            child: Material(
              color: k == selected ? k.color.withValues(alpha: 0.15) : AppColors.surfaceGray,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onPick(k),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: k.color, shape: BoxShape.circle),
                        child: Icon(k.icon, color: Colors.white, size: 18),
                      ),
                      const SizedBox(height: 6),
                      Text(k.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PinEdit {
  const _PinEdit({this.pin, this.delete = false});
  final FloorPin? pin;
  final bool delete;
}

class _PinEditSheet extends ConsumerStatefulWidget {
  const _PinEditSheet({required this.pin, required this.levelName});
  final FloorPin pin;
  final String levelName;

  @override
  ConsumerState<_PinEditSheet> createState() => _PinEditSheetState();
}

class _PinEditSheetState extends ConsumerState<_PinEditSheet> {
  late final _label = TextEditingController(text: widget.pin.label);
  late PinKind _kind = widget.pin.kind;
  late String? _partnerId = widget.pin.partnerVendorId;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pickPartner() async {
    final v = await showModalBottomSheet<PublicVendor>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _PartnerPicker(),
    );
    if (v != null) setState(() => _partnerId = v.id);
  }

  @override
  Widget build(BuildContext context) {
    final partners = ref.watch(partnersDirectoryProvider).value ?? const <PublicVendor>[];
    final partner = partners.where((p) => p.id == _partnerId).firstOrNull;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pin on ${widget.levelName}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 4),
              _KindGrid(selected: _kind, onPick: (k) => setState(() => _kind = k)),
              if (_kind == PinKind.booth) ...[
                const SizedBox(height: 14),
                Material(
                  color: AppColors.surfaceGray,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: partner?.logoUrl != null
                        ? CircleAvatar(backgroundImage: CachedNetworkImageProvider(partner!.logoUrl!))
                        : const Icon(AppIcons.storefront),
                    title: Text(_partnerId == null ? 'Link a partner (optional)' : (partner?.name ?? 'Linked partner'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(_partnerId == null ? 'Members can open their page from the booth.' : 'Tap to change', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    trailing: _partnerId == null
                        ? const Icon(AppIcons.caretRight)
                        : IconButton(tooltip: 'Unlink', icon: const Icon(AppIcons.x), onPressed: () => setState(() => _partnerId = null)),
                    onTap: _pickPartner,
                  ),
                ),
              ],
              if (_kind.hasZoneQr) ...[
                const SizedBox(height: 10),
                Text('This pin gets a printable zone QR. Find it under Print zone QRs.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _PinEdit(
                    pin: widget.pin.copyWith(
                      kind: _kind,
                      label: _label.text.trim(),
                      partnerVendorId: _kind == PinKind.booth ? _partnerId : null,
                      clearPartner: _kind != PinKind.booth || _partnerId == null,
                    ),
                  ),
                ),
                child: const Text('Save'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, const _PinEdit(delete: true)),
                icon: const Icon(AppIcons.trash, size: 18, color: AppColors.danger),
                label: const Text('Delete pin', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable list of TT Spot partners, for linking a booth.
class _PartnerPicker extends ConsumerStatefulWidget {
  const _PartnerPicker();

  @override
  ConsumerState<_PartnerPicker> createState() => _PartnerPickerState();
}

class _PartnerPickerState extends ConsumerState<_PartnerPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final partners = ref.watch(partnersDirectoryProvider);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(AppIcons.magnifyingGlass), hintText: 'Search partners'),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: partners.when(
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => Center(child: Text(friendlyError(e))),
                data: (all) {
                  final list = _q.isEmpty ? all : all.where((p) => p.name.toLowerCase().contains(_q) || (p.address ?? '').toLowerCase().contains(_q)).toList();
                  if (list.isEmpty) return Center(child: Text('No partners match.', style: TextStyle(color: AppColors.textSecondary)));
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return ListTile(
                        leading: p.logoUrl != null ? CircleAvatar(backgroundImage: CachedNetworkImageProvider(p.logoUrl!)) : const CircleAvatar(child: Icon(AppIcons.storefront, size: 18)),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: p.address == null ? null : Text(p.address!, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reorder / rename / delete levels. Pops with the new order (top floor first)
/// when the member taps Done after dragging.
class _LevelsSheet extends StatefulWidget {
  const _LevelsSheet({required this.levels, required this.onRename, required this.onDelete});
  final List<FloorLevel> levels;
  final ValueChanged<FloorLevel> onRename;
  final ValueChanged<FloorLevel> onDelete;

  @override
  State<_LevelsSheet> createState() => _LevelsSheetState();
}

class _LevelsSheetState extends State<_LevelsSheet> {
  late final List<FloorLevel> _order = [...widget.levels];
  bool _moved = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  const Expanded(child: Text('Levels', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  FilledButton(onPressed: () => Navigator.pop(context, _moved ? _order : null), child: const Text('Done')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Top floor at the top. Drag the handle to reorder.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorderItem: (from, to) => setState(() {
                  _order.insert(to, _order.removeAt(from));
                  _moved = true;
                }),
                itemBuilder: (_, i) {
                  final l = _order[i];
                  return ListTile(
                    key: ValueKey(l.id),
                    leading: ReorderableDragStartListener(index: i, child: const Icon(AppIcons.list)),
                    title: Text(l.name, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
                    subtitle: Text(l.hasImage ? '${l.pins.length} pin${l.pins.length == 1 ? '' : 's'}' : 'No plan image yet'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(tooltip: 'Rename', icon: const Icon(AppIcons.pencilSimple), onPressed: () => widget.onRename(l)),
                        IconButton(tooltip: 'Delete', icon: const Icon(AppIcons.trash, color: AppColors.danger), onPressed: () => widget.onDelete(l)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
