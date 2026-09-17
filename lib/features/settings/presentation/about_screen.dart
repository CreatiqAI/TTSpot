import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_version.dart';
import '../../../core/config/release_notes.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/presentation/intro_screen.dart';

/// About TT Spot: version, what's new per update, licences tucked at the end.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('About TT Spot'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Center(child: Image.asset('assets/brand/logo.png', height: 96)),
          const SizedBox(height: 10),
          const Center(
            child: Text('TT Spot', style: TextStyle(fontFamily: AppFonts.display, fontSize: 30, fontWeight: FontWeight.w700, height: 1)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
              child: Text('Version $kAppVersion  ·  build $kAppBuild', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(height: 28),
          Text('WHAT\'S NEW', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          for (var i = 0; i < kReleaseNotes.length; i++) _Release(note: kReleaseNotes[i], current: i == 0),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const IntroScreen(replay: true))),
              child: const Text('Show the intro again', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => showLicensePage(context: context, applicationName: 'TT Spot', applicationVersion: kAppVersion),
              child: Text('Open-source licences', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
          ),
          Center(
            child: Text('Made in Malaysia', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _Release extends StatelessWidget {
  const _Release({required this.note, required this.current});
  final ReleaseNote note;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: current ? AppColors.textPrimary : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: current ? null : Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(note.version, style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w700, height: 1, color: current ? AppColors.onInk : AppColors.textPrimary)),
              const SizedBox(width: 8),
              if (current)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                  child: const Text('CURRENT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .5)),
                ),
              const Spacer(),
              Text(note.date, style: TextStyle(fontSize: 12, color: current ? Colors.white60 : AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 4),
          Text(note.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: current ? AppColors.onInk : AppColors.textPrimary)),
          const SizedBox(height: 8),
          for (final p in note.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: current ? AppColors.brand : AppColors.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p, style: TextStyle(fontSize: 13.5, height: 1.4, color: current ? Colors.white.withValues(alpha: 0.9) : AppColors.textSecondary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
