import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_icons.dart';
import 'app_router.dart' show Routes;

/// Back from a page that may have nothing under it: a deep link, a push
/// notification, a scanned QR or anything else that opened it with
/// `context.go`. Pops when there is a page to go back to, else goes to the
/// map, so the back arrow never does nothing.
void popOrHome(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    // Not under go_router (tests, a plain Navigator route).
    Navigator.maybePop(context);
    return;
  }
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(Routes.map);
  }
}

/// The app bar's back arrow, with [popOrHome]'s fallback.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.icon = AppIcons.arrowLeft});
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Back',
        icon: Icon(icon),
        onPressed: () => popOrHome(context),
      );
}

/// Android's system back on a page with nothing under it would close the
/// app. Wrapped in this, it goes to the map instead (like [AppBackButton]).
/// Pages with something under them pop as usual (iOS swipe-back too).
class HomeOnBack extends StatelessWidget {
  const HomeOnBack({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // ModalRoute.of rebuilds this when the route's canPop changes.
    final route = ModalRoute.of(context);
    final router = GoRouter.maybeOf(context);
    final rootLevel = router != null && route != null && !route.canPop;
    return PopScope(
      canPop: !rootLevel,
      onPopInvokedWithResult: (didPop, _) {
        // Only when this page is why the pop was refused (an inner PopScope,
        // like a form's "discard changes?", handles its own).
        if (didPop || !rootLevel || !context.mounted) return;
        router.go(Routes.map);
      },
      child: child,
    );
  }
}
