import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../map/presentation/widgets/car_marker.dart' show kCarColorLabels;
import '../../domain/car_recognition.dart';

/// Shared by onboarding ("Your ride") and Add car: the scanning state while
/// the recogniser looks at a photo, and the "found it" pieces after.

/// How long the scanning card stays up at minimum, so the status rows get to
/// tick through before the reveal.
const kCarScanHold = Duration(milliseconds: 2600);

/// The picked photo with a scan line sweeping it, TiTi peeking in with his
/// magnifier, and three status rows driven by the clock.
class CarScanningCard extends StatefulWidget {
  const CarScanningCard({super.key, required this.image, required this.startedAt, required this.done});
  final ImageProvider image;
  final DateTime startedAt;
  /// The recogniser is back: every row goes green.
  final bool done;

  @override
  State<CarScanningCard> createState() => _CarScanningCardState();
}

class _CarScanningCardState extends State<CarScanningCard> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  static const _rows = ['Reading make and model', 'Working out the year', 'Pulling engine and gearbox specs'];
  static const _startsAt = [Duration.zero, Duration(milliseconds: 900), Duration(milliseconds: 2200)];

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(24)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(image: widget.image, fit: BoxFit.cover, gaplessPlayback: true),
                ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
                AnimatedBuilder(
                  animation: _sweep,
                  builder: (_, _) => Align(
                    alignment: Alignment(0, -1 + 2 * Curves.easeInOut.transform(_sweep.value)),
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.8), blurRadius: 16, spreadRadius: 3)],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  right: 12,
                  bottom: 12,
                  child: TitiAvatar(TitiPose.magnifier, size: 60, background: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Align(
          alignment: Alignment.centerRight,
          child: TitiBubble('Hold on, having a look at this one…', tailRight: true, maxWidth: 280),
        ),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: _sweep,
          builder: (_, _) {
            final elapsed = DateTime.now().difference(widget.startedAt);
            return Column(
              children: [
                for (var i = 0; i < _rows.length; i++)
                  _StatusRow(
                    label: _rows[i],
                    state: widget.done || (i + 1 < _startsAt.length && elapsed >= _startsAt[i + 1])
                        ? _RowState.done
                        : elapsed >= _startsAt[i]
                            ? _RowState.active
                            : _RowState.pending,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

enum _RowState { pending, active, done }

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.state});
  final String label;
  final _RowState state;

  @override
  Widget build(BuildContext context) {
    final Widget dot = switch (state) {
      _RowState.done => Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
          child: const Icon(AppIcons.check, size: 14, color: Colors.white),
        ),
      _RowState.active => const SizedBox(
          width: 26,
          height: 26,
          child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.brand)),
        ),
      _RowState.pending => Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.border, width: 2)),
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          dot,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: state == _RowState.pending ? FontWeight.w500 : FontWeight.w700,
                color: state == _RowState.pending ? AppColors.textSecondary : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "MAKE · YEAR" over the model name in the big display face, with an
/// optional action (the Edit pill) on the right.
class CarFoundTitle extends StatelessWidget {
  const CarFoundTitle({super.key, required this.make, required this.model, required this.year, this.trailing});
  final String make;
  final String model;
  /// A typed year, or the guess's range; '' for none.
  final String year;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final makeYear = [if (make.isNotEmpty) make.toUpperCase(), if (year.isNotEmpty) year].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(makeYear.isEmpty ? 'MAKE · YEAR' : makeYear, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                model.isEmpty ? 'YOUR CAR' : model,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 48,
                  height: 46 / 48,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: model.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Padding(padding: const EdgeInsets.only(top: 6), child: trailing),
            ],
          ],
        ),
      ],
    );
  }
}

/// The spec tiles: the recogniser's spec line split into parts, plus the
/// body style. Only while the guess still describes the typed make + model.
List<(String, String)> carSpecTiles(CarRecognition? g, String make, String model) {
  if (g == null || !g.matches(make, model)) return const [];
  final out = <(String, String)>[];
  for (final raw in g.specLine.split('·')) {
    final p = raw.trim();
    if (p.isEmpty) continue;
    final label = _specLabel(p);
    final value = label == 'HP' ? p.replaceAll(RegExp(r'\s*hp\b', caseSensitive: false), '').trim() : p;
    out.add((value.isEmpty ? p : value, label));
  }
  if (g.bodyStyle.isNotEmpty) out.add((g.bodyStyle, 'BODY'));
  return out.take(4).toList();
}

String _specLabel(String part) {
  final l = part.toLowerCase();
  if (RegExp(r'\bhp\b').hasMatch(l)) return 'HP';
  if (RegExp(r'\b(ps|kw|bhp|whp)\b').hasMatch(l)) return 'POWER';
  if (RegExp(r'\b(nm|lb-?ft)\b').hasMatch(l)) return 'TORQUE';
  if (RegExp(r'\b\d*-?(speed )?(mt|at|dct|amt)\b').hasMatch(l)) return 'GEARBOX';
  if (RegExp(r'\b(cvt|at|mt|dct|amt|auto|automatic|manual|e-cvt|ivt)\b').hasMatch(l)) return 'GEARBOX';
  if (part.contains('L')) return 'ENGINE';
  return 'SPEC';
}

/// "Silver · from the photo" / "Silver · picked by you" / "Pick one".
String carColourNote(String? color, {required bool fromPhoto}) =>
    color == null ? 'Pick one' : '${kCarColorLabels[color] ?? color} · ${fromPhoto ? 'from the photo' : 'picked by you'}';

/// Four-across spec tiles: big value, tiny label.
class CarSpecGrid extends StatelessWidget {
  const CarSpecGrid({super.key, required this.tiles});
  final List<(String, String)> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) {
          const gap = 8.0;
          final w = (c.maxWidth - gap * 3) / 4;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (value, label) in tiles)
                Container(
                  width: w,
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                  decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, maxLines: 1, style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, height: 1, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      ),
                      const SizedBox(height: 5),
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}
