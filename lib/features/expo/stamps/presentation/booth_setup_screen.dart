import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/pop_or_home.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/open_external.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../expo_routes.dart';
import '../application/stamps_providers.dart';
import '../domain/stamps_models.dart';
import 'booth_qr_sheet_screen.dart';

/// Host: stamp stops, freebies, rally goal, booth staff, printable booth QR codes.
class BoothSetupScreen extends ConsumerWidget {
  const BoothSetupScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(boothSetupProvider(eventId));
    final rows = async.value ?? const <BoothSetupRow>[];
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Stamps & booths'),
        actions: [
          if (rows.any((r) => r.stampStop))
            IconButton(
              tooltip: 'Booth QR codes',
              icon: const Icon(AppIcons.qrCode),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BoothQrSheetScreen(eventId: eventId))),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (rows) => rows.isEmpty
            ? EmptyState(
                titi: TitiPose.clipboard,
                title: 'No exhibitors yet',
                subtitle: 'Add the exhibitors first, then pick which booths give stamps.',
                actionLabel: 'Add exhibitors',
                onAction: () => context.push(ExpoRoutes.exhibitorsEditor(eventId)),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(boothSetupProvider(eventId).future),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    _RallyCard(eventId: eventId, stops: rows.where((r) => r.stampStop).length),
                    const SizedBox(height: 14),
                    if (rows.any((r) => r.stampStop)) ...[
                      SecondaryButton(
                        label: 'Booth QR codes',
                        icon: AppIcons.printer,
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BoothQrSheetScreen(eventId: eventId))),
                      ),
                      const SizedBox(height: 14),
                    ],
                    for (final r in rows) ...[
                      _BoothCard(key: ValueKey(r.id), eventId: eventId, row: r),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

Future<void> _run(BuildContext context, Future<void> Function() f, [String? done]) async {
  try {
    await f();
    if (done != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

/// Goal (stamps needed) + the reward collected at the counter.
class _RallyCard extends ConsumerStatefulWidget {
  const _RallyCard({required this.eventId, required this.stops});
  final String eventId;
  final int stops;

  @override
  ConsumerState<_RallyCard> createState() => _RallyCardState();
}

class _RallyCardState extends ConsumerState<_RallyCard> {
  final _goal = TextEditingController();
  final _reward = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _goal.dispose();
    _reward.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _goal.text.trim();
    final goal = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && (goal == null || goal < 1 || goal > 50)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The goal must be 1 to 50 stamps.')));
      return;
    }
    setState(() => _saving = true);
    await _run(context, () => ref.read(stampsActionsProvider).setRally(widget.eventId, goal: goal, reward: _reward.text), goal == null ? 'Stamp rally off.' : 'Stamp rally saved.');
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(rallySettingsProvider(widget.eventId)).value;
    if (!_loaded && s != null) {
      _loaded = true;
      _goal.text = s.goal?.toString() ?? '';
      _reward.text = s.reward ?? '';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(AppIcons.trophy, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Stamp rally', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              Text('${widget.stops} stamp stops', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Members who collect the goal get the reward at the counter. Leave the goal empty for no rally.',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _goal,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                  decoration: const InputDecoration(labelText: 'Goal', hintText: '8', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _reward,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Reward', hintText: 'Free T-shirt', isDense: true, counterText: ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PrimaryButton(label: 'Save rally', loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

/// One exhibitor: stamp stop switch, freebie + stock, staff, code.
class _BoothCard extends ConsumerStatefulWidget {
  const _BoothCard({super.key, required this.eventId, required this.row});
  final String eventId;
  final BoothSetupRow row;

  @override
  ConsumerState<_BoothCard> createState() => _BoothCardState();
}

class _BoothCardState extends ConsumerState<_BoothCard> {
  late final _freebie = TextEditingController(text: widget.row.freebie ?? '');
  late final _limit = TextEditingController(text: widget.row.freebieLimit?.toString() ?? '');
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _BoothCard old) {
    super.didUpdateWidget(old);
    // Server copy changed and I have no unsaved edits: take it.
    if (!_dirtyAgainst(old.row)) {
      _freebie.text = widget.row.freebie ?? '';
      _limit.text = widget.row.freebieLimit?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _freebie.dispose();
    _limit.dispose();
    super.dispose();
  }

  bool _dirtyAgainst(BoothSetupRow r) => _freebie.text.trim() != (r.freebie ?? '') || _limit.text.trim() != (r.freebieLimit?.toString() ?? '');

  bool get _dirty => _dirtyAgainst(widget.row);

  Future<void> _save({bool? stop}) async {
    final rawLimit = _limit.text.trim();
    final limit = rawLimit.isEmpty ? null : int.tryParse(rawLimit);
    if (rawLimit.isNotEmpty && (limit == null || limit < 1)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock must be 1 or more. Leave it empty for no limit.')));
      return;
    }
    setState(() => _saving = true);
    await _run(
      context,
      () => ref.read(stampsActionsProvider).setBoothStamp(widget.eventId, widget.row.id, stop: stop ?? widget.row.stampStop, freebie: _freebie.text, limit: limit),
      stop == null ? 'Saved.' : null,
    );
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _addStaff() async {
    final handle = await showDialog<String>(context: context, builder: (_) => const _HandleDialog());
    if (handle == null || handle.trim().isEmpty || !mounted) return;
    await _run(context, () async {
      final s = await ref.read(stampsActionsProvider).addStaff(widget.eventId, widget.row.id, handle);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${s.name} is booth staff.')));
      }
    });
  }

  Future<void> _removeStaff(BoothStaff s) async {
    final ok = await confirmSheet(context, title: 'Remove ${s.name}?', body: "They stop seeing this booth's leads.", confirm: 'Remove');
    if (!ok || !mounted) return;
    await _run(context, () => ref.read(stampsActionsProvider).removeStaff(widget.eventId, widget.row.id, s.userId), 'Removed ${s.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final booth = boothLabel(r.booths);
    final stats = [
      if (r.stampStop) '${r.stamps} stamps',
      if (r.freebie != null) r.freebieLimit == null ? '${r.freebiesRedeemed} given' : '${r.freebiesRedeemed} of ${r.freebieLimit} given',
      if (r.leads > 0) '${r.leads} leads',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                    if (booth.isNotEmpty || stats.isNotEmpty)
                      Text([booth, stats].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(AppIcons.dotsThreeVertical, color: AppColors.textSecondary),
                onSelected: (v) async {
                  if (v == 'rotate') {
                    final ok = await confirmSheet(context, title: 'New stamp code?', body: 'The printed QR for this booth stops working. Print the new one.', confirm: 'New code');
                    if (!ok || !context.mounted) return;
                    await _run(context, () => ref.read(stampsActionsProvider).rotateCode(widget.eventId, r.id), 'New code ready. Print the booth QR again.');
                  } else if (v == 'leads') {
                    context.push(ExpoRoutes.leads(widget.eventId, r.id));
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rotate', child: Text('New stamp code')),
                  const PopupMenuItem(value: 'leads', child: Text('Leads')),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                const Icon(AppIcons.stamp, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Stamp stop', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
                Switch(value: r.stampStop, onChanged: _saving ? null : (v) => _save(stop: v)),
              ],
            ),
          ),
          if (r.stampStop) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _freebie,
                      maxLength: 80,
                      onChanged: (_) => setState(() {}),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Freebie (optional)', hintText: 'Keychain', isDense: true, counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 92,
                    child: TextField(
                      controller: _limit,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      decoration: const InputDecoration(labelText: 'Stock', hintText: 'No limit', isDense: true),
                    ),
                  ),
                ],
              ),
            ),
            if (_dirty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 18)),
                    onPressed: _saving ? null : () => _save(),
                    child: const Text('Save'),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final s in r.staff)
                  InputChip(
                    label: Text(s.username == null ? s.name : '@${s.username}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onDeleted: () => _removeStaff(s),
                    deleteIcon: const Icon(AppIcons.x, size: 14),
                    visualDensity: VisualDensity.compact,
                  ),
                ActionChip(
                  avatar: const Icon(AppIcons.userPlus, size: 16),
                  label: Text(r.staff.isEmpty ? 'Add booth staff' : 'Add'),
                  onPressed: _addStaff,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HandleDialog extends StatefulWidget {
  const _HandleDialog();
  @override
  State<_HandleDialog> createState() => _HandleDialogState();
}

class _HandleDialogState extends State<_HandleDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add booth staff'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('They can scan passes to save leads.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            TextField(
              controller: _c,
              autofocus: true,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => Navigator.pop(context, v),
              decoration: const InputDecoration(prefixText: '@', hintText: 'handle', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Add')),
        ],
      );
}
