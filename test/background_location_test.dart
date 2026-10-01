import 'package:car_meet/core/location/background_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = 'user-a';

  BgAction decide({
    bool enabled = true,
    String? owner = me,
    String? current = me,
    bool always = true,
    String? mode = 'friends',
    bool running = false,
    bool paused = false,
  }) =>
      decideBgAction(
        enabled: enabled,
        ownerId: owner,
        currentUserId: current,
        alwaysAllowed: always,
        shareMode: mode,
        running: running,
        paused: paused,
      );

  group('decideBgAction', () {
    test('off on this phone: never touches native', () {
      expect(decide(enabled: false), BgAction.none);
      expect(decide(enabled: false, current: null), BgAction.none);
      expect(decide(enabled: false, mode: 'ghost', running: true), BgAction.none);
    });

    test('signed out: forget (stop + revoke)', () {
      expect(decide(current: null), BgAction.forget);
      expect(decide(current: null, running: true), BgAction.forget);
    });

    test('another member signed in on this phone: forget', () {
      expect(decide(owner: 'user-b'), BgAction.forget);
      expect(decide(owner: null), BgAction.forget);
    });

    test('Nobody (ghost) pauses, never runs', () {
      expect(decide(mode: 'ghost', running: true), BgAction.pause);
      expect(decide(mode: 'ghost', running: false, paused: false), BgAction.pause);
      expect(decide(mode: 'ghost', running: false, paused: true), BgAction.none);
    });

    test('lost "Allow all the time" pauses', () {
      expect(decide(always: false, running: true), BgAction.pause);
      expect(decide(always: false, running: false, paused: true), BgAction.none);
    });

    test('visible and allowed: make sure it runs', () {
      for (final mode in ['friends', 'nearby', 'public']) {
        expect(decide(mode: mode, running: false), BgAction.run, reason: mode);
        expect(decide(mode: mode, running: true), BgAction.none, reason: mode);
      }
      // back from Nobody
      expect(decide(mode: 'friends', running: false, paused: true), BgAction.run);
    });

    test('visibility still loading counts as visible (the server checks ghost anyway)', () {
      expect(decide(mode: null, running: false), BgAction.run);
    });
  });

  group('bgViewFor', () {
    BgView view({bool supported = true, bool enabled = true, bool always = true, String? mode = 'friends'}) =>
        bgViewFor(supported: supported, enabled: enabled, alwaysAllowed: always, shareMode: mode);

    test('states', () {
      expect(view(supported: false), BgView.unsupported);
      expect(view(enabled: false), BgView.off);
      expect(view(enabled: false, always: false), BgView.off);
      expect(view(), BgView.on);
      expect(view(always: false), BgView.needsAlways);
      expect(view(mode: 'ghost'), BgView.hidden);
      // a missing permission is the thing to fix first
      expect(view(mode: 'ghost', always: false), BgView.needsAlways);
    });

    test('labels', () {
      expect(bgSubtitle(BgView.off, ios: false), 'Off');
      expect(bgSubtitle(BgView.on, ios: true), 'On · Always allowed');
      expect(bgSubtitle(BgView.needsAlways, ios: false), 'Needs "Allow all the time"');
      expect(bgSubtitle(BgView.hidden, ios: false), contains('Nobody'));
    });
  });

  test('NativeBgStatus.fromMap', () {
    final s = NativeBgStatus.fromMap({
      'enabled': true,
      'paused': false,
      'running': true,
      'userId': me,
      'lastResult': 'ok',
      'lastAt': 1759312800000,
      'background': true,
      'foreground': true,
      'device': 'Pixel 8 (1a2b3c4d)',
    });
    expect(s.supported, isTrue);
    expect(s.enabled && s.running && s.background, isTrue);
    expect(s.userId, me);
    expect(s.lastAt, DateTime.fromMillisecondsSinceEpoch(1759312800000));
    expect(s.device, 'Pixel 8 (1a2b3c4d)');
    expect(NativeBgStatus.fromMap({'device': '  '}).device, 'phone');
  });
}
