import 'dart:io';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/social/presentation/widgets/media_send_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  // A real (tiny) photo on disk, as the picker would hand back.
  late Directory dir;
  late List<XFile> photos;
  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('msp');
    final png = File('assets/stickers/titi/titi_otw.webp').readAsBytesSync();
    photos = [
      for (var i = 0; i < 2; i++) XFile((File('${dir.path}/p$i.webp')..writeAsBytesSync(png)).path),
    ];
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  Future<void> pump(WidgetTester t, {double keyboard = 0}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
          child: MediaSendPreview(files: photos),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('photos: caption field, Send, thumbnails with remove and add', (t) async {
    await pump(t);
    expect(find.text('Add a caption…'), findsOneWidget);
    expect(find.bySemanticsLabel('Send'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove'), findsNWidgets(2));
    expect(find.text('1 of 2'), findsOneWidget);
    // The caption bar sits at the bottom of the screen.
    final field = t.getRect(find.byType(TextField));
    expect(field.bottom, greaterThan(800));
    expect(t.takeException(), isNull);
  });

  testWidgets('captions are per item', (t) async {
    await pump(t);
    await t.enterText(find.byType(TextField), 'first one');
    await t.tap(find.bySemanticsLabel('Remove').last); // drop the second
    await t.pump();
    expect(find.text('first one'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove'), findsOneWidget);
  });

  testWidgets('the keyboard pushes the caption bar up, not over it', (t) async {
    await pump(t, keyboard: 300);
    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    final field = t.getRect(find.byType(TextField));
    expect(field.bottom, lessThanOrEqualTo(screen.height - 300));
    expect(t.takeException(), isNull);
  });
}
