import 'dart:io';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/titi/presentation/titi_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final (x, y) = (a.computeLuminance(), b.computeLuminance());
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  test('TiTi AI background ships light and dark, each at most 200 KB', () {
    for (final dark in [false, true]) {
      final f = File(TitiBackground.asset(dark: dark));
      expect(f.existsSync(), isTrue, reason: '${f.path} is missing');
      expect(f.lengthSync(), lessThanOrEqualTo(200 * 1024), reason: '${f.path} is too big');
    }
  });

  test('bubbles stand off the ground and their text reads, light and dark', () {
    for (final dark in [false, true]) {
      AppColors.dark = dark;
      final ground = TitiBackground.ground(dark: dark);
      for (final fill in [TitiBackground.mineFill, AppColors.surface, TitiBackground.pillFill]) {
        expect(_contrast(AppColors.textPrimary, fill), greaterThan(7), reason: 'dark=$dark text on $fill');
      }
      expect(_contrast(AppColors.textSecondary, TitiBackground.pillFill), greaterThan(3), reason: 'dark=$dark status pill');
      expect(_contrast(TitiBackground.mineFill, ground), greaterThan(1.04), reason: 'dark=$dark my bubble vs the ground');
    }
    AppColors.dark = false;
  });
}
