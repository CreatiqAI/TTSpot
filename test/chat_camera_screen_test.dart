import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/social/presentation/chat_camera_screen.dart';

void main() {
  // No camera plugin in tests, so the screen lands on its "can't open" state:
  // that layout must hold on a small phone with big text.
  for (final scale in [1.0, 1.3]) {
    testWidgets('no camera: friendly message, retry and gallery, no overflow at font scale $scale', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: const ChatCameraScreen(),
          ),
        ),
      ));
      // The camera lookup fails on a real future (no plugin); let it land.
      for (var i = 0; i < 20 && find.text('Can\'t open the camera').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Can\'t open the camera'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
