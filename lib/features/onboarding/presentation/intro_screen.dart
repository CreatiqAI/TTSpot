import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/application/settings_providers.dart';

/// Four swipes, one tap. Shown once after sign-in; "Show intro again" lives
/// in Settings → About. The router moves on as soon as it is marked seen.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key, this.replay = false});
  /// Opened from Settings: just pop at the end instead of touching settings.
  final bool replay;

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  final _page = PageController();
  int _index = 0;
  bool _busy = false;

  static const _pages = [
    (AppArt.map, 'Malaysia is the map', 'Meets, TT sessions and good spots, all on one map. Balloon is an event, flag is a TT session, badge is a spot.'),
    (AppArt.coffee, 'TT now', 'At a mamak? One tap tells your friends where you are and drops an invite in their inbox.'),
    (AppArt.wave, 'Your friends, live', 'See friends and club mates on the map when they open the app. You choose who sees you: friends, nearby, everyone, or nobody.'),
    (AppArt.gift, 'Check in, earn, redeem', 'Check in at meets and spots for points. Spend them on vouchers from workshops, cafés and shops that back the scene.'),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(settingsActionsProvider).patch({'intro_seen': true});
      // The router listens to the profile and redirects on its own.
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 12, 0),
                child: TextButton(
                  onPressed: _busy ? null : _finish,
                  child: Text(last ? '' : 'Skip', style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 180,
                          height: 180,
                          decoration: const BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
                          child: Center(child: ArtIcon(p.$1, size: 112)),
                        ),
                        const SizedBox(height: 36),
                        Text(p.$2, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 36, fontWeight: FontWeight.w700, height: 1, color: AppColors.textPrimary)),
                        const SizedBox(height: 14),
                        Text(p.$3, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSecondary)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(color: i == _index ? AppColors.brand : AppColors.border, borderRadius: BorderRadius.circular(4)),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _busy
                      ? null
                      : last
                          ? _finish
                          : () => _page.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(last ? (widget.replay ? 'Done' : 'Let\'s go') : 'Next', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
