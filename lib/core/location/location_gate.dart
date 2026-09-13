import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/app_art.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';

/// TT Spot is a map first: friends and clubmates on it, check-ins that prove
/// you were there, and meet QR codes that only work at the meet. So the very
/// first thing after sign-up is asking for location, with a proper explanation
/// instead of a bare system dialog.

/// Whether location permission is granted right now (checked on every launch).
final locationGrantedProvider = FutureProvider<bool>((ref) async {
  try {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
});

/// "Not now" for this session. Resets when the app restarts, so the gate asks
/// again next time, which is the intent: the app is built around location.
class LocationGateSkipped extends Notifier<bool> {
  @override
  bool build() => false;
  void skip() => state = true;
}

final locationGateSkippedProvider = NotifierProvider<LocationGateSkipped, bool>(LocationGateSkipped.new);

class LocationGateScreen extends ConsumerStatefulWidget {
  const LocationGateScreen({super.key});

  @override
  ConsumerState<LocationGateScreen> createState() => _LocationGateScreenState();
}

class _LocationGateScreenState extends ConsumerState<LocationGateScreen> with WidgetsBindingObserver {
  bool _busy = false;
  bool _deniedForever = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from system settings: re-check.
    if (state == AppLifecycleState.resumed) ref.invalidate(locationGrantedProvider);
  }

  Future<void> _allow() async {
    setState(() => _busy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.deniedForever) {
        setState(() => _deniedForever = true);
        await Geolocator.openAppSettings();
        return;
      }
      ref.invalidate(locationGrantedProvider);
    } catch (_) {
      // fall through; the gate stays and the member can try again
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            children: [
              const Spacer(),
              const ArtIcon(AppArt.map, size: 112),
              const SizedBox(height: 26),
              const Text('TT Spot runs on location', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 12),
              const Text(
                'It\'s how the map works. Turn it on to see friends and your club on the map, check in at meets and spots, and scan a meet\'s QR when you\'re actually there.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 22),
              const _Point(art: AppArt.pin, text: 'Only while the app is open. Nothing runs in the background.'),
              const _Point(art: AppArt.ghost, text: 'Go invisible any time with ghost mode on the map.'),
              const _Point(art: AppArt.shield, text: 'Friends and clubmates you choose can see you. Nobody else.'),
              const Spacer(),
              if (_deniedForever)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Location is off for TT Spot in your phone settings. Allow it there, then come back.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.danger)),
                ),
              PrimaryButton(label: _deniedForever ? 'Open settings' : 'Turn on location', loading: _busy, onPressed: _allow),
              TextButton(
                onPressed: () => ref.read(locationGateSkippedProvider.notifier).skip(),
                child: const Text('Not now', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.art, required this.text});
  final String art;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ArtIcon(art, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.35))),
          ],
        ),
      );
}
