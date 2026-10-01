import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/social/domain/voice_wave.dart';
import 'package:car_meet/features/social/presentation/widgets/chat_reply.dart';

void main() {
  group('voice note waveform', () {
    test('squeezes a long take into 50 bars of 0..100, loud parts tallest', () {
      // 10 s at 10 samples/s: quiet first half, loud second half.
      final levels = [for (var i = 0; i < 100; i++) i < 50 ? 0.1 : 0.8];
      final wave = downsampleWave(levels);
      expect(wave, hasLength(kVoiceWaveBars));
      expect(wave.every((v) => v >= 0 && v <= 100), isTrue);
      expect(wave.last, 100);
      expect(wave.first, lessThan(wave.last ~/ 4));
    });

    test('a short spike survives (peak per bar, not average)', () {
      final levels = List<double>.filled(500, 0.05)..[251] = 0.9;
      final wave = downsampleWave(levels, bars: 50);
      expect(wave.reduce((a, b) => a > b ? a : b), 100);
      expect(wave.where((v) => v == 100), hasLength(1));
    });

    test('stretches a very short take to the bar count', () {
      final wave = downsampleWave([0.2, 0.6, 1.0], bars: 40);
      expect(wave, hasLength(40));
      expect(wave.first, 20);
      expect(wave.last, 100);
    });

    test('lifts a quiet take at most 4x', () {
      final wave = downsampleWave(List<double>.filled(60, 0.1));
      expect(wave.every((v) => v == 40), isTrue);
    });

    test('nothing recorded -> no bars; values outside 0..1 are clamped', () {
      expect(downsampleWave(const []), isEmpty);
      final wave = downsampleWave([-1, 2, 0.5], bars: 3);
      expect(wave, [0, 100, 50]);
    });

    test('dBFS maps to 0..1', () {
      expect(dbfsToLevel(-160), 0);
      expect(dbfsToLevel(0), 1);
      expect(dbfsToLevel(-22.5), closeTo(0.5, 1e-9));
      expect(dbfsToLevel(double.nan), 0);
    });

    test('stand-in waveform is stable per message and differs between messages', () {
      final a = pseudoWave('7f3c0e7a-1111-4b8e-9d55-000000000001');
      expect(a, hasLength(kVoiceWaveBars));
      expect(a.every((v) => v >= 8 && v <= 100), isTrue);
      expect(pseudoWave('7f3c0e7a-1111-4b8e-9d55-000000000001'), a);
      expect(pseudoWave('7f3c0e7a-1111-4b8e-9d55-000000000002'), isNot(a));
    });

    test('reads smallint[] from the API and from a realtime payload', () {
      expect(parseWave(null), isNull);
      expect(parseWave([1, 2.0, 3]), [1, 2, 3]);
      expect(parseWave('{4,5,6}'), [4, 5, 6]);
      expect(parseWave('{}'), isEmpty);
    });
  });

  group('swipe to reply', () {
    late List<MethodCall> platformCalls;

    setUp(() {
      platformCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> pump(WidgetTester tester, {required VoidCallback onReply, bool enabled = true}) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SwipeToReply(
                  enabled: enabled,
                  onReply: onReply,
                  child: Container(key: const Key('bubble'), width: 200, height: 48, color: const Color(0xFFEEEEEE), child: const Text('hello')),
                ),
              ),
            ),
          ),
        );

    bool haptic() => platformCalls.any((c) => c.method == 'HapticFeedback.vibrate' && c.arguments == 'HapticFeedbackType.selectionClick');

    testWidgets('a long swipe right replies, with a haptic tick, and springs back', (tester) async {
      var replies = 0;
      await pump(tester, onReply: () => replies++);
      final start = tester.getTopLeft(find.byKey(const Key('bubble')));

      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('bubble'))));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      // Mid-swipe: the bubble has moved right and the arrow has faded in.
      expect(tester.getTopLeft(find.byKey(const Key('bubble'))).dx, greaterThan(start.dx + SwipeToReply.threshold - 1));
      expect(haptic(), isTrue);
      expect(replies, 0);

      await g.up();
      await tester.pumpAndSettle();
      expect(replies, 1);
      expect(tester.getTopLeft(find.byKey(const Key('bubble'))), start);
    });

    testWidgets('a short swipe does nothing', (tester) async {
      var replies = 0;
      await pump(tester, onReply: () => replies++);
      await tester.drag(find.byKey(const Key('bubble')), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(replies, 0);
      expect(haptic(), isFalse);
    });

    testWidgets('swiping left does nothing', (tester) async {
      var replies = 0;
      await pump(tester, onReply: () => replies++);
      final start = tester.getTopLeft(find.byKey(const Key('bubble')));
      await tester.drag(find.byKey(const Key('bubble')), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(replies, 0);
      expect(tester.getTopLeft(find.byKey(const Key('bubble'))), start);
    });

    testWidgets('a quote whose original is gone says so, and stays tappable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 260, child: ReplyQuote(original: null, name: '', mine: false, onTap: () => taps++)),
          ),
        ),
      ));
      expect(find.text('Original message unavailable'), findsOneWidget);
      await tester.tap(find.byType(ReplyQuote));
      expect(taps, 1);
    });

    testWidgets('disabled (deleted account chat): no reply', (tester) async {
      var replies = 0;
      await pump(tester, onReply: () => replies++, enabled: false);
      await tester.drag(find.byKey(const Key('bubble')), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(replies, 0);
    });
  });
}
