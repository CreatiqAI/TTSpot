import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/settings/application/settings_providers.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/open_external.dart' show wazeUrl;

/// A navigation app TT Spot hands a trip to. There is no in-app turn-by-turn:
/// Waze and Google Maps route better in Malaysia and have the police and
/// speed-camera alerts drivers expect.
enum DirectionsApp {
  waze('waze', 'Waze'),
  google('google', 'Google Maps'),
  apple('apple', 'Apple Maps');

  const DirectionsApp(this.key, this.label);

  /// Value stored in `profiles.settings.directions_app`.
  final String key;
  final String label;

  static DirectionsApp? fromKey(String? key) => values.where((a) => a.key == key).firstOrNull;
}

/// `directions_app` value for "Ask every time" (also the default).
const kDirectionsAsk = 'ask';

/// The apps this platform can offer, in chooser order. Apple Maps is iPhone only.
List<DirectionsApp> directionsAppsFor({required bool iOS}) => [DirectionsApp.waze, DirectionsApp.google, if (iOS) DirectionsApp.apple];

/// What a Directions tap does: open [open] straight away, or show the chooser
/// with [options]. [web]: nothing is installed, so the options are web links.
/// [missing]: the remembered app is no longer on this phone.
class DirectionsPlan {
  const DirectionsPlan.open(DirectionsApp this.open)
      : options = const [],
        web = false,
        missing = null;
  const DirectionsPlan.choose(this.options, {this.web = false, this.missing}) : open = null;

  final DirectionsApp? open;
  final List<DirectionsApp> options;
  final bool web;
  final DirectionsApp? missing;

  @override
  String toString() => open != null ? 'open(${open!.key})' : 'choose(${options.map((a) => a.key).join(',')}${web ? ', web' : ''}${missing != null ? ', missing ${missing!.key}' : ''})';
}

/// Pure: decides between opening the remembered app and showing the chooser.
/// [saved] is the `directions_app` setting ('ask', 'waze', 'google', 'apple'
/// or null); [installed] what this phone has; [choose] forces the chooser
/// (long-press). A remembered app that isn't installed (or isn't offered on
/// this platform, like Apple Maps on Android) falls back to the chooser.
DirectionsPlan planDirections({required String? saved, required Set<DirectionsApp> installed, required bool iOS, bool choose = false}) {
  final platform = directionsAppsFor(iOS: iOS);
  final have = platform.where(installed.contains).toList();
  final pick = DirectionsApp.fromKey(saved);
  final remembered = pick != null && platform.contains(pick) ? pick : null;
  if (!choose && remembered != null && have.contains(remembered)) return DirectionsPlan.open(remembered);
  final missing = !choose && remembered != null && !have.contains(remembered) ? remembered : null;
  if (have.isEmpty) {
    // No maps app at all: Waze and Google Maps as web links (Apple Maps' web
    // link only makes sense on an iPhone, where Maps is always there).
    return DirectionsPlan.choose(const [DirectionsApp.waze, DirectionsApp.google], web: true, missing: missing);
  }
  return DirectionsPlan.choose(have, missing: missing);
}

/// The app link and the web link for a trip to [lat],[lng] by car.
({String? app, String web}) directionsUrls(DirectionsApp app, double lat, double lng, {required bool iOS}) => switch (app) {
      DirectionsApp.waze => (app: 'waze://?ll=$lat,$lng&navigate=yes', web: wazeUrl(lat, lng)),
      DirectionsApp.google => (
          app: iOS ? 'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving' : 'google.navigation:q=$lat,$lng&mode=d',
          web: 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
        ),
      // maps.apple.com opens the Maps app itself on an iPhone.
      DirectionsApp.apple => (app: null, web: 'https://maps.apple.com/?daddr=$lat,$lng&dirflg=d'),
    };

bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

/// Which navigation apps this phone has. Uses the schemes declared in
/// Info.plist (LSApplicationQueriesSchemes) and the Android manifest `<queries>`.
Future<Set<DirectionsApp>> installedDirectionsApps({bool? iOS}) async {
  final ios = iOS ?? _isIOS;
  Future<bool> can(String url) async {
    try {
      return await canLaunchUrl(Uri.parse(url));
    } catch (_) {
      return false;
    }
  }

  final checks = await Future.wait([can('waze://'), can(ios ? 'comgooglemaps://' : 'google.navigation:q=0,0')]);
  return {
    if (checks[0]) DirectionsApp.waze,
    if (checks[1]) DirectionsApp.google,
    if (ios) DirectionsApp.apple, // ships with every iPhone
  };
}

/// Opens [app] with a driving route to [lat],[lng]. Tries the app first and
/// the web link after that ([web] skips straight to the web link).
Future<void> launchDirections(BuildContext context, DirectionsApp app, double lat, double lng, {bool web = false}) async {
  final urls = directionsUrls(app, lat, lng, iOS: _isIOS);
  if (!web && urls.app != null) {
    try {
      if (await launchUrl(Uri.parse(urls.app!), mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
  }
  try {
    if (await launchUrl(Uri.parse(urls.web), mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Couldn\'t open ${app.label}.')));
  }
}

/// The remembered directions app, if it's installed here. Null means a
/// Directions tap will show the chooser. For button labels ("Open Waze").
Future<DirectionsApp?> rememberedDirectionsApp(WidgetRef ref) async {
  final ios = _isIOS;
  final plan = planDirections(saved: ref.read(settingsProvider).directionsApp, installed: await installedDirectionsApps(iOS: ios), iOS: ios);
  return plan.open;
}

/// Every Directions / Go now button lands here. With a remembered app it
/// opens straight away; otherwise (or with [choose], used by long-press) a
/// sheet lists the installed apps with a "Remember my choice" switch.
Future<void> openDirections(BuildContext context, {required double lat, required double lng, String? label, bool choose = false}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final saved = container.read(settingsProvider).directionsApp;
  final ios = _isIOS;
  final installed = await installedDirectionsApps(iOS: ios);
  if (!context.mounted) return;
  final plan = planDirections(saved: saved, installed: installed, iOS: ios, choose: choose);
  final direct = plan.open;
  if (direct != null) return launchDirections(context, direct, lat, lng);

  final picked = await _chooser(context, plan, label: label, current: DirectionsApp.fromKey(saved));
  if (picked == null || !context.mounted) return;

  // Save only real changes; a failed save never blocks the trip.
  if (!plan.web) {
    final next = picked.remember ? picked.app.key : kDirectionsAsk;
    if (next != saved) {
      unawaited(container.read(settingsActionsProvider).patch({'directions_app': next}).catchError((_) {}));
    }
  }
  if (!context.mounted) return;
  await launchDirections(context, picked.app, lat, lng, web: plan.web);
}

Future<({DirectionsApp app, bool remember})?> _chooser(BuildContext context, DirectionsPlan plan, {String? label, DirectionsApp? current}) {
  var remember = true;
  final note = plan.missing != null
      ? '${plan.missing!.label} isn\'t on this phone any more. Pick another app.'
      : plan.web
          ? 'No maps app on this phone, so these open in your browser.'
          : null;
  return showModalBottomSheet<({DirectionsApp app, bool remember})>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(label == null ? 'Directions' : 'Directions to $label', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Text(note, style: TextStyle(fontSize: 13.5, height: 1.35, color: AppColors.textSecondary)),
                ),
              for (final app in plan.options)
                ListTile(
                  leading: DirectionsAppIcon(app: app),
                  title: Text(app.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(plan.web ? 'Opens in your browser' : _blurb(app), style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  trailing: app == current ? Icon(AppIcons.checkCircleFill, color: AppColors.brand, size: 20) : null,
                  onTap: () => Navigator.pop(ctx, (app: app, remember: remember)),
                ),
              if (!plan.web)
                SwitchListTile.adaptive(
                  value: remember,
                  onChanged: (v) => setSheet(() => remember = v),
                  title: const Text('Remember my choice', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  subtitle: Text('Opens straight away next time. Long-press Directions or change it in Settings.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

String _blurb(DirectionsApp app) => switch (app) {
      DirectionsApp.waze => 'Live traffic, police and camera alerts',
      DirectionsApp.google => 'Live traffic, lanes and Street View',
      DirectionsApp.apple => 'Built into your iPhone',
    };

/// Coloured tile for a directions app (chooser rows, Settings).
class DirectionsAppIcon extends StatelessWidget {
  const DirectionsAppIcon({super.key, required this.app, this.size = 40});
  final DirectionsApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color fg) = switch (app) {
      DirectionsApp.waze => (AppIcons.navigationArrow, const Color(0xFF0B7FA6)),
      DirectionsApp.google => (AppIcons.mapTrifold, const Color(0xFF1E7E34)),
      DirectionsApp.apple => (AppIcons.compass, const Color(0xFF3A6FD8)),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fg.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, color: fg, size: size * 0.55),
    );
  }
}
