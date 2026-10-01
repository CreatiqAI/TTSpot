import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/titi.dart';
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
        child: LayoutBuilder(
          builder: (_, c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight > 32 ? c.maxHeight - 32 : 0),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: 300,
                          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(28)),
                          // Left of centre so the bubble never covers TiTi or the
                          // TT Spot logo on his left foot.
                          alignment: const Alignment(-0.75, 0.35),
                          child: const Titi(TitiPose.mapPin, height: 250),
                        ),
                        const Positioned(
                          right: 14,
                          top: 22,
                          child: TitiBubble('Last thing. I need to know where the meet is, and where you are.', maxWidth: 168, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'TT SPOT IS A MAP.',
                      style: TextStyle(fontFamily: AppFonts.display, fontSize: 40, height: 0.98, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 18),
                    const _Point(icon: AppIcons.mapPin, title: 'Check in at meets and spots', text: 'One tap when you arrive. That\'s how you earn points.'),
                    const _Point(icon: AppIcons.usersThree, title: 'See friends on the road', text: 'Only friends you choose see you. Off by default.'),
                    const _Point(icon: AppIcons.navigationArrow, title: 'Get to the meet', text: 'Post your ETA, then go with Waze or Maps.'),
                    const Spacer(),
                    const SizedBox(height: 20),
                    if (_deniedForever)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text('Location is off for TT Spot in your phone settings. Allow it there, then come back.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.danger)),
                      ),
                    PrimaryButton(label: _deniedForever ? 'Open settings' : 'Turn on location', loading: _busy, onPressed: _allow),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => ref.read(locationGateSkippedProvider.notifier).skip(),
                      child: Text('Not now, take me to the map', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One reason row: a 40 px icon square, a bold title and a one-line why.
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
