import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../expo_routes.dart';
import '../application/stamps_providers.dart';
import '../domain/stamps_models.dart';

/// Booth staff: members whose pass we scanned; export CSV.
/// `?pass=<code>` (staff of several booths scanned a pass): ask which booth
/// to save it for.
class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key, required this.eventId, required this.exhibitorId});
  final String eventId;
  final String exhibitorId;

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  bool _handledPass = false;
  bool _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledPass) return;
    _handledPass = true;
    String? pass;
    try {
      pass = GoRouterState.of(context).uri.queryParameters['pass'];
    } catch (_) {
      pass = null; // not under go_router (tests)
    }
    if (pass != null && pass.isNotEmpty) {
      final code = pass;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickBoothAndSave(code));
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickBoothAndSave(String passCode) async {
    try {
      final booths = await ref.read(myStaffBoothsProvider(widget.eventId).future);
      if (!mounted) return;
      if (booths.isEmpty) return _toast('Only booth staff can save leads.');
      StaffBooth? pick = booths.first;
      if (booths.length > 1) {
        pick = await showModalBottomSheet<StaffBooth>(
          context: context,
          useRootNavigator: true,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (ctx) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('Save this lead for', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  for (final b in booths)
                    ListTile(
                      leading: const Icon(AppIcons.storefront),
                      title: Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: b.booths.isEmpty ? null : Text(boothLabel(b.booths)),
                      onTap: () => Navigator.pop(ctx, b),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      }
      if (pick == null || !mounted) return;
      final r = await ref.read(stampsActionsProvider).saveLead(eventId: widget.eventId, passCode: passCode, exhibitorId: pick.id);
      if (!mounted) return;
      _toast(r.title);
      if (r.exhibitorId != widget.exhibitorId) context.pushReplacement(ExpoRoutes.leads(widget.eventId, r.exhibitorId));
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  Future<void> _export(List<Lead> leads, String boothName) async {
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final safe = boothName.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final file = File('${dir.path}/ttspot-leads-${safe.isEmpty ? 'booth' : safe}.csv');
      await file.writeAsString(leadsCsv(leads), encoding: utf8, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], text: '$boothName leads'));
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _editNote(Lead l) async {
    final note = await showDialog<String>(context: context, builder: (_) => _NoteDialog(initial: l.note ?? '', name: l.name));
    if (note == null || !mounted) return;
    try {
      await ref.read(stampsActionsProvider).setLeadNote(widget.exhibitorId, l.id, note);
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  void _showContact(Lead l) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            if ((l.phone ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(AppIcons.phone),
                title: Text(l.phone!),
                trailing: IconButton(
                  icon: const Icon(AppIcons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: l.phone!));
                    Navigator.pop(ctx);
                    _toast('Phone copied.');
                  },
                ),
                onTap: () => launchUrl(Uri(scheme: 'tel', path: l.phone)),
              ),
            if ((l.email ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(AppIcons.envelope),
                title: Text(l.email!, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(AppIcons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: l.email!));
                    Navigator.pop(ctx);
                    _toast('Email copied.');
                  },
                ),
                onTap: () => launchUrl(Uri(scheme: 'mailto', path: l.email)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(exhibitorLeadsProvider(widget.exhibitorId));
    final booths = ref.watch(myStaffBoothsProvider(widget.eventId)).value ?? const <StaffBooth>[];
    String name = 'Leads';
    for (final b in booths) {
      if (b.id == widget.exhibitorId) name = b.name;
    }
    final leads = async.value ?? const <Lead>[];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (leads.isNotEmpty)
            _exporting
                ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(tooltip: 'Export CSV', icon: const Icon(AppIcons.fileCsv), onPressed: () => _export(leads, name)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: PrimaryButton(label: 'Scan a pass', icon: AppIcons.scan, onPressed: () => context.push(Routes.scan)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (leads) => RefreshIndicator(
          onRefresh: () => ref.refresh(exhibitorLeadsProvider(widget.exhibitorId).future),
          child: leads.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 40),
                    EmptyState(
                      titi: TitiPose.clipboard,
                      title: 'No leads yet',
                      subtitle: "Scan a visitor's event pass to save their name and car. Phone and email come along when they share them.",
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        leads.length == 1 ? '1 lead' : '${leads.length} leads',
                        style: const TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        '${leads.where((l) => l.hasContact).length} shared phone and email',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                    for (final l in leads) LeadTile(lead: l, onNote: () => _editNote(l), onContact: l.hasContact ? () => _showContact(l) : null),
                  ],
                ),
        ),
      ),
    );
  }
}

/// One lead: avatar, name, @handle · state, car, time, note; contact icon when shared.
class LeadTile extends StatelessWidget {
  const LeadTile({super.key, required this.lead, required this.onNote, this.onContact});
  final Lead lead;
  final VoidCallback onNote;
  final VoidCallback? onContact;

  @override
  Widget build(BuildContext context) {
    final l = lead;
    final line1 = [if (l.username != null) '@${l.username}', if ((l.state ?? '').isNotEmpty) l.state!].join(' · ');
    final when = isSameDay(l.createdAt, DateTime.now()) ? formatTime(l.createdAt) : formatEventDate(l.createdAt);
    final line2 = [if (l.car != null) l.car!, when].join(' · ');
    return InkWell(
      onTap: onNote,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(url: l.avatarUrl, name: l.name, seed: l.userId, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  if (line1.isNotEmpty) Text(line1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(AppIcons.notePencil, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          (l.note ?? '').isEmpty ? 'Add a note' : l.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: (l.note ?? '').isEmpty ? AppColors.textMuted : AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onContact != null)
              IconButton(tooltip: 'Contact', icon: const Icon(AppIcons.addressBook), color: AppColors.success, onPressed: onContact),
          ],
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial, required this.name});
  final String initial;
  final String name;
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Note on ${widget.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
        content: TextField(
          controller: _c,
          autofocus: true,
          maxLength: 300,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Wants a quote for brake pads'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
        ],
      );
}
