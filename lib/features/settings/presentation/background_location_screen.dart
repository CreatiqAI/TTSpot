import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/location/background_location.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/primary_button.dart';
import '../../friends/application/friends_providers.dart';
import '../application/background_location_controller.dart';

bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

/// Settings → Privacy: "Share location when TT Spot is closed", with its live
/// status and a Fix button when the phone took "Allow all the time" away.
class BackgroundLocationTile extends ConsumerStatefulWidget {
  const BackgroundLocationTile({super.key});

  @override
  ConsumerState<BackgroundLocationTile> createState() => _BackgroundLocationTileState();
}

class _BackgroundLocationTileState extends ConsumerState<BackgroundLocationTile> {
  bool _busy = false;

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _turnOn() async {
    final accepted = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BackgroundLocationDisclosure()),
    );
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    final outcome = await ref.read(backgroundLocationProvider.notifier).enable();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case BgEnableOutcome.on:
        _snack('On. The people your map visibility allows can see you while TT Spot is closed.');
      case BgEnableOutcome.needsAlways:
        await _needsAlwaysSheet();
      case BgEnableOutcome.locationOff:
        _snack('Turn on your phone\'s location first, then try again.');
      case BgEnableOutcome.denied:
        _snack('TT Spot needs location for this. Nothing was turned on.');
      case BgEnableOutcome.blocked:
        _snack('Location is off for TT Spot in your phone settings. Allow it there, then try again.');
        await Geolocator.openAppSettings();
      case BgEnableOutcome.failed:
        _snack('Couldn\'t turn it on. Check your connection and try again.');
    }
  }

  Future<void> _turnOff() async {
    setState(() => _busy = true);
    await ref.read(backgroundLocationProvider.notifier).disable();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack('Off. TT Spot shares your location only while it\'s open.');
  }

  /// Ask again where the phone still allows it; otherwise phone settings.
  Future<void> _fix() async {
    final t = DateTime.now();
    final granted = await BgLocationNative.requestBackground();
    // An instant "no" means the phone didn't show anything: go to settings.
    if (!granted && DateTime.now().difference(t) < const Duration(milliseconds: 800)) await Geolocator.openAppSettings();
    await ref.read(backgroundLocationProvider.notifier).sync();
  }

  Future<void> _needsAlwaysSheet() => showModalBottomSheet<void>(
        useRootNavigator: true, // above the shell tab bar
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('One more step', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  _ios
                      ? 'In iPhone Settings, tap Location and choose Always. Then come back and it turns on by itself.'
                      : 'In phone settings, tap Permissions › Location and choose "Allow all the time". Then come back and it turns on by itself.',
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Open phone settings',
                  icon: AppIcons.gear,
                  onPressed: () {
                    Navigator.pop(ctx);
                    Geolocator.openAppSettings();
                  },
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Not now', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(backgroundLocationProvider);
    final view = s.view;
    if (view == BgView.unsupported) return const SizedBox.shrink();
    final waiting = s.waitingForAlways && !s.enabled;
    final Color tint = switch (view) {
      BgView.on => AppColors.success,
      BgView.needsAlways => AppColors.danger,
      _ => AppColors.textSecondary,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          value: s.enabled || waiting,
          onChanged: _busy || !s.loaded ? null : (v) => v && !waiting ? _turnOn() : _turnOff(),
          activeTrackColor: AppColors.brand,
          secondary: Icon(AppIcons.navigationArrow, color: AppColors.textPrimary),
          title: const Text('Share location when TT Spot is closed', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          subtitle: Text(
            waiting ? (_ios ? 'Waiting for "Always" in iPhone Settings' : 'Waiting for "Allow all the time"') : bgSubtitle(view, ios: _ios),
            style: TextStyle(fontSize: 12, color: waiting ? AppColors.textSecondary : tint, fontWeight: view == BgView.needsAlways ? FontWeight.w600 : FontWeight.w400),
          ),
        ),
        if (view == BgView.needsAlways || waiting)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _ios ? 'Location must be set to Always for TT Spot.' : 'Location must be "Allow all the time" for TT Spot.',
                    style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _fix, child: const Text('Fix', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand))),
              ],
            ),
          ),
      ],
    );
  }
}

/// The prominent disclosure Google Play asks for before background location,
/// full screen, before any permission prompt. "Turn on" pops true.
class BackgroundLocationDisclosure extends ConsumerWidget {
  const BackgroundLocationDisclosure({super.key});

  static String _audience(String? mode) => switch (mode) {
        'nearby' => 'Your visibility is Friends + nearby: friends and clubmates, plus members within your distance at a rounded spot.',
        'public' => 'Your visibility is Everyone: friends and clubmates, plus any member at a rounded spot.',
        'ghost' => 'Your visibility is Nobody, so nobody sees you until you change it.',
        _ => 'Your visibility is Friends: your friends and clubmates.',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(myLocationProvider).value?.shareMode;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: () => Navigator.pop(context, false)),
        title: const Text('Location when closed'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                children: [
                  Container(
                    height: 150,
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(24)),
                    alignment: Alignment.bottomCenter,
                    child: const Titi(TitiPose.mapPin, height: 136),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Share your location when TT Spot is closed?',
                    style: TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'TT Spot collects your location to show you on the map to the people you choose, even when the app is closed or not in use.',
                    style: TextStyle(fontSize: 14.5, height: 1.4, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  _Point(
                    icon: AppIcons.mapPin,
                    title: 'What we collect',
                    text: 'Your phone\'s location, in the background and when TT Spot is closed. About every 30 seconds while you move. We keep only your latest spot.',
                  ),
                  _Point(icon: AppIcons.users, title: 'Who sees it', text: 'Only the people your map visibility allows. ${_audience(mode)}'),
                  _Point(
                    icon: AppIcons.car,
                    title: 'Why',
                    text: 'So friends and your club can find you on the road and at meets without you opening the app.',
                  ),
                  _Point(
                    icon: AppIcons.lightning,
                    title: 'Battery',
                    text: _ios
                        ? 'Uses a little more battery. It rests when you\'re parked. iPhone shows a location arrow while it\'s on.'
                        : 'Uses a little more battery. It rests when you\'re parked. A notification shows while it\'s on.',
                  ),
                  _Point(
                    icon: AppIcons.stop,
                    title: 'How to stop',
                    text: _ios
                        ? 'Switch it off here in Settings, or set your visibility to Nobody. You can also set TT Spot\'s location to While Using in iPhone Settings.'
                        : 'Switch it off here in Settings, tap Stop on the notification, or set your visibility to Nobody.',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: Text(
                      _ios
                          ? 'Next, iPhone asks about location. Choose "Change to Always Allow".'
                          : 'Next, your phone asks about location. Choose "Allow all the time".',
                      style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(label: 'Turn on', onPressed: () => Navigator.pop(context, true)),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Not now', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the disclosure: an icon square, a bold title, the detail.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(text, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );
}
