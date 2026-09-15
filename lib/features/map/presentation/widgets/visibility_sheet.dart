import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../friends/application/friends_providers.dart';

/// "Who can see my car": friends · friends + nearby (radius slider) · nobody.
Future<void> showVisibilitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _VisibilitySheet(),
  );
}

class _VisibilitySheet extends ConsumerStatefulWidget {
  const _VisibilitySheet();
  @override
  ConsumerState<_VisibilitySheet> createState() => _VisibilitySheetState();
}

class _VisibilitySheetState extends ConsumerState<_VisibilitySheet> {
  late String _mode = ref.read(myLocationProvider).value?.shareMode ?? 'friends';
  late double _km = (ref.read(myLocationProvider).value?.shareRadiusM ?? 2000) / 1000;
  bool _busy = false;

  Future<void> _apply(String mode, {double? km}) async {
    setState(() {
      _mode = mode;
      if (km != null) _km = km;
      _busy = true;
    });
    try {
      await ref.read(locationPublisherProvider.notifier).setShare(mode, radiusM: (_km * 1000).round());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _kmLabel => _km >= 1 ? '${_km.toStringAsFixed(_km % 1 == 0 ? 0 : 1)} km' : '${(_km * 1000).round()} m';

  @override
  Widget build(BuildContext context) {
    final nearbyCount = ref.watch(friendPinsProvider).value?.where((p) => p.viaNearby).length ?? 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Who can see my car', style: TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w700, height: 1)),
            const SizedBox(height: 4),
            const Text('Only while the app is open. Change it any time.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            _Option(
              icon: AppIcons.users,
              title: 'Friends',
              subtitle: 'Friends and your clubmates see where you are, live.',
              on: _mode == 'friends',
              onTap: _busy ? null : () => _apply('friends'),
            ),
            _Option(
              icon: AppIcons.broadcast,
              title: 'Friends + nearby',
              subtitle: 'Car people around you also see your car and handle at a rounded spot. They can message you.',
              on: _mode == 'nearby',
              onTap: _busy ? null : () => _apply('nearby'),
              child: _mode != 'nearby'
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(activeTrackColor: AppColors.brand, thumbColor: Colors.white, overlayColor: AppColors.brand.withValues(alpha: 0.12), trackHeight: 5, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 3)),
                                child: Slider(
                                  value: _km,
                                  min: 0.5,
                                  max: 3,
                                  divisions: 25,
                                  onChanged: (v) => setState(() => _km = v),
                                  onChangeEnd: (v) => _apply('nearby', km: v),
                                ),
                              ),
                            ),
                            SizedBox(width: 58, child: Text(_kmLabel, textAlign: TextAlign.right, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w700))),
                          ],
                        ),
                        Row(
                          children: [
                            for (final k in const [1.0, 2.0, 3.0]) ...[
                              Expanded(
                                child: GestureDetector(
                                  onTap: _busy ? null : () => _apply('nearby', km: k),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 7),
                                    decoration: BoxDecoration(color: _km == k ? AppColors.ink : AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
                                    child: Text('${k.toInt()} km', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _km == k ? Colors.white : AppColors.textPrimary)),
                                  ),
                                ),
                              ),
                              if (k != 3.0) const SizedBox(width: 6),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(nearbyCount == 0 ? 'Nobody nearby right now.' : '$nearbyCount ${nearbyCount == 1 ? 'person' : 'people'} around you now.', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
            ),
            _Option(
              icon: AppIcons.ghost,
              title: 'Nobody (ghost)',
              subtitle: 'You still see friends. They don\'t see you.',
              on: _mode == 'ghost',
              onTap: _busy ? null : () => _apply('ghost'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.title, required this.subtitle, required this.on, required this.onTap, this.child});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool on;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? AppColors.ink : AppColors.border, width: on ? 1.5 : 1)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: on ? AppColors.brand : AppColors.surfaceGray, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: on ? Colors.white : AppColors.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary)),
                    ?child,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
