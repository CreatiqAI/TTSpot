import 'dart:convert';

import 'package:car_meet/core/widgets/photo_viewer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1x1 PNG, so the viewer shows a real picture without the network.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Future<void> _open(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(PageRouteBuilder<void>(
              opaque: false,
              pageBuilder: (_, _, _) => PhotoViewer(urls: const ['a'], imageFor: (_) => MemoryImage(_png)),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  expect(find.byType(PhotoViewer), findsOneWidget);
}

double _scale(WidgetTester t) => t.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value.getMaxScaleOnAxis();

void main() {
  testWidgets('a single tap closes once the double-tap window has passed', (t) async {
    await _open(t);
    await t.tap(find.byType(InteractiveViewer));
    // Still inside the double-tap window: nothing yet.
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(PhotoViewer), findsOneWidget);
    await t.pump(kDoubleTapTimeout);
    await t.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
  });

  testWidgets('a double tap zooms and does not close; a tap on the zoomed photo zooms out first', (t) async {
    await _open(t);
    final at = t.getCenter(find.byType(InteractiveViewer));
    await t.tapAt(at);
    await t.pump(const Duration(milliseconds: 80));
    await t.tapAt(at);
    await t.pump(kDoubleTapTimeout * 2);
    await t.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget, reason: 'a double tap must not close the viewer');
    expect(_scale(t), greaterThan(2));

    // Zoomed: one tap only zooms back out.
    await t.tapAt(at);
    await t.pump(kDoubleTapTimeout * 2);
    await t.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);
    expect(_scale(t), closeTo(1, 0.01));

    // Back at 1x: the next tap closes.
    await t.tapAt(at);
    await t.pump(kDoubleTapTimeout * 2);
    await t.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
  });

  testWidgets('the X still closes at once', (t) async {
    await _open(t);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
  });
}
