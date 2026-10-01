import 'dart:io';

import 'package:car_meet/features/social/presentation/chat_stickers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every sticker in a pack has its art bundled', () {
    for (final p in kStickerPacks) {
      for (final k in p.keys) {
        expect(File(p.asset(k)).existsSync(), isTrue, reason: '${p.asset(k)} is missing');
      }
    }
  });

  test('sticker keys are unique and never reuse a legacy key', () {
    final all = [for (final p in kStickerPacks) ...p.keys];
    expect(all.toSet().length, all.length);
    expect(all.where(kLegacyStickers.containsKey), isEmpty);
  });

  test('old messages still find their art', () {
    expect(stickerAsset('titi_otw'), 'assets/stickers/titi/titi_otw.webp');
    expect(stickerAsset('car_vroom'), 'assets/stickers/car/car_vroom.webp');
    expect(stickerAsset('thumbsUp'), isNull);
    expect(kLegacyStickers['thumbsUp'], isNotNull);
  });
}
