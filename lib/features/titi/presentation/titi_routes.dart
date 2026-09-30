import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';

/// App paths TiTi may open, from a link in his text or an action card (the
/// function's APP_LINKS and PAGE_TITLES, plus id pages). Anything else stays
/// plain words.
const _appPaths = [
  Routes.points, Routes.cards, Routes.rewards, Routes.scan, Routes.myQr, Routes.friends, Routes.meets, Routes.clubs,
  Routes.map, Routes.inbox, Routes.explore, Routes.garage, Routes.suggestSpot, Routes.newCar, Routes.myGarage,
  Routes.createEvent, Routes.organizerApply, Routes.clubApply, Routes.partnerApply, Routes.settings, Routes.pushSettings,
  Routes.myMoments, Routes.activity, Routes.saved,
  '/event/', '/place/', '/club/', '/partner/', '/car/', '/profile/', '/voucher/', '/cards/box/', '/cards/prize/',
];

/// The four tabs switch branch; everything else stacks on top.
const _tabs = {Routes.explore, Routes.map, Routes.inbox, Routes.garage};

/// Whether TiTi may open [target] inside the app.
bool titiCanOpen(String target) {
  final path = Uri.tryParse(target)?.path ?? '';
  return _appPaths.any((p) => p.endsWith('/') ? path.startsWith(p) && path.length > p.length : path == p);
}

/// Opens an app path TiTi gave (a tab switches, a page is pushed). False
/// when it isn't one he may open.
bool openTitiRoute(BuildContext context, String target) {
  if (!titiCanOpen(target)) return false;
  final path = Uri.parse(target).path;
  if (_tabs.contains(path)) {
    context.go(target);
  } else {
    context.push(target);
  }
  return true;
}
