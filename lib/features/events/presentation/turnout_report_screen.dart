import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';

/// Verified turnout for one meet: what a host shows sponsors and partners.
class TurnoutReport {
  const TurnoutReport(this.m);
  final Map<String, dynamic> m;

  String get title => m['title'] as String? ?? 'Meet';
  DateTime get startsAt => DateTime.parse(m['starts_at'] as String).toLocal();
  int _i(String k) => (m[k] as num?)?.toInt() ?? 0;
  int get rsvps => _i('rsvps');
  int get checkedIn => _i('checked_in');
  int get rsvpShowed => _i('rsvp_showed');
  int get walkIns => _i('walk_ins');
  int get firstTimers => _i('first_timers');
  int get noCar => _i('no_car');
  int get scanned => ((m['by_source'] as Map?)?['qr'] as num?)?.toInt() ?? 0;
  int? get showRate => rsvps == 0 ? null : (rsvpShowed * 100 / rsvps).round();

  List<({String label, int count})> _list(String key, String Function(Map) label) => [
        for (final r in (m[key] as List? ?? const []))
          (label: label(r as Map), count: (r['count'] as num).toInt()),
      ];
  List<({String label, int count})> get makes => _list('by_make', (r) => r['make'] as String);
  List<({String label, int count})> get models => _list('top_models', (r) => '${r['make']} ${r['model']}');
  List<({String label, int count})> get clubs => _list('clubs', (r) => r['name'] as String);
  List<({DateTime at, int count})> get arrivals => [
        for (final r in (m['arrivals'] as List? ?? const []))
          (at: DateTime.parse((r as Map)['at'] as String).toLocal(), count: (r['count'] as num).toInt()),
      ];

  /// Plain-text version for WhatsApp / email to a sponsor.
  String get summary {
    final b = StringBuffer()
      ..writeln('$title · ${formatEventDate(startsAt)}')
      ..writeln('$checkedIn cars checked in on TT Spot (location-verified)')
      ..writeln('$rsvps RSVPs${showRate == null ? '' : ', $showRate % showed up'} · $walkIns walk-ins · $firstTimers first meet ever');
    if (makes.isNotEmpty) b.writeln('Top makes: ${makes.take(5).map((x) => '${x.label} ${x.count}').join(', ')}');
    if (models.isNotEmpty) b.writeln('Top models: ${models.take(3).map((x) => '${x.label} (${x.count})').join(', ')}');
    return b.toString().trim();
  }
}

final turnoutReportProvider = FutureProvider.autoDispose.family<TurnoutReport, String>((ref, eventId) async {
  final res = await ref.read(supabaseProvider).rpc('event_turnout_report', params: {'p_event': eventId});
  return TurnoutReport((res as Map).cast<String, dynamic>());
});

class TurnoutReportScreen extends ConsumerWidget {
  const TurnoutReportScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(turnoutReportProvider(eventId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Turnout report'),
        actions: [
          if (report.value != null)
            IconButton(
              tooltip: 'Share',
              icon: const Icon(AppIcons.shareFat),
              onPressed: () => SharePlus.instance.share(ShareParams(text: report.value!.summary, subject: 'Turnout: ${report.value!.title}')),
            ),
        ],
      ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (r) => RefreshIndicator(
          onRefresh: () => ref.refresh(turnoutReportProvider(eventId).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(r.title, style: AppText.sectionTitle.copyWith(fontSize: 20)),
              const SizedBox(height: 2),
              Text(formatEventDate(r.startsAt), style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              _Hero(value: r.checkedIn, label: 'cars checked in', note: 'Every check-in is proven on the spot: QR scan at the meet or GPS within range.'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _Tile(value: '${r.rsvps}', label: 'RSVPs')),
                  const SizedBox(width: 8),
                  Expanded(child: _Tile(value: r.showRate == null ? '–' : '${r.showRate} %', label: 'RSVPs showed')),
                  const SizedBox(width: 8),
                  Expanded(child: _Tile(value: '${r.walkIns}', label: 'Walk-ins')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _Tile(value: '${r.firstTimers}', label: 'First meet ever')),
                  const SizedBox(width: 8),
                  Expanded(child: _Tile(value: '${r.scanned}', label: 'Scanned your QR')),
                  const SizedBox(width: 8),
                  Expanded(child: _Tile(value: '${r.checkedIn - r.firstTimers}', label: 'Returning')),
                ],
              ),
              if (r.checkedIn == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text('No check-ins yet. Show your check-in QR at the meet, or members tap "I\'m here" when they arrive.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
                ),
              if (r.makes.isNotEmpty) ...[
                const _Head('Cars by make'),
                _Bars(rows: r.makes, total: r.checkedIn),
                if (r.noCar > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r.noCar} without a car in their garage', style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ],
              if (r.models.isNotEmpty) ...[
                const _Head('Top models'),
                _Bars(rows: r.models, total: r.checkedIn),
              ],
              if (r.arrivals.length > 1) ...[
                const _Head('Arrivals (15-minute slots)'),
                _Arrivals(rows: r.arrivals),
              ],
              if (r.clubs.isNotEmpty) ...[
                const _Head('Clubs that came'),
                _Bars(rows: r.clubs, total: r.checkedIn),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.value, required this.label, required this.note});
  final int value;
  final String label;
  final String note;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$value', style: TextStyle(fontFamily: AppFonts.display, fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1)),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(AppIcons.sealCheck, size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                Expanded(child: Text(note, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35))),
              ],
            ),
          ],
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );
}

/// Ranked horizontal bars, one hue, value in text beside each bar.
class _Bars extends StatelessWidget {
  const _Bars({required this.rows, required this.total});
  final List<({String label, int count})> rows;
  final int total;
  @override
  Widget build(BuildContext context) {
    final max = rows.fold<int>(1, (m, r) => r.count > m ? r.count : m);
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 120, child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textPrimary))),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: (c.maxWidth * r.count / max).clamp(4, c.maxWidth),
                        height: 12,
                        decoration: const BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.horizontal(right: Radius.circular(4))),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(
                    total == 0 ? '${r.count}' : '${r.count} · ${(r.count * 100 / total).round()} %',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Check-ins per 15-minute slot. Tap a bar for its time and count.
class _Arrivals extends StatelessWidget {
  const _Arrivals({required this.rows});
  final List<({DateTime at, int count})> rows;
  @override
  Widget build(BuildContext context) {
    final max = rows.fold<int>(1, (m, r) => r.count > m ? r.count : m);
    const h = 96.0;
    return Column(
      children: [
        SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final r in rows)
                Expanded(
                  child: Tooltip(
                    message: '${formatTime(r.at)} · ${r.count} check-in${r.count == 1 ? '' : 's'}',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1), // 2px gap between bars
                      child: Container(
                        height: (h * r.count / max).clamp(4, h),
                        decoration: const BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.vertical(top: Radius.circular(4))),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(formatTime(rows.first.at), style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            const Spacer(),
            Text('peak ${rows.fold<int>(0, (m, r) => r.count > m ? r.count : m)} in 15 min', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            const Spacer(),
            Text(formatTime(rows.last.at), style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
      ],
    );
  }
}
