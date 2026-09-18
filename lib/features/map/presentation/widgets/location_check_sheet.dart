import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/location/live_position.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/open_external.dart';

/// Long-press the locate button: what the phone is actually reporting, and
/// one-tap comparisons in Google Maps and Apple Maps at the same coordinates.
/// If those apps put you in the same spot, the fix is right and only the map
/// label is missing; if they differ, the phone's fix is the problem.
Future<void> showLocationCheckSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    builder: (_) => const _LocationCheckSheet(),
  );
}

class _LocationCheckSheet extends ConsumerStatefulWidget {
  const _LocationCheckSheet();
  @override
  ConsumerState<_LocationCheckSheet> createState() => _LocationCheckSheetState();
}

class _LocationCheckSheetState extends ConsumerState<_LocationCheckSheet> {
  LocationPermission? _perm;
  LocationAccuracyStatus? _precision;
  bool _serviceOn = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final on = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      final prec = await Geolocator.getLocationAccuracy();
      if (mounted) {
        setState(() {
          _serviceOn = on;
          _perm = perm;
          _precision = prec;
        });
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await ref.read(livePositionProvider.notifier).refresh();
    await _load();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(livePositionProvider);
    final lat = p?.latLng.latitude, lng = p?.latLng.longitude;
    final coords = lat == null ? null : '${lat.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}';
    final age = p?.age.inSeconds;
    final accColor = p == null
        ? AppColors.textSecondary
        : p.accuracyM <= 20
            ? AppColors.success
            : p.accuracyM <= 100
                ? AppColors.warnColor
                : AppColors.danger;

    Widget row(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 130, child: Text(k, style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary))),
              Expanded(child: Text(v, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary))),
            ],
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Location check', style: TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
            const SizedBox(height: 4),
            Text('What your phone is telling TT Spot right now.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            row('Fix', p == null ? 'None yet' : '${age}s ago', color: p == null ? AppColors.danger : null),
            row('Accuracy', p == null ? '—' : '±${p.accuracyM.round()} m', color: accColor),
            row('Coordinates', coords ?? '—'),
            row('Permission', switch (_perm) {
              null => '…',
              LocationPermission.always => 'Always',
              LocationPermission.whileInUse => 'While using the app',
              LocationPermission.denied => 'Denied',
              LocationPermission.deniedForever => 'Denied permanently',
              LocationPermission.unableToDetermine => 'Unknown',
            }, color: _perm == LocationPermission.denied || _perm == LocationPermission.deniedForever ? AppColors.danger : null),
            row('Precise location', switch (_precision) { null => '…', LocationAccuracyStatus.precise => 'On', LocationAccuracyStatus.reduced => 'Off (rounded to a few km)', _ => 'Unknown' },
                color: _precision == LocationAccuracyStatus.reduced ? AppColors.danger : null),
            if (!_serviceOn) row('Location services', 'Off', color: AppColors.danger),
            const SizedBox(height: 8),
            Text(
              'Green accuracy under 20 m means the phone is sure. Compare the same coordinates in another app: if it lands in the same place, the fix is right and only the map label differs.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: coords == null
                        ? null
                        : () => openExternal(context, 'comgooglemaps://?q=$lat,$lng&zoom=18', fallbackUrl: 'https://maps.google.com/?q=$lat,$lng', appName: 'Google Maps'),
                    icon: const Icon(AppIcons.mapTrifold, size: 18),
                    label: const Text('Google Maps'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: coords == null ? null : () => openExternal(context, 'maps://?ll=$lat,$lng&q=TT%20Spot%20fix', fallbackUrl: 'https://maps.apple.com/?ll=$lat,$lng', appName: 'Apple Maps'),
                    icon: const Icon(AppIcons.mapPin, size: 18),
                    label: const Text('Apple Maps'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(AppIcons.gpsFix, size: 18),
                label: Text(_refreshing ? 'Getting a fresh fix…' : 'Get a fresh fix'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
