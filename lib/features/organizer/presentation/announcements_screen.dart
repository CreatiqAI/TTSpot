import 'package:flutter/cupertino.dart' show CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/pop_or_home.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart' show confirmSheet;
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/wheel_picker.dart';
import '../../events/application/event_providers.dart';
import '../application/organizer_providers.dart';
import '../domain/organizer_models.dart';

/// Write an announcement (now or at a time) and see what's scheduled / sent.
/// Sending is allowed from a day before the meet until a day after it ends.
class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  Audience _audience = Audience.linked;
  DateTime? _sendAt; // null = now
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickTime() async {
    final ev = ref.read(eventDetailProvider(widget.eventId)).value?.event;
    final now = DateTime.now();
    final min = now.add(const Duration(minutes: 2));
    final picked = await showWheelPicker(
      context,
      initial: _sendAt ?? (ev != null && ev.startsAt.isAfter(min) ? ev.startsAt : min.add(const Duration(minutes: 13))),
      mode: CupertinoDatePickerMode.dateAndTime,
      min: min,
      max: ev?.closesAt.add(const Duration(days: 1)),
      title: 'Send at',
    );
    if (picked != null) setState(() => _sendAt = picked);
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack('Add a title and a message.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(organizerActionsProvider).announce(eventId: widget.eventId, title: title, body: body, audience: _audience, sendAt: _sendAt);
      _title.clear();
      _body.clear();
      final when = _sendAt;
      setState(() => _sendAt = null);
      _snack(when == null ? 'Sent.' : 'Scheduled for ${formatEventDate(when)}.');
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(EventAnnouncement a) async {
    final ok = await confirmSheet(context, title: 'Cancel this announcement?', body: '"${a.title}" won\'t go out.', confirm: 'Cancel it', cancel: 'Keep', icon: AppIcons.xCircle);
    if (!ok) return;
    try {
      await ref.read(organizerActionsProvider).cancelAnnouncement(widget.eventId, a.id);
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(eventAnnouncementsProvider(widget.eventId));
    final count = ref.watch(audienceCountProvider((eventId: widget.eventId, audience: _audience))).value;
    final ev = ref.watch(eventDetailProvider(widget.eventId)).value?.event;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Announcements'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(eventAnnouncementsProvider(widget.eventId));
          ref.invalidate(audienceCountProvider((eventId: widget.eventId, audience: _audience)));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            TextField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Parking moved to level 3', counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              maxLength: 500,
              maxLines: 4,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Message', hintText: 'What should everyone know?'),
            ),
            const SizedBox(height: 6),
            Text('SEND TO', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in Audience.values)
                  ChoiceChip(label: Text(a.label), selected: _audience == a, showCheckmark: false, onSelected: (_) => setState(() => _audience = a)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_audience.hint}.${count == null ? '' : ' $count ${count == 1 ? 'person' : 'people'} right now.'}',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Send now'), icon: Icon(AppIcons.paperPlaneTilt, size: 16)),
                      ButtonSegment(value: true, label: Text('Schedule'), icon: Icon(AppIcons.clock, size: 16)),
                    ],
                    selected: {_sendAt != null},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      if (s.first) {
                        _pickTime();
                      } else {
                        setState(() => _sendAt = null);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (_sendAt != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickTime,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(AppIcons.calendarBlank, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(formatEventDate(_sendAt!), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('Change', style: AppText.link),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            PrimaryButton(label: _sendAt == null ? 'Send announcement' : 'Schedule announcement', loading: _busy, onPressed: _send),
            const SizedBox(height: 8),
            Text(
              ev == null
                  ? 'Announcements go out from a day before the meet until a day after it ends.'
                  : 'Announcements can go out between ${formatEventDate(ev.startsAt.subtract(const Duration(days: 1)))} and ${formatEventDate(ev.closesAt.add(const Duration(days: 1)))}.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
            ),
            const SizedBox(height: 22),
            Text('SCHEDULED AND SENT', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            list.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (e, _) => Text(friendlyError(e)),
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Nothing yet. Your first announcement shows up here.', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : Column(children: [for (final a in items) _AnnouncementTile(a: a, onCancel: () => _cancel(a))]),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({required this.a, required this.onCancel});
  final EventAnnouncement a;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final (String status, Color color) = a.isCancelled
        ? ('Cancelled', AppColors.textMuted)
        : a.isSent
            ? ('Sent ${formatTime(a.sentAt!)} · ${a.recipients ?? 0} ${a.recipients == 1 ? 'person' : 'people'}', AppColors.success)
            : ('Scheduled ${formatEventDate(a.sendAt)}', AppColors.brand);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(AppIcons.megaphone, size: 20, color: AppColors.textSecondary)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title, style: TextStyle(fontWeight: FontWeight.w700, color: a.isCancelled ? AppColors.textMuted : AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(a.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text('$status · ${a.audience.label}${a.authorUsername == null ? '' : ' · @${a.authorUsername}'}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
          if (a.isScheduled)
            IconButton(tooltip: 'Cancel', icon: Icon(AppIcons.xCircle, color: AppColors.textSecondary), onPressed: onCancel),
        ],
      ),
    );
  }
}
