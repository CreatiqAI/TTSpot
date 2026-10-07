import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/pop_or_home.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../floorplan/application/floorplan_providers.dart';
import '../../../floorplan/presentation/floorplan_editor_screen.dart';
import '../../../vendors/domain/vendor.dart';
import '../application/exhibitors_providers.dart';
import '../data/exhibitors_repository.dart';
import '../domain/exhibitor.dart';
import '../domain/exhibitor_import.dart';
import 'exhibitor_widgets.dart';
import 'exhibitors_screen.dart';

/// Host: add, import (paste CSV) and edit exhibitors; link booth pins.
class ExhibitorsEditorScreen extends ConsumerStatefulWidget {
  const ExhibitorsEditorScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<ExhibitorsEditorScreen> createState() => _ExhibitorsEditorScreenState();
}

class _ExhibitorsEditorScreenState extends ConsumerState<ExhibitorsEditorScreen> {
  String _q = '';
  bool _linking = false;

  ExhibitorsRepository get _repo => ref.read(exhibitorsRepositoryProvider);

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _refresh() {
    ref.invalidate(eventExhibitorsProvider(widget.eventId));
    ref.invalidate(floorLevelsProvider(widget.eventId));
  }

  Future<void> _link() async {
    setState(() => _linking = true);
    try {
      final n = await _repo.linkBoothPins(widget.eventId);
      _refresh();
      if (mounted) _toast(n == 0 ? 'No booth pins match. Add booth codes on the floor plan.' : (n == 1 ? '1 booth linked.' : '$n booths linked.'));
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _edit([Exhibitor? e]) async {
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _ExhibitorForm(eventId: widget.eventId, exhibitor: e), fullscreenDialog: e == null),
    );
    if (saved != null && mounted) _toast(saved);
  }

  Future<void> _import(int existing) async {
    final done = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _ImportPage(eventId: widget.eventId, existing: existing), fullscreenDialog: true),
    );
    if (done != null && mounted) _toast(done);
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(isMeetHostProvider(widget.eventId));
    final async = ref.watch(eventExhibitorsProvider(widget.eventId));
    final count = async.value?.length ?? 0;
    final isHost = host.value ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(count == 0 ? 'Exhibitors' : 'Exhibitors · $count'),
        actions: [
          if (isHost) IconButton(tooltip: 'Paste list', icon: const Icon(AppIcons.clipboardText), onPressed: () => _import(count)),
        ],
      ),
      floatingActionButton: isHost
          ? FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(AppIcons.plus), label: const Text('Add exhibitor'))
          : null,
      body: host.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => EmptyState(icon: AppIcons.wifiSlash, title: "Couldn't check access", subtitle: friendlyError(e)),
        data: (isHost) {
          if (!isHost) return const EmptyState(icon: AppIcons.lock, title: 'Host only', subtitle: 'Only the organizer can edit exhibitors.');
          return async.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => EmptyState(
              icon: AppIcons.wifiSlash,
              title: "Couldn't load exhibitors",
              subtitle: friendlyError(e),
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(eventExhibitorsProvider(widget.eventId)),
            ),
            data: (all) {
              if (all.isEmpty) {
                return EmptyState(
                  titi: TitiPose.clipboard,
                  icon: AppIcons.storefront,
                  title: 'No exhibitors yet',
                  subtitle: 'Paste your exhibitor list from a spreadsheet, or add them one by one.',
                  actionLabel: 'Paste list',
                  onAction: () => _import(0),
                );
              }
              final list = all.where((e) => e.matches(_q)).toList();
              final pins = all.fold<int>(0, (n, e) => n + e.pinCount);
              return RefreshIndicator(
                onRefresh: () => ref.refresh(eventExhibitorsProvider(widget.eventId).future),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: list.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '${all.length} exhibitor${all.length == 1 ? '' : 's'} · $pins booth${pins == 1 ? '' : 's'} on the floor plan',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _import(all.length),
                                        icon: const Icon(AppIcons.clipboardText, size: 18),
                                        label: const Text('Paste list'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: _linking ? null : _link,
                                        icon: _linking
                                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(AppIcons.link, size: 18),
                                        label: const Text('Link to floor plan booths'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (all.length > 8) ...[
                              const SizedBox(height: 10),
                              TextField(
                                onChanged: (v) => setState(() => _q = v),
                                decoration: const InputDecoration(
                                  hintText: 'Search name, booth, category',
                                  prefixIcon: Icon(AppIcons.magnifyingGlass, size: 20),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }
                    final e = list[i - 1];
                    return ExhibitorRow(
                      key: ValueKey(e.id),
                      exhibitor: e,
                      onTap: () => _edit(e),
                      trailing: e.booths.isNotEmpty && e.pinCount == 0
                          ? Tooltip(message: 'No booth pin on the plan', child: Icon(AppIcons.warning, size: 18, color: AppColors.textMuted))
                          : Icon(AppIcons.pencilSimple, size: 18, color: AppColors.textMuted),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ form ---

class _ExhibitorForm extends ConsumerStatefulWidget {
  const _ExhibitorForm({required this.eventId, this.exhibitor});
  final String eventId;
  final Exhibitor? exhibitor;

  @override
  ConsumerState<_ExhibitorForm> createState() => _ExhibitorFormState();
}

class _ExhibitorFormState extends ConsumerState<_ExhibitorForm> {
  late final Exhibitor? _e = widget.exhibitor;
  late final _name = TextEditingController(text: _e?.name ?? '');
  late final _booths = TextEditingController(text: _e?.boothsLabel ?? '');
  late final _category = TextEditingController(text: _e?.category ?? '');
  late final _country = TextEditingController(text: _e?.country ?? '');
  late final _phone = TextEditingController(text: _e?.phone ?? '');
  late final _email = TextEditingController(text: _e?.email ?? '');
  late final _website = TextEditingController(text: _e?.website ?? '');
  late final _about = TextEditingController(text: _e?.about ?? '');
  late String? _partnerId = _e?.partnerVendorId;
  late String? _partnerName = _e?.partnerName;
  late String? _partnerLogo = _e?.partnerLogo;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _booths, _category, _country, _phone, _email, _website, _about]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickPartner() async {
    final v = await showModalBottomSheet<PublicVendor>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const PartnerPickerSheet(),
    );
    if (v == null) return;
    setState(() {
      _partnerId = v.id;
      _partnerName = v.name;
      _partnerLogo = v.logoUrl;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _toast('Add a name.');
    final email = _email.text.trim();
    if (email.isNotEmpty && !email.contains('@')) return _toast('That email looks wrong.');
    setState(() => _busy = true);
    final repo = ref.read(exhibitorsRepositoryProvider);
    try {
      await repo.save(
        id: _e?.id,
        eventId: widget.eventId,
        name: name,
        booths: parseBoothCodes(_booths.text),
        category: _category.text,
        country: _country.text,
        phone: _phone.text,
        email: email,
        website: _website.text,
        about: _about.text,
        partnerVendorId: _partnerId,
      );
      try {
        await repo.linkBoothPins(widget.eventId);
      } catch (_) {/* the save stands; linking can be redone */}
      ref.invalidate(eventExhibitorsProvider(widget.eventId));
      ref.invalidate(floorLevelsProvider(widget.eventId));
      if (mounted) Navigator.pop(context, _e == null ? 'Added $name.' : 'Saved.');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(friendlyError(e));
      }
    }
  }

  Future<void> _delete() async {
    final e = _e;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${e.name}?'),
        content: const Text('Its booths on the floor plan stay, unlinked.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(exhibitorsRepositoryProvider).delete(e.id);
      ref.invalidate(eventExhibitorsProvider(widget.eventId));
      ref.invalidate(floorLevelsProvider(widget.eventId));
      if (mounted) Navigator.pop(context, 'Deleted ${e.name}.');
    } catch (err) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(friendlyError(err));
      }
    }
  }

  Widget _field(TextEditingController c, String label, {String? hint, int maxLength = 120, TextInputType? keyboard, int maxLines = 1, TextCapitalization caps = TextCapitalization.sentences}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: TextField(
          controller: c,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: 1,
          keyboardType: keyboard,
          textCapitalization: caps,
          decoration: InputDecoration(labelText: label, hintText: hint, counterText: maxLines > 1 ? null : ''),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editing = _e != null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => Navigator.pop(context)),
        title: Text(editing ? 'Edit exhibitor' : 'Add exhibitor'),
        actions: [
          if (editing) IconButton(tooltip: 'Delete', icon: const Icon(AppIcons.trash, color: AppColors.danger), onPressed: _busy ? null : _delete),
          TextButton(onPressed: _busy ? null : _save, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _field(_name, 'Name', hint: 'Company or brand', caps: TextCapitalization.words),
            _field(_booths, 'Booth codes', hint: 'A019, A024', maxLength: 300, caps: TextCapitalization.characters),
            _field(_category, 'Category', hint: 'e.g. Wheels, Car care', maxLength: 60, caps: TextCapitalization.words),
            _field(_country, 'Country', hint: 'e.g. Malaysia', maxLength: 40, caps: TextCapitalization.words),
            _field(_phone, 'Phone', maxLength: 60, keyboard: TextInputType.phone, caps: TextCapitalization.none),
            _field(_email, 'Email', keyboard: TextInputType.emailAddress, caps: TextCapitalization.none),
            _field(_website, 'Website', hint: 'acme.com', maxLength: 200, keyboard: TextInputType.url, caps: TextCapitalization.none),
            _field(_about, 'About', maxLength: 1000, maxLines: 6),
            const SizedBox(height: 8),
            Material(
              color: _partnerId == null ? AppColors.surfaceGray : kPartnerGold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: _partnerLogo != null ? CircleAvatar(backgroundImage: CachedNetworkImageProvider(_partnerLogo!)) : const Icon(AppIcons.storefront),
                title: Text(_partnerId == null ? 'TT Spot partner (optional)' : (_partnerName ?? 'Linked partner'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  _partnerId == null ? 'Partner booths show their logo on the plan.' : 'Gold logo on the plan, View shop button.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                trailing: _partnerId == null
                    ? const Icon(AppIcons.caretRight)
                    : IconButton(
                        tooltip: 'Unlink',
                        icon: const Icon(AppIcons.x),
                        onPressed: () => setState(() {
                          _partnerId = null;
                          _partnerName = null;
                          _partnerLogo = null;
                        }),
                      ),
                onTap: _pickPartner,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- import ---

class _ImportPage extends ConsumerStatefulWidget {
  const _ImportPage({required this.eventId, required this.existing});
  final String eventId;
  final int existing;

  @override
  ConsumerState<_ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<_ImportPage> {
  final _text = TextEditingController();
  ExhibitorImport _parsed = const ExhibitorImport();
  bool _replace = false;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String v) => setState(() => _parsed = v.trim().isEmpty ? const ExhibitorImport() : parseExhibitorList(v));

  Future<void> _run() async {
    final rows = _parsed.rows;
    if (rows.isEmpty) return;
    if (_replace && widget.existing > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Replace ${widget.existing} exhibitor${widget.existing == 1 ? '' : 's'}?'),
          content: const Text('The current list is deleted first, with its stamps, freebies and leads.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    final repo = ref.read(exhibitorsRepositoryProvider);
    try {
      final n = await repo.import(widget.eventId, rows, replace: _replace);
      var linked = 0;
      try {
        linked = await repo.linkBoothPins(widget.eventId);
      } catch (_) {}
      ref.invalidate(eventExhibitorsProvider(widget.eventId));
      ref.invalidate(floorLevelsProvider(widget.eventId));
      if (mounted) Navigator.pop(context, 'Imported $n. $linked booth${linked == 1 ? '' : 's'} linked.');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _parsed;
    final hasText = _text.text.trim().isNotEmpty;
    final found = {for (final e in p.columns.entries) e.key};
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => Navigator.pop(context)),
        title: const Text('Paste list'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Text(
              'Copy the table from Excel or Google Sheets, header row included. Columns: Name, Booth, Category, Country, Phone, Email, Website, About.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              onChanged: _onChanged,
              minLines: 8,
              maxLines: 14,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.3),
              decoration: const InputDecoration(
                hintText: 'Name\tBooth\tCategory\nAcme Wheels\tA019, A024\tWheels',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            if (hasText && p.error != null)
              _Note(icon: AppIcons.warning, text: p.error!, danger: true)
            else if (p.rows.isNotEmpty) ...[
              Text(
                '${p.rows.length} exhibitor${p.rows.length == 1 ? '' : 's'} found${p.skipped > 0 ? ' · ${p.skipped} row${p.skipped == 1 ? '' : 's'} without a name skipped' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in ImportField.values)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: found.contains(f) ? AppColors.success.withValues(alpha: 0.12) : AppColors.surfaceGray,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(found.contains(f) ? AppIcons.check : AppIcons.minus, size: 12, color: found.contains(f) ? AppColors.success : AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(_fieldLabel(f), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: found.contains(f) ? AppColors.textPrimary : AppColors.textMuted)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              for (final r in p.rows.take(5)) _PreviewRow(row: r),
              if (p.rows.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('+ ${p.rows.length - 5} more', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _replace,
              onChanged: _busy ? null : (v) => setState(() => _replace = v),
              title: const Text('Replace existing', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                widget.existing == 0
                    ? 'No exhibitors yet.'
                    : (_replace ? 'Deletes the ${widget.existing} already here first.' : 'Off: same names are updated, new ones added.'),
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy || !p.ok ? null : _run,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(p.ok ? 'Import ${p.rows.length}' : 'Import'),
            ),
          ],
        ),
      ),
    );
  }

  static String _fieldLabel(ImportField f) => switch (f) {
        ImportField.name => 'Name',
        ImportField.booths => 'Booth',
        ImportField.category => 'Category',
        ImportField.country => 'Country',
        ImportField.phone => 'Phone',
        ImportField.email => 'Email',
        ImportField.website => 'Website',
        ImportField.about => 'About',
      };
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.row});
  final ExhibitorImportRow row;

  @override
  Widget build(BuildContext context) {
    final sub = [if (row.booths.isNotEmpty) row.booths.join(', '), if (row.category != null) row.category!, if (row.country != null) row.country!].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.danger = false});
  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: danger ? AppColors.danger : AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: danger ? AppColors.danger : AppColors.textSecondary))),
        ],
      );
}
