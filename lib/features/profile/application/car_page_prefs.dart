import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Cars whose "Make it look pro" card the owner closed, remembered on this
/// phone only (a small JSON file in the app's support folder). Missing or
/// unreadable reads as none closed.
class CarPromoDismissals extends AsyncNotifier<Set<String>> {
  static const _file = 'car_promo_dismissed.json';

  Future<File> _path() async => File('${(await getApplicationSupportDirectory()).path}/$_file');

  @override
  Future<Set<String>> build() async {
    try {
      final f = await _path();
      if (!await f.exists()) return const {};
      final list = jsonDecode(await f.readAsString());
      return list is List ? list.whereType<String>().toSet() : const {};
    } catch (e) {
      if (kDebugMode) debugPrint('Car promo dismissals unreadable: $e');
      return const {};
    }
  }

  Future<void> dismiss(String carId) async {
    final next = {...?state.value, carId};
    state = AsyncData(next);
    try {
      final f = await _path();
      await f.writeAsString(jsonEncode(next.toList()), flush: true);
    } catch (e) {
      if (kDebugMode) debugPrint('Car promo dismissal not saved: $e');
    }
  }
}

final carPromoDismissalsProvider = AsyncNotifierProvider<CarPromoDismissals, Set<String>>(CarPromoDismissals.new);
