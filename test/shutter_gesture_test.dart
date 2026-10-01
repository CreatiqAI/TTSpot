import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/core/config/media.dart';
import 'package:car_meet/features/social/domain/shutter_gesture.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  ShutterGesture make() => ShutterGesture(maxClip: kChatVideoMaxDuration);

  group('chat camera shutter: tap vs hold', () {
    test('the hold threshold is 0.5 s and the longest video is the chat cap', () {
      final s = make();
      expect(s.holdThreshold, ms(500));
      expect(s.maxClip, kChatVideoMaxDuration);
    });

    test('a quick tap takes a photo', () {
      final s = make();
      expect(s.down(ms(0)), ShutterAction.none);
      expect(s.phase, ShutterPhase.pressed);
      expect(s.up(ms(120)), ShutterAction.takePhoto);
      expect(s.phase, ShutterPhase.busy);
    });

    test('the hold timer does nothing before 0.5 s', () {
      final s = make()..down(ms(0));
      expect(s.holdCheck(ms(499)), ShutterAction.none);
      expect(s.phase, ShutterPhase.pressed);
    });

    test('a press just under 0.5 s is still a photo, never a video', () {
      final s = make()..down(ms(0));
      expect(s.holdCheck(ms(300)), ShutterAction.none);
      expect(s.up(ms(499)), ShutterAction.takePhoto);
      // A late hold timer after the release can't start a video.
      expect(s.holdCheck(ms(520)), ShutterAction.none);
      expect(s.isVideo, isFalse);
    });

    test('a release before the recorder started (timer late) is a photo', () {
      final s = make()..down(ms(0));
      // The hold timer hasn't fired yet when the finger lifts at 0.6 s.
      expect(s.up(ms(600)), ShutterAction.takePhoto);
    });

    test('holding 0.5 s starts a video; letting go stops it', () {
      final s = make()..down(ms(0));
      expect(s.holdCheck(ms(500)), ShutterAction.startVideo);
      expect(s.phase, ShutterPhase.recording);
      expect(s.isVideo, isTrue);
      s.started(ms(560));
      expect(s.isRolling, isTrue);
      expect(s.recorded(ms(3560)), const Duration(seconds: 3));
      expect(s.up(ms(3560)), ShutterAction.stopVideo);
      expect(s.phase, ShutterPhase.busy);
      s.done();
      expect(s.phase, ShutterPhase.idle);
    });

    test('the hold timer only starts one video', () {
      final s = make()..down(ms(0));
      expect(s.holdCheck(ms(500)), ShutterAction.startVideo);
      expect(s.holdCheck(ms(700)), ShutterAction.none);
    });

    test('a release right after recording starts waits for a 1 s clip', () {
      final s = make()..down(ms(0));
      s.holdCheck(ms(500));
      s.started(ms(550));
      expect(s.up(ms(700)), ShutterAction.none);
      expect(s.stopQueued, isTrue);
      expect(s.tick(ms(1200)), ShutterAction.none);
      expect(s.tick(ms(1550)), ShutterAction.stopVideo);
      expect(s.phase, ShutterPhase.busy);
    });

    test('a release while the recorder is still starting stops once it has run 1 s', () {
      final s = make()..down(ms(0));
      s.holdCheck(ms(500));
      expect(s.up(ms(600)), ShutterAction.none);
      expect(s.stopQueued, isTrue);
      // Ticks before the start is confirmed do nothing.
      expect(s.tick(ms(700)), ShutterAction.none);
      s.started(ms(800));
      expect(s.tick(ms(1700)), ShutterAction.none);
      expect(s.tick(ms(1800)), ShutterAction.stopVideo);
    });

    test('sliding up 80 px while recording locks it hands-free', () {
      final s = make()..down(ms(0));
      s.holdCheck(ms(500));
      s.started(ms(550));
      expect(s.move(-40), ShutterAction.none);
      expect(s.lockProgress, closeTo(0.5, 0.001));
      expect(s.move(-80), ShutterAction.lock);
      expect(s.phase, ShutterPhase.locked);
      // Lifting the finger keeps it recording.
      expect(s.up(ms(2000)), ShutterAction.none);
      expect(s.phase, ShutterPhase.locked);
      // The stop button ends it.
      expect(s.stopTapped(ms(5000)), ShutterAction.stopVideo);
    });

    test('sliding down does not lock', () {
      final s = make()..down(ms(0));
      s.holdCheck(ms(500));
      expect(s.move(120), ShutterAction.none);
      expect(s.dragY, 0);
      expect(s.phase, ShutterPhase.recording);
    });

    test('sliding before the threshold neither locks nor records', () {
      final s = make()..down(ms(0));
      expect(s.move(-200), ShutterAction.none);
      expect(s.phase, ShutterPhase.pressed);
      expect(s.up(ms(300)), ShutterAction.takePhoto);
    });

    test('a video stops itself at the chat max length', () {
      final s = make()..down(ms(0));
      s.holdCheck(ms(500));
      s.started(ms(500));
      s.move(-100); // locked
      expect(s.tick(ms(500) + kChatVideoMaxDuration - ms(1)), ShutterAction.none);
      expect(s.tick(ms(500) + kChatVideoMaxDuration), ShutterAction.stopVideo);
      expect(s.recorded(ms(500) + kChatVideoMaxDuration), Duration.zero); // finished
    });

    test('the system taking the touch: a press is dropped, a held video is kept', () {
      final a = make()..down(ms(0));
      expect(a.cancel(ms(200)), ShutterAction.none);
      expect(a.phase, ShutterPhase.idle);

      final b = make()..down(ms(0));
      b.holdCheck(ms(500));
      b.started(ms(500));
      expect(b.cancel(ms(4000)), ShutterAction.stopVideo);
    });

    test('input is ignored while busy, until done', () {
      final s = make()..down(ms(0));
      s.up(ms(100)); // photo
      expect(s.down(ms(150)), ShutterAction.none);
      expect(s.phase, ShutterPhase.busy);
      expect(s.up(ms(200)), ShutterAction.none);
      s.done();
      s.down(ms(300));
      expect(s.phase, ShutterPhase.pressed);
    });

    test('stop does nothing unless locked', () {
      final s = make()..down(ms(0));
      s.holdCheck(ms(500));
      s.started(ms(500));
      expect(s.stopTapped(ms(3000)), ShutterAction.none);
      expect(s.phase, ShutterPhase.recording);
    });
  });
}
