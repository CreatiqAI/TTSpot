import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../map/presentation/widgets/car_marker.dart' show kCarColors, kCarColorLabels;
import '../../domain/car.dart';
import '../../domain/portrait_style.dart';
import '../garage/garage_body.dart' show compactMoney;
import '../widgets/portrait_style_sheet.dart' show PortraitSampleImage;
import 'car_page_model.dart';

/// Make · year, colour, today's car; the model big; then the real specs as
/// chips (or a spec sheet once there are four or more) and the description.
class CarIdentity extends StatelessWidget {
  const CarIdentity({super.key, required this.car, this.top = 8});
  final Car car;

  /// Space above the kicker (more under the media strip).
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = car;
    final kicker = [c.make.toUpperCase(), if (c.year != null) '${c.year}'].join(' · ');
    final specs = carSpecs(c);
    final colour = kCarColors[c.color];
    final description = (c.description ?? '').trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(kicker, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2.5, color: AppColors.textSecondary)),
              if (colour != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colour,
                        shape: BoxShape.circle,
                        border: colour.computeLuminance() > 0.6 || colour.computeLuminance() < 0.02 ? Border.all(color: AppColors.border) : null,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(kCarColorLabels[c.color] ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ],
                ),
              if (c.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: const Text('TODAY\'S CAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            c.model,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AppFonts.display, fontSize: 40, fontWeight: FontWeight.w800, height: 1.02, color: AppColors.textPrimary),
          ),
          if (specs.isNotEmpty && specs.length < 4) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in specs)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text(s.value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
              ],
            ),
          ],
          if (specs.length >= 4) ...[
            const SizedBox(height: 16),
            SpecSheet(specs: specs),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(description, style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.textPrimary)),
          ],
        ],
      ),
    );
  }
}

/// Two columns of label / value with hairlines, like a magazine's spec box.
class SpecSheet extends StatelessWidget {
  const SpecSheet({super.key, required this.specs});
  final List<CarSpec> specs;

  @override
  Widget build(BuildContext context) {
    Widget cell(CarSpec s) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 1),
              Text(s.value, style: TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w700, height: 1.15, color: AppColors.textPrimary)),
            ],
          ),
        );
    final rows = <Widget>[];
    for (var i = 0; i < specs.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cell(specs[i])),
              const SizedBox(width: 18),
              Expanded(child: i + 1 < specs.length ? cell(specs[i + 1]) : const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SPEC SHEET', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppColors.brand)),
        const SizedBox(height: 2),
        ...rows,
      ],
    );
  }
}

/// Mods · Spent (owner only) · Meets · Posts.
class CarStatsCard extends StatelessWidget {
  const CarStatsCard({super.key, required this.data});
  final CarPageData data;

  @override
  Widget build(BuildContext context) {
    final mods = data.mods;
    final spent = mods?.fold<double>(0, (s, m) => s + (m.cost ?? 0));
    final cells = <(String?, String)>[
      (mods?.length.toString(), 'Mods'),
      if (data.mine) (spent == null ? null : (spent > 0 ? 'RM ${compactMoney(spent)}' : '–'), 'Spent'),
      (data.meets?.length.toString(), 'Meets'),
      (data.posts?.length.toString(), 'Posts'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(16)),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      cells[i].$1 ?? '–',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w700, height: 1.1, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(cells[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Make it look pro": three real samples and the Paint button, for an
/// owner whose car has no portrait yet. The X hides it for this car on this
/// phone.
class MakeItLookProCard extends StatelessWidget {
  const MakeItLookProCard({super.key, required this.car, required this.cost, required this.onPaint, required this.onDismiss});
  final Car car;
  final int cost;
  final VoidCallback onPaint;
  final VoidCallback onDismiss;

  static const _samples = ['night_city', 'golden_hour', 'race_poster'];

  @override
  Widget build(BuildContext context) {
    final price = cost > 0 ? ' · $cost points' : '';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF15171C), Color(0xFF2A1215)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MAKE IT LOOK PRO', style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800, height: 1.05, color: Colors.white)),
                    const SizedBox(height: 3),
                    Text('Your own ${car.model}, painted in a style you pick.', style: TextStyle(fontSize: 13, height: 1.3, color: Colors.white.withValues(alpha: 0.75))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Hide this',
                child: GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.12)),
                    child: const Icon(AppIcons.x, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < _samples.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 1.6,
                      child: PortraitSampleImage(style: PortraitStyle.byId(_samples[i])!, cacheWidth: 360),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: onPaint,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            child: Text('Paint my ${car.model}$price', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// The owner's portraits still painting, and ones that failed this week
/// (points back, try again).
class PortraitNews extends StatelessWidget {
  const PortraitNews({super.key, required this.car, required this.portraits, required this.onRetry});
  final Car car;
  final List<CarPortrait> portraits;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          for (final p in portraits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.surfaceGray,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: p.isPending ? null : onRetry,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: p.isPending
                                ? Shimmer(child: ColoredBox(color: AppColors.border))
                                : ColoredBox(color: AppColors.danger.withValues(alpha: 0.12), child: const Icon(AppIcons.warning, size: 20, color: AppColors.danger)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.isPending ? 'Painting your ${car.model}…' : '${p.style?.name ?? 'The portrait'} didn\'t come out',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.isPending
                                    ? '${p.style?.name ?? 'Your portrait'}, ready in about a minute. We\'ll ping you.'
                                    : (p.refunded ? 'Your ${p.pointsSpent} points are back. Tap to try again.' : (p.error ?? 'Tap to try another style.')),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (!p.isPending) ...[
                          const SizedBox(width: 8),
                          Icon(AppIcons.arrowsClockwise, size: 18, color: AppColors.textSecondary),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A soft light sweep across [child], for things still being made.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.5 + 3 * _c.value, -0.3),
                  end: Alignment(-0.5 + 3 * _c.value, 0.3),
                  colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: AppColors.dark ? 0.10 : 0.55), Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "In the garage of @user", for visitors.
class CarOwnerRow extends StatelessWidget {
  const CarOwnerRow({super.key, required this.ownerId, required this.owner, required this.onTap});
  final String ownerId;
  final Profile? owner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = owner;
    final name = o?.username == null ? (o?.displayName ?? '…') : '@${o!.username}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Row(
              children: [
                UserAvatar(url: o?.avatarUrl, name: o?.displayName ?? o?.username, seed: ownerId, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('In the garage of', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
