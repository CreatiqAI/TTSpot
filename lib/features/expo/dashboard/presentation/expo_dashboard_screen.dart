import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../events/application/event_providers.dart';
import '../../expo_routes.dart';
import '../application/dashboard_providers.dart';
import '../data/dashboard_repository.dart';
import '../domain/csv.dart';
import '../domain/dashboard.dart';
import 'arrivals_chart.dart';

/// Host: live numbers and CSV exports. Refreshes every 30 s while on screen.
class ExpoDashboardScreen extends ConsumerStatefulWidget {
  const ExpoDashboardScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<ExpoDashboardScreen> createState() => _ExpoDashboardScreenState();
}

class _ExpoDashboardScreenState extends ConsumerState<ExpoDashboardScreen> with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  String? _exporting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg && !_foreground) _tick();
    _foreground = fg;
  }

  /// Only while this screen is the one on top and the app is open.
  void _tick() {
    if (!mounted || !_foreground) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    ref.invalidate(expoDashboardProvider(widget.eventId));
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _export(String kind) async {
    setState(() => _exporting = kind);
    try {
      final repo = ref.read(dashboardRepositoryProvider);
      final title = ref.read(eventDetailProvider(widget.eventId)).value?.event.title ?? 'event';
      final String csv;
      final String name;
      if (kind == 'checkins') {
        final rows = await repo.exportCheckins(widget.eventId);
        if (rows.isEmpty) throw const AppException('No check-ins yet.');
        csv = checkinsCsv(rows);
        name = 'ttspot-checkins-${csvSlug(title)}.csv';
      } else {
        final rows = await repo.exportBoothVisits(widget.eventId);
        if (rows.isEmpty) throw const AppException('No booth visits yet.');
        csv = boothVisitsCsv(rows);
        name = 'ttspot-booth-visits-${csvSlug(title)}.csv';
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: name));
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(expoDashboardProvider(widget.eventId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Live dashboard'),
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(friendlyError(e), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(onPressed: () => ref.invalidate(expoDashboardProvider(widget.eventId)), child: const Text('Try again')),
              ],
            ),
          ),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () => ref.refresh(expoDashboardProvider(widget.eventId).future),
          child: DashboardBody(
            eventId: widget.eventId,
            data: d,
            exporting: _exporting,
            onExport: _export,
          ),
        ),
      ),
    );
  }
}

/// The scrolling content. Public so tests can pump it with fixed data.
class DashboardBody extends StatelessWidget {
  const DashboardBody({super.key, required this.eventId, required this.data, this.exporting, required this.onExport});
  final String eventId;
  final ExpoDashboard data;
  final String? exporting;
  final ValueChanged<String> onExport;

  @override
  Widget build(BuildContext context) {
    final t = data.totals;
    final d = data;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                d.generatedAt == null ? 'Live' : 'Live · updated ${formatTime(d.generatedAt!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ---- big numbers
        _Tile(
          hero: true,
          icon: AppIcons.userCheck,
          label: 'Checked in',
          value: t.checkedIn,
          sub: t.going > 0 ? '${t.going} going' : null,
        ),
        const SizedBox(height: 10),
        _TileGrid(children: [
          _Tile(icon: AppIcons.clipboardText, label: 'Registered', value: t.registrations, sub: t.registrations > 0 ? '${t.contactOk} share contact' : null),
          _Tile(icon: AppIcons.stamp, label: 'Stamps', value: t.stamps, sub: t.stamps > 0 ? '${t.stampers} ${t.stampers == 1 ? 'person' : 'people'}' : null),
          _Tile(icon: AppIcons.addressBook, label: 'Leads', value: t.leads, sub: t.exhibitors > 0 ? '${t.exhibitors} exhibitors' : null),
          _Tile(icon: AppIcons.heart, label: 'Votes', value: t.votes),
        ]),
        if (t.freebies > 0 || t.rallyCompleted > 0) ...[
          const SizedBox(height: 10),
          _Card(
            child: Column(
              children: [
                if (t.freebies > 0) _StatLine(icon: AppIcons.gift, label: 'Freebies handed out', value: '${t.freebies}'),
                if (t.rallyCompleted > 0)
                  _StatLine(icon: AppIcons.flagCheckered, label: 'Stamp rally done', value: '${t.rallyCompleted}', sub: '${t.rallyRedeemed} collected'),
              ],
            ),
          ),
        ],

        // ---- arrivals
        const _Head('ARRIVALS BY HOUR'),
        _Card(
          child: d.arrivals.isEmpty
              ? Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No check-ins yet.', style: TextStyle(color: AppColors.textSecondary)))
              : ArrivalsChart(hours: d.arrivals),
        ),

        // ---- who
        if (d.makes.isNotEmpty) ...[
          const _Head('TOP CAR MAKES'),
          _Card(child: _Bars(items: d.makes)),
        ],
        if (d.states.isNotEmpty) ...[
          const _Head('WHERE THEY ARE FROM'),
          _Card(child: _Bars(items: d.states)),
        ],

        // ---- booths
        if (d.booths.isNotEmpty) ...[
          const _Head('BOOTHS'),
          _Card(
            child: Column(
              children: [
                for (var i = 0; i < d.booths.length; i++) _BoothRow(rank: i + 1, booth: d.booths[i]),
              ],
            ),
          ),
        ],

        // ---- draws
        if (d.draws.isNotEmpty) ...[
          const _Head('LUCKY DRAW'),
          _Card(
            child: Column(
              children: [
                for (final dr in d.draws)
                  _StatLine(
                    icon: dr.drawn ? AppIcons.confetti : AppIcons.gift,
                    label: dr.title,
                    sub: [
                      if (dr.drawn) 'Drawn' else if (dr.drawAt != null) formatTime(dr.drawAt!),
                      if (dr.rollCall) 'roll call ${dr.presenceMinutes} min before',
                    ].join(' · '),
                    value: dr.drawn ? '${dr.entrants ?? 0}' : (dr.rollCall ? '${dr.confirmed}' : '${dr.entrants ?? 0}'),
                    valueSub: dr.drawn ? 'entries' : (dr.rollCall ? 'confirmed' : 'in so far'),
                    onTap: () => context.push(Routes.eventDraws(eventId)),
                  ),
              ],
            ),
          ),
        ],

        // ---- votes
        if (d.contests.isNotEmpty) ...[
          const _Head('SHOW CAR VOTE'),
          _Card(
            child: Column(
              children: [
                for (final c in d.contests)
                  _StatLine(
                    icon: AppIcons.trophy,
                    label: c.title,
                    sub: [
                      '${c.entries} car${c.entries == 1 ? '' : 's'}',
                      if (c.pending > 0) '${c.pending} waiting',
                      if (c.ended) 'closed',
                    ].join(' · '),
                    value: '${c.votes}',
                    valueSub: c.votes == 1 ? 'vote' : 'votes',
                    onTap: () => context.push(ExpoRoutes.contestEditor(eventId)),
                  ),
              ],
            ),
          ),
        ],

        // ---- exports
        const _Head('EXPORT'),
        _ExportButton(label: 'Check-ins CSV', busy: exporting == 'checkins', enabled: exporting == null, onTap: () => onExport('checkins')),
        const SizedBox(height: 8),
        _ExportButton(label: 'Booth visits CSV', busy: exporting == 'visits', enabled: exporting == null, onTap: () => onExport('visits')),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(AppIcons.presentationChart, color: AppColors.textPrimary),
          title: const Text('Turnout report', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Verified check-ins to share with sponsors.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
          onTap: () => context.push(Routes.eventReport(eventId)),
        ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: child,
      );
}

/// Two tiles a row; each as tall as its content.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const gap = 10.0;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in children) SizedBox(width: w, child: t)]);
      });
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value, this.sub, this.hero = false});
  final IconData icon;
  final String label;
  final int value;
  final String? sub;
  final bool hero;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: hero ? AppColors.ink : AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: hero ? Colors.white70 : AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: hero ? Colors.white70 : AppColors.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _compact(value),
                style: TextStyle(fontFamily: AppFonts.display, fontSize: hero ? 56 : 38, fontWeight: FontWeight.w800, height: 1.05, color: hero ? Colors.white : AppColors.textPrimary),
              ),
            ),
            if (sub != null)
              Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: hero ? Colors.white70 : AppColors.textSecondary)),
          ],
        ),
      );
}

/// 1234 → "1,234".
String _compact(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.icon, required this.label, required this.value, this.sub, this.valueSub, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final String? valueSub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if ((sub ?? '').isNotEmpty) Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  if (valueSub != null) Text(valueSub!, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
        ),
      );
}

/// A ranked list with a thin bar under each label.
class _Bars extends StatelessWidget {
  const _Bars({required this.items});
  final List<LabelCount> items;

  @override
  Widget build(BuildContext context) {
    final max = items.fold<int>(1, (m, e) => e.count > m ? e.count : m);
    return Column(
      children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                    const SizedBox(width: 8),
                    Text('${e.count}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (_, c) => Container(
                    width: (c.maxWidth * e.count / max).clamp(4.0, c.maxWidth),
                    height: 6,
                    decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BoothRow extends StatelessWidget {
  const _BoothRow({required this.rank, required this.booth});
  final int rank;
  final BoothStat booth;

  @override
  Widget build(BuildContext context) {
    final b = booth;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank', style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [
                    if (b.booths.isNotEmpty) b.booths.join(' '),
                    '${b.stamps} stamp${b.stamps == 1 ? '' : 's'}',
                    if (b.freebies > 0) '${b.freebies} freebie${b.freebies == 1 ? '' : 's'}',
                    '${b.leads} lead${b.leads == 1 ? '' : 's'}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${b.stamps}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.label, required this.busy, required this.enabled, required this.onTap});
  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.fileCsv, size: 18, color: AppColors.textPrimary),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}
