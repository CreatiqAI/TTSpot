import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';

/// The look every page around sign-in shares (sign in, create account, new
/// password, check your email, the intro slides, building your garage):
/// always dark whatever the app theme, a soft lift at the top of the page,
/// a #111318 panel with a 32 px rounded top, dark filled fields with an
/// 18 px radius, red and white 56 px pills. Approved as SignIn.dc.html.
abstract final class AuthDark {
  static const page = Color(0xFF07080B);
  static const lift = Color(0xFF1B1E28);
  static const panel = Color(0xFF111318);
  static const field = Color(0xFF1A1D25);
  static const link = Color(0xFFFF4B50);
  static const error = Color(0xFFFF6B70);
  static final edge = Colors.white.withValues(alpha: 0.14);
  static final text = Colors.white.withValues(alpha: 0.74);
  static final text2 = Colors.white.withValues(alpha: 0.55);

  /// Headline in the display font: 'WELCOME BACK', 'NEVER MISS A MEET'.
  static TextStyle display(double size, {Color color = Colors.white}) =>
      TextStyle(fontFamily: AppFonts.display, fontSize: size, height: 1, fontWeight: FontWeight.w800, color: color);

  /// The app theme, re-coloured for a dark panel: fields, cursor, text,
  /// links and error text. Everything else (sheets, snack bars) stays.
  static ThemeData theme(ThemeData base) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c));
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: base.colorScheme.copyWith(brightness: Brightness.dark, surface: panel, onSurface: Colors.white, error: error),
      scaffoldBackgroundColor: page,
      textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
      textSelectionTheme: TextSelectionThemeData(cursorColor: Colors.white, selectionColor: Colors.white.withValues(alpha: 0.25), selectionHandleColor: Colors.white),
      dividerTheme: DividerThemeData(color: edge, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        hintStyle: TextStyle(color: text2, fontSize: 15),
        helperStyle: TextStyle(color: text, fontSize: 12),
        errorStyle: const TextStyle(color: error, fontSize: 12),
        prefixIconColor: text,
        suffixIconColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: border(edge),
        enabledBorder: border(edge),
        focusedBorder: border(Colors.white.withValues(alpha: 0.5)),
        errorBorder: border(error),
        focusedErrorBorder: border(error),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.white.withValues(alpha: 0.8), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// A dark page: the radial lift at the top, light status-bar icons, the
/// re-coloured theme. [lift] is the ellipse's centre as a fraction of the
/// height (0.18 on sign-in, 0.28 on the intros, 0.38 on the garage screen).
class AuthPage extends StatelessWidget {
  const AuthPage({super.key, required this.child, this.lift = 0.18, this.liftHeight = 0.34, this.resizeToAvoidBottomInset = true});
  final Widget child;
  final double lift;
  final double liftHeight;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(systemNavigationBarColor: AuthDark.page, systemNavigationBarIconBrightness: Brightness.light),
        child: Theme(
          data: AuthDark.theme(Theme.of(context)),
          child: Scaffold(
            backgroundColor: AuthDark.page,
            resizeToAvoidBottomInset: resizeToAvoidBottomInset,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1 + 2 * lift),
                  radius: 1,
                  // The CSS ellipse is 100 % wide and 34 % tall: squash a circle.
                  transform: _Squash(liftHeight / 1),
                  colors: const [AuthDark.lift, AuthDark.page],
                  stops: const [0, 0.8],
                ),
              ),
              child: child,
            ),
          ),
        ),
      );
}

/// Scales the gradient vertically around its centre line so the lift reads
/// as a wide, shallow ellipse.
class _Squash extends GradientTransform {
  const _Squash(this.yScale);
  final double yScale;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final cy = bounds.center.dy;
    return Matrix4.identity()
      ..translateByDouble(0, cy, 0, 1)
      ..scaleByDouble(1, yScale, 1, 1)
      ..translateByDouble(0, -cy, 0, 1);
  }
}

/// The panel: #111318, rounded 32 at the top, hairline edge.
class AuthPanel extends StatelessWidget {
  const AuthPanel({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(24, 26, 24, 0)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AuthDark.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        ),
        child: Padding(padding: padding, child: child),
      );
}

/// 48 px pill. Red with white text by default; [white] flips it. [leading]
/// sits before the label (the Apple logo).
class AuthPill extends StatelessWidget {
  const AuthPill({super.key, required this.label, required this.onPressed, this.loading = false, this.white = false, this.glow, this.leading});
  final String label;
  final Widget? leading;
  final VoidCallback? onPressed;
  final bool loading;
  final bool white;
  /// 0..1: how strong the red glow under the pill is (the intros breathe it).
  final double? glow;

  @override
  Widget build(BuildContext context) {
    final bg = white ? Colors.white : AppColors.brand;
    final fg = white ? AuthDark.page : Colors.white;
    return PressScale(
      enabled: onPressed != null && !loading,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: glow == null ? null : [BoxShadow(color: AppColors.brand.withValues(alpha: 0.45 + 0.4 * glow!), blurRadius: 22 + 18 * glow!)],
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: bg.withValues(alpha: 0.5),
            disabledForegroundColor: fg.withValues(alpha: 0.8),
            minimumSize: const Size.fromHeight(48),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          onPressed: loading ? null : onPressed,
          child: loading
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
              : leading == null
                  ? Text(label)
                  : Row(mainAxisSize: MainAxisSize.min, children: [leading!, const SizedBox(width: 8), Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis))]),
        ),
      ),
    );
  }
}

/// "── or ──"
class AuthOr extends StatelessWidget {
  const AuthOr({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Container(height: 1, color: AuthDark.edge)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7))),
            ),
            Expanded(child: Container(height: 1, color: AuthDark.edge)),
          ],
        ),
      );
}

/// Small white icon button for the top corners (back, close).
class AuthIconButton extends StatelessWidget {
  const AuthIconButton({super.key, required this.icon, required this.onPressed, required this.tooltip});
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 24, color: Colors.white.withValues(alpha: onPressed == null ? 0.4 : 0.9)),
        onPressed: onPressed,
      );
}
