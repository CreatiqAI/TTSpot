import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/application/auth_controller.dart';
import 'package:car_meet/features/auth/presentation/sign_in_screen.dart';

/// Stands in for Supabase: every attempt works, or every attempt fails.
class _FakeAuth extends AuthController {
  _FakeAuth({required this.ok});
  final bool ok;

  void _settle() => state = ok ? const AsyncData(null) : AsyncError(Exception('Wrong email or password.'), StackTrace.current);

  @override
  Future<bool> signIn({required String email, required String password}) async {
    _settle();
    return ok;
  }

  @override
  Future<({bool ok, bool needsCode})> signUp({required String email, required String password}) async {
    _settle();
    return (ok: ok, needsCode: false);
  }
}

/// Sign in and Create an account share the dark panel, switch both ways, carry the autofill
/// hints iCloud Keychain and Google Password Manager need, and fit a small
/// phone (320 x 568) at 1.3x text in light and dark without overflowing.
/// The test font draws every glyph a full em wide, wider than the real ones,
/// so fitting here means fitting on the phone.
void main() {
  Future<void> pump(WidgetTester tester, {required bool signUp, required bool dark, bool? authOk}) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    AppColors.dark = dark;
    addTearDown(() => AppColors.dark = false);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/sign-in', builder: (_, s) => SignInScreen(signUp: s.uri.queryParameters['mode'] == 'signup')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [if (authOk != null) authControllerProvider.overrideWith(() => _FakeAuth(ok: authOk))],
      child: MaterialApp.router(
        theme: AppTheme.current,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
      ),
    ));
    router.push(signUp ? '/sign-in?mode=signup' : '/sign-in');
    await tester.pumpAndSettle();
  }

  List<Iterable<String>?> hints(WidgetTester tester) =>
      tester.widgetList<EditableText>(find.byType(EditableText)).map((e) => e.autofillHints).toList();

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('Log in, $theme', (tester) async {
      await pump(tester, signUp: false, dark: dark);
      expect(find.text('WELCOME BACK'), findsOneWidget);
      expect(find.text('Sign in and pick up where you parked.'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('CREATE YOUR ACCOUNT'), findsNothing);
      expect(find.byType(AutofillGroup), findsOneWidget);
      expect(hints(tester), [
        [AutofillHints.username, AutofillHints.email],
        [AutofillHints.password],
      ]);

      // To Sign up and back (the link scrolls with the panel on a short phone).
      await tester.ensureVisible(find.textContaining('Create an account'));
      await tester.tap(find.textContaining('Create an account'));
      await tester.pumpAndSettle();
      expect(find.text('WELCOME BACK'), findsNothing);
      expect(find.text('CREATE YOUR ACCOUNT'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Have an account?'));
      await tester.tap(find.textContaining('Have an account?'));
      await tester.pumpAndSettle();
      expect(find.text('WELCOME BACK'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('Sign up, $theme', (tester) async {
      await pump(tester, signUp: true, dark: dark);
      expect(find.text('CREATE YOUR ACCOUNT'), findsOneWidget);
      expect(find.text('Free. Two minutes to join.'), findsOneWidget);
      expect(find.textContaining('6-digit code'), findsOneWidget);
      expect(find.text('Sign up'), findsOneWidget);
      expect(find.text('Forgot password?'), findsNothing);
      expect(hints(tester), [
        [AutofillHints.email],
        [AutofillHints.newPassword],
      ]);

      // The strength hint follows the password.
      final password = find.byType(EditableText).last;
      await tester.enterText(password, 'abc');
      await tester.pump();
      expect(find.textContaining('Too short'), findsOneWidget);
      await tester.enterText(password, 'abcdefg');
      await tester.pump();
      expect(find.textContaining('Weak'), findsOneWidget);
      await tester.enterText(password, 'abcdef12');
      await tester.pump();
      expect(find.textContaining('Okay'), findsOneWidget);
      await tester.enterText(password, 'Abcdef12!xyz');
      await tester.pump();
      expect(find.text('Strong password.'), findsOneWidget);

      // Show / hide.
      expect(tester.widget<EditableText>(password).obscureText, isTrue);
      await tester.ensureVisible(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<EditableText>(find.byType(EditableText).last).obscureText, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    // iPhone adds the OR divider and the Apple button: the tallest layouts.
    testWidgets('Both modes on iPhone, $theme', (tester) async {
      await pump(tester, signUp: true, dark: dark);
      expect(find.text('Sign up with Apple'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Have an account?'));
      await tester.tap(find.textContaining('Have an account?'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Apple'), findsOneWidget);
      expect(find.text('WELCOME BACK'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  // The password manager is asked to save only after the server said yes.
  // finishAutofillContext(true) offers to save; false throws the typing away.
  List<bool> finishes(WidgetTester tester) => [
        for (final c in tester.testTextInput.log)
          if (c.method == 'TextInput.finishAutofillContext') c.arguments as bool,
      ];

  for (final signUp in [false, true]) {
    final what = signUp ? 'Sign up' : 'Sign in';

    testWidgets('$what that works offers to save the password', (tester) async {
      await pump(tester, signUp: signUp, dark: false, authOk: true);
      await tester.enterText(find.byType(EditableText).first, 'driver@example.com');
      await tester.enterText(find.byType(EditableText).last, 'Abcdef12!xyz');
      tester.testTextInput.log.clear();
      await tester.ensureVisible(find.text(what));
      await tester.tap(find.text(what));
      await tester.pump();
      expect(finishes(tester), [true]);
    });

    testWidgets('$what that fails never offers to save', (tester) async {
      await pump(tester, signUp: signUp, dark: false, authOk: false);
      await tester.enterText(find.byType(EditableText).first, 'driver@example.com');
      await tester.enterText(find.byType(EditableText).last, 'Abcdef12!xyz');
      tester.testTextInput.log.clear();
      await tester.ensureVisible(find.text(what));
      await tester.tap(find.text(what));
      await tester.pump();
      expect(finishes(tester), isEmpty);
      // Leaving the page cancels the context instead of saving it.
      await tester.pumpWidget(const SizedBox());
      expect(finishes(tester), [false]);
    });
  }
}
