import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart' show confirmSheet;
import '../../../core/widgets/user_avatar.dart';
import '../application/organizer_providers.dart';
import '../domain/organizer_models.dart';

/// The stage screen, built to be mirrored to a TV: a big live entrant
/// counter before the draw, then a reveal that rolls names and stops on each
/// winner (grand prize last), then the results with live claim status.
/// The reveal only replays what the server already drew.
class LuckyDrawStageScreen extends ConsumerStatefulWidget {
  const LuckyDrawStageScreen({super.key, required this.eventId, required this.drawId});
  final String eventId;
  final String drawId;

  @override
  ConsumerState<LuckyDrawStageScreen> createState() => _LuckyDrawStageScreenState();
}

enum _Phase { waiting, ready, reveal, results }

class _LuckyDrawStageScreenState extends ConsumerState<LuckyDrawStageScreen> {
  Timer? _poll;
  Timer? _clock;
  _Phase? _phase; // null = follow the draw's status
  int _index = 0;
  bool _stopped = false;
  bool _running = false;

  static const _bg = Color(0xFF0B0B0D);

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _phase == _Phase.reveal) return;
      ref.invalidate(drawStageProvider(widget.drawId));
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_phase ?? _Phase.waiting) == _Phase.waiting) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _run(DrawStage s) async {
    final ok = await confirmSheet(
      context,
      title: 'Run the draw now?',
      body: 'Entries freeze now. ${s.entrantCount} member${s.entrantCount == 1 ? ' is' : 's are'} in. Winners get a push straight away.',
      confirm: 'Run draw',
      icon: AppIcons.gift,
    );
    if (!ok) return;
    setState(() => _running = true);
    try {
      await ref.read(organizerActionsProvider).runDraw(widget.eventId, widget.drawId);
      await ref.read(drawStageProvider(widget.drawId).future);
      if (mounted) _startReveal();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _startReveal() => setState(() {
        _phase = _Phase.reveal;
        _index = 0;
        _stopped = false;
      });

  void _next(int total) {
    if (_index + 1 >= total) {
      setState(() => _phase = _Phase.results);
    } else {
      setState(() {
        _index++;
        _stopped = false;
      });
    }
  }

  Future<void> _forfeit(StageWinner w) async {
    final ok = await confirmSheet(
      context,
      title: 'Pass ${w.prize ?? 'this prize'} on?',
      body: '${w.displayName} loses it and the next alternate gets a push to come to the stage.',
      confirm: 'Pass it on',
      icon: AppIcons.arrowRight,
    );
    if (!ok) return;
    try {
      await ref.read(organizerActionsProvider).forfeit(widget.eventId, widget.drawId, w.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = ref.watch(drawStageProvider(widget.drawId));
    final role = ref.watch(myEventRoleProvider(widget.eventId)).value ?? EventRole.none;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(icon: const Icon(AppIcons.x), onPressed: () => context.pop()),
          title: Text(stage.value?.title ?? 'Lucky draw', style: const TextStyle(color: Colors.white)),
          actions: [
            if (stage.value?.status == DrawStatus.drawn && _phase != _Phase.reveal)
              IconButton(tooltip: 'Replay reveal', icon: const Icon(AppIcons.play), onPressed: _startReveal),
            IconButton(tooltip: 'Scan prize claim', icon: const Icon(AppIcons.scan), onPressed: () => context.push(Routes.prizeScan)),
          ],
        ),
        body: stage.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
          error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)))),
          data: (s) {
            if (s.status == DrawStatus.cancelled) {
              return const _Center(pose: TitiPose.sad, title: 'Draw cancelled', line: 'This lucky draw was cancelled by the host.');
            }
            final phase = _phase ?? (s.status == DrawStatus.drawn ? _Phase.ready : _Phase.waiting);
            if (s.status == DrawStatus.scheduled || phase == _Phase.waiting) {
              return _Waiting(stage: s, canRun: role.isHostCircle, running: _running, onRun: () => _run(s));
            }
            final order = s.prizeWinners.reversed.toList(); // grand prize (listed first) revealed last
            return switch (phase) {
              _Phase.ready => _Ready(stage: s, onReveal: order.isEmpty ? () => setState(() => _phase = _Phase.results) : _startReveal, onResults: () => setState(() => _phase = _Phase.results)),
              _Phase.reveal when order.isNotEmpty => _Reveal(
                  key: ValueKey('reveal-$_index'),
                  stage: s,
                  winner: order[_index.clamp(0, order.length - 1)],
                  step: _index,
                  total: order.length,
                  stopped: _stopped,
                  onStopped: () => setState(() => _stopped = true),
                  onNext: () => _next(order.length),
                ),
              _ => _Results(stage: s, canManage: role.isHostCircle, onForfeit: _forfeit),
            };
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- waiting ---

class _Waiting extends StatelessWidget {
  const _Waiting({required this.stage, required this.canRun, required this.running, required this.onRun});
  final DrawStage stage;
  final bool canRun;
  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final left = stage.drawAt.difference(DateTime.now());
    final due = left.isNegative;
    final countdown = due
        ? 'Draw time!'
        : left.inHours > 0
            ? 'Draw at ${formatTime(stage.drawAt)}'
            : 'Draw in ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    return LayoutBuilder(
      builder: (context, c) {
        final big = math.min(c.maxWidth * 0.42, c.maxHeight * 0.3).clamp(90.0, 260.0);
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          children: [
            const SizedBox(height: 8),
            Center(child: Titi(due ? TitiPose.rolling : TitiPose.gift, height: math.min(170, c.maxHeight * 0.2))),
            const SizedBox(height: 8),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: stage.entrantCount.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text(
                  '${v.round()}',
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: big, height: 0.95, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
            const Center(
              child: Text('IN THE DRAW', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 4)),
            ),
            const SizedBox(height: 10),
            Text(
              [
                '${stage.checkedIn} checked in',
                if (stage.hasRollCall)
                  DateTime.now().isBefore(stage.drawAt.subtract(Duration(minutes: stage.presenceMinutes!)))
                      ? 'roll call ${formatTime(stage.drawAt.subtract(Duration(minutes: stage.presenceMinutes!)))}'
                      : '${stage.presenceConfirmed} confirmed here',
                'entries close ${formatTime(stage.cutoffAt)}',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 22),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(countdown, style: const TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in stage.prizes)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('${p.quantity > 1 ? '${p.quantity}× ' : ''}${p.name}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            if (canRun)
              Center(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size(240, 54)),
                  onPressed: running || stage.status != DrawStatus.scheduled ? null : onRun,
                  icon: running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(AppIcons.gift),
                  label: Text(due ? 'Run the draw' : 'Run the draw now', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              )
            else
              const Text('The host runs the draw. This screen updates on its own.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 10),
            Text(
              due ? 'TT Spot runs it automatically within a minute if nobody taps.' : 'Or leave it: TT Spot runs it automatically at ${formatTime(stage.drawAt)}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12.5),
            ),
            const SizedBox(height: 26),
            const _FinePrint(),
            if (stage.seedHash != null) ...[
              const SizedBox(height: 6),
              Text('Sealed seed ${stage.seedHash!.substring(0, 16)}…', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white24, fontSize: 11, fontFamily: 'monospace')),
            ],
          ],
        );
      },
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.stage, required this.onReveal, required this.onResults});
  final DrawStage stage;
  final VoidCallback onReveal;
  final VoidCallback onResults;

  @override
  Widget build(BuildContext context) {
    final n = stage.prizeWinners.length;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Titi(TitiPose.celebrate, height: 170),
            const SizedBox(height: 12),
            Text(n == 0 ? 'Nobody was eligible' : 'The winners are in', textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(height: 10),
            Text(
              '${stage.entrantCount} ${stage.entrantCount == 1 ? 'entry' : 'entries'} · $n winner${n == 1 ? '' : 's'} · drawn ${stage.drawnAt == null ? '' : formatTime(stage.drawnAt!)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 15),
            ),
            const SizedBox(height: 28),
            if (n > 0)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: Colors.white, minimumSize: const Size(260, 56)),
                onPressed: onReveal,
                icon: const Icon(AppIcons.sparkle),
                label: const Text('Reveal winners', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            const SizedBox(height: 10),
            TextButton(onPressed: onResults, style: TextButton.styleFrom(foregroundColor: Colors.white70), child: const Text('Skip to the results')),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- reveal ---

class _Reveal extends StatelessWidget {
  const _Reveal({
    super.key,
    required this.stage,
    required this.winner,
    required this.step,
    required this.total,
    required this.stopped,
    required this.onStopped,
    required this.onNext,
  });
  final DrawStage stage;
  final StageWinner winner;
  final int step;
  final int total;
  final bool stopped;
  final VoidCallback onStopped;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // Roll entry numbers when we have them (the stage calls out "#0427");
    // names are masked on the big screen.
    final byNumber = winner.entryNo != null;
    final pool = byNumber
        ? [for (final n in stage.entryNos.isNotEmpty ? stage.entryNos : [for (final w in stage.winners) ?w.entryNo]) formatEntryNo(n)]
        : [for (final n in stage.names.isNotEmpty ? stage.names : stage.winners.map((w) => w.displayName)) maskName(n)];
    final target = byNumber ? formatEntryNo(winner.entryNo!) : maskName(winner.displayName);
    final last = step == total - 1;
    return LayoutBuilder(
      builder: (context, c) {
        final nameSize = math.min(c.maxWidth * 0.13, c.maxHeight * 0.11).clamp(40.0, 120.0);
        return Stack(
          children: [
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    last && total > 1 ? 'GRAND PRIZE' : 'PRIZE ${total - step} OF $total',
                    style: const TextStyle(color: Colors.white54, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 3),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(winner.prize ?? 'Prize', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppFonts.display, color: AppColors.brand, fontSize: nameSize * 0.55, fontWeight: FontWeight.w800, height: 1)),
                  ),
                  SizedBox(height: c.maxHeight * 0.05),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: stopped
                        ? Titi(TitiPose.celebrate, key: const ValueKey('titi'), height: math.min(180, c.maxHeight * 0.24))
                        : SizedBox(key: const ValueKey('gap'), height: math.min(180, c.maxHeight * 0.24), child: const Center(child: Titi(TitiPose.rolling, height: 120))),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      height: nameSize * (byNumber ? 1.6 : 1.25),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _RollingName(names: pool, target: target, size: byNumber ? nameSize * 1.3 : nameSize, onDone: onStopped),
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: stopped ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: Column(
                      children: [
                        if (byNumber)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              maskName(winner.displayName),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: (nameSize * 0.42).clamp(22.0, 52.0), fontWeight: FontWeight.w700),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          stage.mustBePresent ? 'Come to the stage within ${stage.claimMinutes} min with your claim QR' : 'Check your phone for your claim QR',
                          style: const TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: c.maxHeight * 0.05),
                  AnimatedOpacity(
                    opacity: stopped ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size(220, 52)),
                      onPressed: stopped ? onNext : null,
                      icon: Icon(last ? AppIcons.trophy : AppIcons.arrowRight),
                      label: Text(last ? 'All winners' : 'Next prize', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
            if (stopped) const Positioned.fill(child: IgnorePointer(child: _Confetti())),
          ],
        );
      },
    );
  }
}

/// Cycles random names, slowing down, then lands on [target].
class _RollingName extends StatefulWidget {
  const _RollingName({required this.names, required this.target, required this.size, required this.onDone});
  final List<String> names;
  final String target;
  final double size;
  final VoidCallback onDone;

  @override
  State<_RollingName> createState() => _RollingNameState();
}

class _RollingNameState extends State<_RollingName> {
  final _rand = math.Random();
  Timer? _t;
  late String _shown;
  int _delay = 45;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _shown = _pick();
    _tick();
  }

  String _pick() {
    final pool = widget.names.where((n) => n != widget.target).toList();
    if (pool.isEmpty) return widget.target;
    return pool[_rand.nextInt(pool.length)];
  }

  void _tick() {
    _t = Timer(Duration(milliseconds: _delay), () {
      if (!mounted) return;
      if (_delay > 420) {
        setState(() {
          _shown = widget.target;
          _done = true;
        });
        HapticFeedback.heavyImpact();
        widget.onDone();
        return;
      }
      HapticFeedback.selectionClick();
      setState(() => _shown = _pick());
      _delay = (_delay * 1.09).round() + 2;
      _tick();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: _done ? 1.08 : 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: Text(
          _shown,
          maxLines: 1,
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: widget.size,
            height: 1.05,
            fontWeight: FontWeight.w800,
            color: _done ? Colors.white : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      );
}

/// A one-shot burst of paper confetti falling from the top.
class _Confetti extends StatefulWidget {
  const _Confetti();
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))..forward();
  late final List<_Bit> _bits = () {
    final r = math.Random();
    const colors = [AppColors.brand, Color(0xFFFFC53D), Color(0xFF2B7CFF), Color(0xFF1DA750), Colors.white, Color(0xFFEC4899)];
    return List.generate(
      150,
      (_) => _Bit(
        x: r.nextDouble(),
        delay: r.nextDouble() * 0.35,
        speed: 0.55 + r.nextDouble() * 0.6,
        drift: (r.nextDouble() - 0.5) * 0.25,
        spin: (r.nextDouble() - 0.5) * 14,
        w: 6 + r.nextDouble() * 7,
        h: 9 + r.nextDouble() * 9,
        color: colors[r.nextInt(colors.length)],
      ),
    );
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_bits, _c.value)));
}

class _Bit {
  const _Bit({required this.x, required this.delay, required this.speed, required this.drift, required this.spin, required this.w, required this.h, required this.color});
  final double x, delay, speed, drift, spin, w, h;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<_Bit> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final b in bits) {
      final p = ((t - b.delay) / (1 - b.delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final y = -20 + p * b.speed * (size.height + 60) * 1.2;
      final x = (b.x + b.drift * p + math.sin(p * 9 + b.x * 20) * 0.02) * size.width;
      paint.color = b.color.withValues(alpha: p > 0.85 ? (1 - p) / 0.15 : 1);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p * b.spin);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: b.w, height: b.h * (0.4 + 0.6 * math.cos(p * b.spin).abs())), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// ------------------------------------------------------------- results ---

class _Results extends StatelessWidget {
  const _Results({required this.stage, required this.canManage, required this.onForfeit});
  final DrawStage stage;
  final bool canManage;
  final ValueChanged<StageWinner> onForfeit;

  @override
  Widget build(BuildContext context) {
    final winners = stage.winners.where((w) => w.hasPrize).toList()
      ..sort((a, b) => a.prizeSort != b.prizeSort ? a.prizeSort.compareTo(b.prizeSort) : a.rank.compareTo(b.rank));
    final standby = stage.standby;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        Text('WINNERS', style: const TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 2)),
        const SizedBox(height: 8),
        if (winners.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Nobody was eligible for this draw.', style: TextStyle(color: Colors.white70)),
          ),
        for (final w in winners) _WinnerTile(w: w, mustBePresent: stage.mustBePresent, onForfeit: canManage && w.status == 'pending' ? () => onForfeit(w) : null),
        if (standby.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('STANDBY', style: TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 2)),
          const SizedBox(height: 4),
          const Text('If a prize is not claimed in time, it goes to the next one here.', style: TextStyle(color: Colors.white38, fontSize: 12.5)),
          const SizedBox(height: 8),
          for (final w in standby) _WinnerTile(w: w, mustBePresent: stage.mustBePresent),
        ],
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DRAW RECORD', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text('${stage.entrantCount} entries frozen at ${stage.drawnAt == null ? '' : formatEventDate(stage.drawnAt!)} (cut-off ${formatTime(stage.cutoffAt)})'),
                if (stage.entrantsHash != null) Text('Entry list sha256 ${stage.entrantsHash!.substring(0, 16)}…', style: const TextStyle(fontFamily: 'monospace')),
                if (stage.seedHash != null) Text('Seed sha256 ${stage.seedHash!.substring(0, 16)}… (sealed before the draw)', style: const TextStyle(fontFamily: 'monospace')),
                if (stage.seedReveal != null) Text('Seed ${stage.seedReveal!.substring(0, 16)}… (revealed)', style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 4),
                const Text('Ranked by sha256(seed + member id). Anyone with the seed and the list can check it.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _FinePrint(),
      ],
    );
  }
}

class _WinnerTile extends StatelessWidget {
  const _WinnerTile({required this.w, required this.mustBePresent, this.onForfeit});
  final StageWinner w;
  final bool mustBePresent;
  final VoidCallback? onForfeit;

  @override
  Widget build(BuildContext context) {
    final open = w.status == 'pending' && w.hasPrize;
    final left = w.expiresAt?.difference(DateTime.now());
    final (String label, Color color) = switch (w.status) {
      'claimed' => ('Collected', const Color(0xFF1DA750)),
      'expired' => ('Missed', Colors.white38),
      'forfeited' => ('Passed on', Colors.white38),
      _ when !w.hasPrize => ('#${w.rank}', Colors.white54),
      _ when left != null && left.isNegative => ('Time up', AppColors.brand),
      _ when left != null => ('${left.inMinutes} min left', const Color(0xFFFFC53D)),
      _ => ('Waiting', const Color(0xFFFFC53D)),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(
        children: [
          UserAvatar(url: w.avatarUrl, name: w.displayName, seed: w.userId, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                Text(
                  [if (w.entryNo != null) formatEntryNo(w.entryNo!), if (w.prize != null) w.prize!, if (w.promotedAt != null) 'from standby'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
          if (open && onForfeit != null)
            PopupMenuButton<String>(
              icon: const Icon(AppIcons.dotsThreeVertical, color: Colors.white54),
              onSelected: (_) => onForfeit!(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'forfeit', child: Text('Not here: pass it on'))],
            ),
        ],
      ),
    );
  }
}

class _FinePrint extends StatelessWidget {
  const _FinePrint();
  @override
  Widget build(BuildContext context) => const Text(
        'Free to enter. TT Spot provides the platform; prizes are provided by the organizer. Apple is not a sponsor.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white38, fontSize: 11.5, height: 1.4),
      );
}

class _Center extends StatelessWidget {
  const _Center({required this.pose, required this.title, required this.line});
  final TitiPose pose;
  final String title;
  final String line;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Titi(pose, height: 150),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(line, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      );
}
