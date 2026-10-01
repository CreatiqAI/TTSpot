import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kDebugMode, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/env.dart';
import '../../../core/location/background_location.dart';
import '../../../core/push/push_service.dart' show rootMessengerKey;
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../friends/application/friends_providers.dart';

/// Settings → Privacy → "Share location when TT Spot is closed" (off by default).
class BgLocationState {
  const BgLocationState({this.native = NativeBgStatus.unsupported, this.shareMode, this.loaded = false, this.waitingForAlways = false});

  final NativeBgStatus native;
  /// My map visibility ('friends' | 'nearby' | 'public' | 'ghost'), null while loading.
  final String? shareMode;
  final bool loaded;
  /// Turned on, then sent to phone settings for "Allow all the time": finish
  /// turning it on as soon as the member comes back with it granted.
  final bool waitingForAlways;

  bool get enabled => native.enabled;
  BgView get view => bgViewFor(supported: native.supported, enabled: native.enabled, alwaysAllowed: native.background, shareMode: shareMode);

  BgLocationState copyWith({NativeBgStatus? native, String? shareMode, bool? loaded, bool? waitingForAlways}) => BgLocationState(
        native: native ?? this.native,
        shareMode: shareMode ?? this.shareMode,
        loaded: loaded ?? this.loaded,
        waitingForAlways: waitingForAlways ?? this.waitingForAlways,
      );
}

/// How turning it on went, for the Settings screen to explain.
enum BgEnableOutcome { on, needsAlways, locationOff, denied, blocked, failed }

/// Keeps the native side in step with who is signed in, my map visibility and
/// the phone's permission. Lives for the whole app (main.dart holds it), so a
/// sign-out or another member signing in always stops and revokes this
/// phone's token, even when Settings was never opened.
class BackgroundLocationController extends Notifier<BgLocationState> {
  bool _syncing = false;
  bool _again = false;
  bool _againFromResume = false;

  @override
  BgLocationState build() {
    ref.listen<String?>(currentUserIdProvider, (prev, next) {
      if (prev != next) unawaited(sync());
    });
    ref.listen<String?>(myLocationProvider.select((v) => v.value?.shareMode), (prev, next) {
      if (prev != next) unawaited(sync());
    });
    Future.microtask(sync);
    return const BgLocationState();
  }

  /// Re-read everything and fix the native side. [fromResume]: back from the
  /// background, so also warn if "Allow all the time" was taken away.
  Future<void> sync({bool fromResume = false}) async {
    if (!BgLocationNative.supported) {
      state = state.copyWith(loaded: true);
      return;
    }
    if (_syncing) {
      _again = true;
      _againFromResume |= fromResume;
      return;
    }
    _syncing = true;
    try {
      var resume = fromResume;
      do {
        _again = false;
        await _syncOnce(resume);
        resume = _againFromResume;
        _againFromResume = false;
      } while (_again);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce(bool fromResume) async {
    final before = state;
    var st = await BgLocationNative.status();
    final me = ref.read(currentUserIdProvider);
    final mode = ref.read(myLocationProvider).value?.shareMode;
    final action = decideBgAction(
      enabled: st.enabled,
      ownerId: st.userId,
      currentUserId: me,
      alwaysAllowed: st.background,
      shareMode: mode,
      running: st.running,
      paused: st.paused,
    );
    switch (action) {
      case BgAction.run:
        await BgLocationNative.resume();
      case BgAction.pause:
        await BgLocationNative.pause();
      case BgAction.forget:
        await BgLocationNative.stop(revoke: true);
      case BgAction.none:
        break;
    }
    if (action != BgAction.none) st = await BgLocationNative.status();
    state = BgLocationState(native: st, shareMode: mode, loaded: true, waitingForAlways: before.waitingForAlways && !st.enabled && me != null);

    if (state.waitingForAlways && st.background) {
      // Back from phone settings with "Allow all the time": finish the job.
      try {
        await _finishEnable();
      } catch (_) {
        state = state.copyWith(waitingForAlways: false);
      }
      return;
    }
    if (fromResume && st.enabled && before.loaded && before.native.background && !st.background) _warnDowngraded();
  }

  /// After the member accepted the disclosure. Walks the phone's permission
  /// steps, then makes this phone's token and starts the native side.
  Future<BgEnableOutcome> enable() async {
    if (!BgLocationNative.supported || ref.read(currentUserIdProvider) == null) return BgEnableOutcome.failed;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
        return BgEnableOutcome.locationOff;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.deniedForever) return BgEnableOutcome.blocked;
      if (p == LocationPermission.denied || p == LocationPermission.unableToDetermine) return BgEnableOutcome.denied;
      if (p != LocationPermission.always) {
        // Set first: on Android 11+ the answer comes from phone settings, and the
        // resume sync may see "Allow all the time" before this call returns.
        state = state.copyWith(waitingForAlways: true);
        final granted = await BgLocationNative.requestBackground();
        if (!granted) return BgEnableOutcome.needsAlways;
      }
      await _finishEnable();
      return (await BgLocationNative.status()).enabled ? BgEnableOutcome.on : BgEnableOutcome.failed;
    } catch (_) {
      state = state.copyWith(waitingForAlways: false);
      return BgEnableOutcome.failed;
    }
  }

  /// One at a time: the resume sync and [enable] can both get here, and a
  /// second token for this phone would revoke the first.
  Future<void> _finishEnable() => _enabling ??= _doFinishEnable().whenComplete(() => _enabling = null);
  Future<void>? _enabling;

  Future<void> _doFinishEnable() async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    if ((await BgLocationNative.status()).enabled) return;
    final device = (await BgLocationNative.status()).device;
    final token = await ref.read(supabaseProvider).rpc('create_location_token', params: {'p_device': device}) as String;
    await BgLocationNative.start(
      token: token,
      url: Env.supabaseUrl,
      key: Env.supabasePublishableKey,
      userId: me,
      // Debug builds on a PC whose antivirus re-signs HTTPS (see main.dart).
      devCa: kDebugMode && Env.devExtraCaPemB64.isNotEmpty ? Env.devExtraCaPemB64 : null,
    );
    state = state.copyWith(waitingForAlways: false);
    unawaited(sync()); // pause straight away if I'm on Nobody
  }

  /// Off: stop the native side and revoke this phone's token.
  Future<void> disable() async {
    state = state.copyWith(waitingForAlways: false);
    final st = await BgLocationNative.status();
    await BgLocationNative.stop(revoke: true);
    await _revokeOnServer(st.device);
    await sync();
  }

  /// Log out: called while the session still works, so every token this
  /// phone ever made goes, not just the one it holds.
  /// Never throws: logging out must always work.
  Future<void> beforeSignOut() async {
    if (!BgLocationNative.supported) return;
    try {
      final st = await BgLocationNative.status();
      if (st.enabled) await BgLocationNative.stop(revoke: true);
      if (st.enabled || st.lastResult != null) await _revokeOnServer(st.device);
      state = state.copyWith(waitingForAlways: false);
    } catch (_) {}
  }

  Future<void> _revokeOnServer(String device) async {
    try {
      await ref.read(supabaseProvider).rpc('revoke_location_tokens', params: {'p_device': device}).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline: the native side already revoked its token with the token itself.
    }
  }

  void _warnDowngraded() {
    final what = defaultTargetPlatform == TargetPlatform.iOS ? '"Always" location' : '"Allow all the time"';
    rootMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Text('TT Spot can\'t share your location while closed: $what was turned off.'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(label: 'Fix', onPressed: () => ref.read(appRouterProvider).push(Routes.settings)),
    ));
  }
}

final backgroundLocationProvider = NotifierProvider<BackgroundLocationController, BgLocationState>(BackgroundLocationController.new);
