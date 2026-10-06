import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/location/background_location.dart' show BgView;
import '../../../core/location/location_gate.dart';
import '../../../core/push/push_service.dart' show kInstantAnswer;
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart' show PressScale;
import '../../auth/presentation/widgets/dark_auth.dart';
import '../../settings/application/background_location_controller.dart';
import '../../settings/presentation/background_location_screen.dart' show BackgroundLocationDisclosure;
import '../application/permissions_step.dart';

/// "Turn on permissions": the step after onboarding (route /location), and
/// on every launch while location is off. One dark card per permission, each
/// saying which button to tap in the phone's own prompt:
/// 1. Location, which the map needs.
/// 2. Notifications, through the push service so this phone registers for
///    push exactly as before.
/// 3. Optional: share my spot while the app is closed. Enable opens the same
///    disclosure and opt-in as Settings, so it only turns on from here when
///    the member asks (it is off by default).
/// A permission the phone won't ask for again shows Settings instead of
/// Enable. Everything is read again when the app comes back to the
/// foreground (from phone settings or a system prompt). Continue always
/// works; without location it asks once to be sure. The router moves on to
/// the map when [permissionsStepDoneProvider] flips.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key, this.confirmBackground});

  /// Shows the background-location disclosure; true = Turn on. Defaults to
  /// the full-screen one Settings uses (Google Play wants it before the
  /// prompt). Tests stand in for it.
  final Future<bool?> Function(BuildContext context)? confirmBackground;

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// The cards rise in one after another.
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  LocationPermission? _location;
  bool _serviceOn = true;
  AuthorizationStatus? _notifications;
  bool _loaded = false;
  // What the phone told us this launch: it refuses without showing a prompt.
  bool _locationBlocked = false;
  bool _notificationsBlocked = false;
  int _notificationNos = 0;
  bool _busyLocation = false;
  bool _busyNotifications = false;
  bool _busyBackground = false;

  PermissionsDevice get _device => ref.read(permissionsDeviceProvider);
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  PermPill get _locationPill => locationPill(_location, serviceOn: _serviceOn, blocked: _locationBlocked);
  PermPill get _notificationsPill => notificationsPill(_notifications, blocked: _notificationsBlocked, ios: _ios);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _device.stepShown();
    unawaited(_refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
    } else if (_enter.value == 0 && !_enter.isAnimating) {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _enter.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from phone settings or a system prompt: read everything again.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  /// Reads every permission fresh. A card that turns on gives a light tap.
  Future<void> _refresh() async {
    final d = _device;
    LocationPermission? location;
    var serviceOn = true;
    AuthorizationStatus? notifications;
    try {
      location = await d.location();
    } catch (_) {}
    try {
      serviceOn = await d.locationServiceOn();
    } catch (_) {}
    try {
      notifications = await d.notifications();
    } catch (_) {}
    if (!mounted) return;
    final before = (_locationPill, _notificationsPill);
    final hadLocation = locationAllowed(_location);
    final wasLoaded = _loaded;
    setState(() {
      _location = location;
      _serviceOn = serviceOn;
      _notifications = notifications;
      _loaded = true;
      if (locationAllowed(location)) _locationBlocked = false;
      if (notificationsAllowed(notifications)) _notificationsBlocked = false;
    });
    final turnedOn = (before.$1 != PermPill.on && _locationPill == PermPill.on) || (before.$2 != PermPill.on && _notificationsPill == PermPill.on);
    if (wasLoaded && turnedOn) unawaited(HapticFeedback.lightImpact());
    // The router and the map read this one.
    if (hadLocation != locationAllowed(location)) ref.invalidate(locationGrantedProvider);
    if (notificationsAllowed(notifications)) unawaited(d.registerPush().catchError((_) {}));
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6)));
  }

  /// Card 1. True when location is allowed afterwards.
  Future<bool> _enableLocation() async {
    final d = _device;
    switch (_locationPill) {
      case PermPill.on:
        return true;
      case PermPill.settings:
        if (locationAllowed(_location) && !_serviceOn) {
          await d.openLocationSettings();
        } else {
          await d.openAppSettings();
        }
        return false;
      case PermPill.enable:
        break;
    }
    setState(() => _busyLocation = true);
    var allowed = false;
    try {
      final clock = Stopwatch()..start();
      var p = await d.location();
      // Never ask while it's already allowed: on Android that asks for "all the time".
      if (!locationAllowed(p) && p != LocationPermission.deniedForever) p = await d.requestLocation();
      final instant = clock.elapsed < kInstantAnswer;
      allowed = locationAllowed(p);
      if (p == LocationPermission.deniedForever) {
        _locationBlocked = true;
        // No prompt was shown: phone settings are the only way left.
        if (instant) await d.openAppSettings();
      } else if (allowed && !await d.locationServiceOn()) {
        await d.openLocationSettings();
      }
    } catch (_) {
      // The card stays as it was; the member can try again.
    } finally {
      if (mounted) setState(() => _busyLocation = false);
    }
    await _refresh();
    return allowed;
  }

  /// Card 2.
  Future<void> _enableNotifications() async {
    final d = _device;
    switch (_notificationsPill) {
      case PermPill.on:
        return;
      case PermPill.settings:
        await d.openNotificationSettings();
        return;
      case PermPill.enable:
        break;
    }
    setState(() => _busyNotifications = true);
    try {
      final r = await d.requestNotifications();
      if (r == null) {
        // Push isn't running on this phone: its settings are all there is.
        await d.openNotificationSettings();
      } else if (!notificationsAllowed(r.status)) {
        if (!r.prompted) {
          _notificationsBlocked = true;
          await d.openNotificationSettings();
        } else if (!_ios && ++_notificationNos >= 2) {
          // Android stops asking after a second "Don't allow".
          _notificationsBlocked = true;
        }
      }
    } catch (_) {
      // Stays as it was.
    } finally {
      if (mounted) setState(() => _busyNotifications = false);
    }
    await _refresh();
  }

  Future<bool?> _disclosure(BuildContext context) => Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BackgroundLocationDisclosure()),
      );

  /// Card 3: the Settings opt-in, started from here. Nothing turns on unless
  /// the member taps Enable and then Turn on in the disclosure.
  Future<void> _enableBackground() async {
    final s = ref.read(backgroundLocationProvider);
    final pill = backgroundPill(s);
    if (!s.loaded || pill == null || pill == PermPill.on) return;
    final d = _device;
    final bg = ref.read(backgroundLocationProvider.notifier);
    if (pill == PermPill.settings) {
      // Ask for "Always" again where the phone still may, else its settings.
      setState(() => _busyBackground = true);
      try {
        final clock = Stopwatch()..start();
        final granted = await d.requestBackground();
        if (!granted && clock.elapsed < kInstantAnswer) await d.openAppSettings();
        await bg.sync();
      } catch (_) {
      } finally {
        if (mounted) setState(() => _busyBackground = false);
      }
      return;
    }
    final accepted = await (widget.confirmBackground ?? _disclosure)(context);
    if (accepted != true || !mounted) return;
    setState(() => _busyBackground = true);
    BgEnableOutcome outcome;
    try {
      outcome = await bg.enable();
    } catch (_) {
      outcome = BgEnableOutcome.failed;
    }
    if (!mounted) return;
    setState(() => _busyBackground = false);
    switch (outcome) {
      case BgEnableOutcome.on:
      case BgEnableOutcome.denied: // the Location card still says Enable
      case BgEnableOutcome.needsAlways: // the card says what's missing, with a Settings button
        break;
      case BgEnableOutcome.locationOff:
        _snack('Turn on your phone\'s location, then tap Enable again.');
      case BgEnableOutcome.blocked:
        _locationBlocked = true;
        await d.openAppSettings();
      case BgEnableOutcome.failed:
        _snack('Couldn\'t turn it on. Check your connection and try again.');
    }
    await _refresh();
  }

  Future<void> _continue() async {
    if (!locationAllowed(_location)) {
      final turnOn = await _confirmNoLocation();
      if (turnOn == null || !mounted) return;
      // Turn on: the Location card's button. Straight on to the map when it
      // worked; after a trip to phone settings the member taps Continue again.
      if (turnOn && !await _enableLocation()) return;
      if (!mounted) return;
    }
    ref.read(permissionsStepDoneProvider.notifier).done();
  }

  /// Null when dismissed (stay here), true = Turn on, false = Not now.
  Future<bool?> _confirmNoLocation() => showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (ctx) => Dialog(
          backgroundColor: AuthDark.panel,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Use TT Spot without location?', style: TextStyle(fontSize: 20, height: 1.2, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 8),
                Text(
                  'The map can\'t show you, and check-ins won\'t work.',
                  style: TextStyle(fontSize: 14, height: 1.4, color: AuthDark.text),
                ),
                const SizedBox(height: 20),
                AuthPill(label: 'Turn on', onPressed: () => Navigator.pop(ctx, true)),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  child: Text('Not now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8))),
                ),
              ],
            ),
          ),
        ),
      );

  // ───────────────────────────────────────────────────────────── words ──

  // One short line each (the owner wants it clean): the button to tap in the
  // phone's prompt, what it's for once on, and "fix in Settings" when the
  // phone won't ask again. No menu paths: the Settings pill goes there.

  String _locationHint(PermPill pill) => switch (pill) {
        PermPill.enable => _ios ? 'Tap "Allow While Using App".' : 'Tap "While using the app".',
        PermPill.on => 'So friends and meets can find you.',
        PermPill.settings => locationAllowed(_location) && !_serviceOn ? 'Phone location is off · fix in Settings' : 'Turned off · fix in Settings',
      };

  String _notificationsHint(PermPill pill) => switch (pill) {
        PermPill.enable => 'Tap "Allow" for meets, friends and messages.',
        PermPill.on => 'Meets, friends and messages.',
        PermPill.settings => 'Turned off · fix in Settings',
      };

  String _backgroundHint(PermPill pill, BgLocationState s) => switch (pill) {
        PermPill.enable => _ios ? 'Tap "Change to Always Allow".' : 'Choose "Allow all the time".',
        PermPill.on => s.view == BgView.hidden ? 'Paused while you\'re on Nobody.' : 'Friends see you when it\'s closed.',
        PermPill.settings => _ios ? 'Needs "Always" · fix in Settings' : 'Needs "Allow all the time"',
      };

  // ──────────────────────────────────────────────────────────── layout ──

  /// Fades and lifts item [i] into place, each a beat after the one before.
  Widget _rise(int i, Widget child) => AnimatedBuilder(
        animation: _enter,
        builder: (_, c) {
          final start = math.min(i * 0.11, 0.6);
          final t = Interval(start, start + 0.4, curve: Curves.easeOutCubic).transform(_enter.value);
          return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: c));
        },
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final bg = ref.watch(backgroundLocationProvider);
    ref.listen<BgLocationState>(backgroundLocationProvider, (prev, next) {
      if (prev != null && prev.loaded && backgroundPill(prev) != PermPill.on && backgroundPill(next) == PermPill.on) {
        HapticFeedback.lightImpact();
      }
    });
    final bgPill = backgroundPill(bg);
    final locPill = _locationPill;
    final notifPill = _notificationsPill;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return AuthPage(
      lift: 0.16,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _rise(0, Text('TURN ON PERMISSIONS', textAlign: TextAlign.center, style: AuthDark.display(40))),
                    const SizedBox(height: 12),
                    _rise(
                      1,
                      Text(
                        'So the map works for you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, height: 23 / 16, color: AuthDark.text),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _rise(
                      2,
                      PermissionCard(
                        icon: AppIcons.mapPin,
                        title: 'Location',
                        hint: _locationHint(locPill),
                        pill: locPill,
                        busy: _busyLocation || !_loaded,
                        onTap: _enableLocation,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _rise(
                      3,
                      PermissionCard(
                        icon: AppIcons.bell,
                        title: 'Notifications',
                        hint: _notificationsHint(notifPill),
                        pill: notifPill,
                        busy: _busyNotifications || !_loaded,
                        onTap: _enableNotifications,
                      ),
                    ),
                    if (bgPill != null) ...[
                      const SizedBox(height: 12),
                      _rise(
                        4,
                        PermissionCard(
                          icon: AppIcons.navigationArrow,
                          title: 'Share when closed',
                          optional: true,
                          hint: _backgroundHint(bgPill, bg),
                          pill: bgPill,
                          busy: _busyBackground || !bg.loaded,
                          onTap: _enableBackground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _rise(
              5,
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Change these any time in Settings.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AuthDark.text2)),
                    const SizedBox(height: 12),
                    AuthPill(label: 'Continue', onPressed: _continue),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One permission: an icon square, a bold title (with an Optional tag), a
/// line saying what to tap in the phone's prompt, and the button. The button
/// sits on the right when there's room for the words beside it, and under
/// them on a narrow phone or with big text.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.pill,
    required this.onTap,
    this.busy = false,
    this.optional = false,
  });

  final IconData icon;
  final String title;
  final String hint;
  final PermPill pill;
  final VoidCallback onTap;
  final bool busy;
  final bool optional;

  static const green = Color(0xFF3DDC84);

  @override
  Widget build(BuildContext context) {
    final on = pill == PermPill.on;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Title(title, optional: optional),
        const SizedBox(height: 4),
        Text(hint, style: TextStyle(fontSize: 13, height: 1.38, color: AuthDark.text2)),
      ],
    );
    final button = _PillButton(pill: pill, busy: busy, onTap: on ? null : onTap, what: title);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AuthDark.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Room for the words beside the widest button ("Settings")?
          // (At 1.3 on a 412 px phone the words got about 140 px: too thin.)
          final beside = c.maxWidth - 40 - 12 - 10 - _PillButton.widestWidth(context) >= 150;
          final tile = AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: on ? green.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: on ? green : Colors.white),
          );
          if (beside) {
            return Row(
              children: [
                tile,
                const SizedBox(width: 12),
                Expanded(child: words),
                const SizedBox(width: 10),
                button,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tile,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [words, const SizedBox(height: 10), button],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The card title. With [optional], the tag sits inline after it: the last
/// word and the tag are one unbreakable piece, so when the title wraps the
/// tag goes along with "closed" and is never on a line of its own.
class _Title extends StatelessWidget {
  const _Title(this.text, {this.optional = false});
  final String text;
  final bool optional;

  static const _style = TextStyle(fontSize: 16, height: 1.25, fontWeight: FontWeight.w700, color: Colors.white);

  @override
  Widget build(BuildContext context) {
    if (!optional) return Text(text, style: _style);
    final cut = text.lastIndexOf(' ');
    final head = cut < 0 ? '' : text.substring(0, cut + 1);
    final last = cut < 0 ? text : text.substring(cut + 1);
    return Text.rich(
      TextSpan(
        text: head,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            // The span already scales its widget with the text; scaling the
            // word again inside made "closed" bigger than "Share when" at 1.3.
            child: MediaQuery.withNoTextScaling(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  // Flexible: on a line too thin for both, the word gives way.
                  Flexible(child: Text(last, style: _style)),
                  const SizedBox(width: 8),
                  const _Tag('OPTIONAL'),
                ],
              ),
            ),
          ),
        ],
      ),
      style: _style,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
        child: Text(text, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: Colors.white.withValues(alpha: 0.7))),
      );
}

/// Enable (red), On (green check, not a button) or Settings (gear, quiet).
class _PillButton extends StatelessWidget {
  const _PillButton({required this.pill, required this.busy, required this.onTap, required this.what});
  final PermPill pill;
  final bool busy;
  final VoidCallback? onTap;
  /// The card's title, for screen readers.
  final String what;

  static const _style = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  static const _padX = 16.0;
  static const _icon = 16.0;
  static const _gap = 6.0;

  /// The Settings pill's width under the current text size, so a card's
  /// layout doesn't jump when its button changes.
  static double widestWidth(BuildContext context) {
    final tp = TextPainter(
      text: const TextSpan(text: 'Settings', style: _style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w + 2 * _padX + MediaQuery.textScalerOf(context).scale(_icon) + _gap;
  }

  @override
  Widget build(BuildContext context) {
    final (String label, IconData? icon, Color bg, Color fg, Color? edge) = switch (pill) {
      PermPill.enable => ('Enable', null, AppColors.brand, Colors.white, null),
      PermPill.on => ('On', AppIcons.check, PermissionCard.green.withValues(alpha: 0.14), PermissionCard.green, null),
      PermPill.settings => ('Settings', AppIcons.gear, Colors.white.withValues(alpha: 0.08), Colors.white, Colors.white.withValues(alpha: 0.2)),
    };
    final still = MediaQuery.disableAnimationsOf(context);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: MediaQuery.textScalerOf(context).scale(_icon), color: fg), const SizedBox(width: _gap)],
        Text(label, maxLines: 1, style: _style.copyWith(color: fg)),
      ],
    );
    final shape = StadiumBorder(side: edge == null ? BorderSide.none : BorderSide(color: edge));
    final tappable = onTap != null && !busy;
    final pillWidget = Semantics(
      key: ValueKey(pill),
      button: onTap != null,
      label: pill == PermPill.on ? '$what is on' : null,
      child: PressScale(
        enabled: tappable,
        child: Material(
          color: bg,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: tappable ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 38, minWidth: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _padX, vertical: 8),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: busy
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(opacity: 0, child: content),
                            SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                          ],
                        )
                      : content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween<double>(begin: 0.8, end: 1).animate(a), child: child)),
      child: pillWidget,
    );
  }
}
