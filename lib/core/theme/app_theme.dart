import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One set of surface / text colours. Light is the white Instagram-style
/// ground; dark is the map's night palette carried across the whole app.
class _Palette {
  const _Palette({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceGray,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.snack,
  });
  final Color bg, surface, surfaceRaised, surfaceGray, border, divider, textPrimary, textSecondary, textMuted, snack;
}

const _light = _Palette(
  bg: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  surfaceRaised: Color(0xFFFAFAFA),
  surfaceGray: Color(0xFFEFEFEF),
  border: Color(0xFFDBDBDB),
  divider: Color(0xFFEFEFEF),
  textPrimary: Color(0xFF000000),
  textSecondary: Color(0xFF737373),
  textMuted: Color(0xFFA8A8A8),
  snack: Color(0xFF262626),
);

const _dark = _Palette(
  bg: Color(0xFF0F1115),
  surface: Color(0xFF161920),
  surfaceRaised: Color(0xFF1C1F26),
  surfaceGray: Color(0xFF23272F),
  border: Color(0xFF2E333C),
  divider: Color(0xFF23272F),
  textPrimary: Color(0xFFF2F3F5),
  textSecondary: Color(0xFF9AA0A8),
  textMuted: Color(0xFF6B7280),
  snack: Color(0xFFF2F3F5),
);

/// TT Spot palette. Brand red and ink black never change; the ground and
/// text flip with [AppColors.dark]. Set it before the MaterialApp builds
/// (main.dart does), and everything reads the right set.
abstract final class AppColors {
  static bool dark = false;
  static _Palette get _p => dark ? _dark : _light;

  // Ground
  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surfaceRaised => _p.surfaceRaised;   // input fill
  static Color get surfaceGray => _p.surfaceGray;       // secondary buttons, chips
  static Color get border => _p.border;
  static Color get divider => _p.divider;

  // Text
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;
  static Color get snack => _p.snack;
  /// Text drawn on a [textPrimary] surface (the tab capsule, black chips).
  static Color get onInk => dark ? const Color(0xFF0F1115) : Colors.white;

  // Brand (fixed)
  static const brand = Color(0xFFE00008);            // logo red
  static const brandDeep = Color(0xFFB80006);
  static const ink = Color(0xFF101010);              // logo black

  // Actions
  static const primary = brand;
  static const primaryPressed = brandDeep;
  static const danger = Color(0xFFC4000A);
  static const success = Color(0xFF1DA750);
  /// Highlight surface (points, live pills, vouchers). White text on it.
  static const warnColor = brand;

  static const accent = brand;
  static const storyGradient = LinearGradient(
    colors: [Color(0xFFE00008), Color(0xFF7A0004), Color(0xFF101010)],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );

  // Map (its own night palette, used by MapPalette)
  static const mapBg = Color(0xFF0F1115);
  static const mapSurfaceLight = Color(0xFFFFFFFF);
  static const mapSurface = Color(0xFF1C1F26);
  static const mapText = Color(0xFFF2F3F5);
  static const mapTextSecondary = Color(0xFF9AA0A8);
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

abstract final class AppFonts {
  /// Wordmark only. Everything else uses the platform font, like Instagram.
  static const display = 'BarlowCondensed';
}

abstract final class AppText {
  static TextStyle get wordmark => TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w800,
        fontSize: 46,
        height: 1,
        letterSpacing: -0.5,
        color: AppColors.textPrimary,
      );
  static TextStyle get screenTitle => TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static TextStyle get sectionTitle => TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static TextStyle get link => const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary);
}

abstract final class AppTheme {
  static SystemUiOverlayStyle get systemOverlay => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: AppColors.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: AppColors.dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: AppColors.bg,
        systemNavigationBarIconBrightness: AppColors.dark ? Brightness.light : Brightness.dark,
      );

  /// The theme for whatever [AppColors.dark] is right now.
  static ThemeData get current => _build();

  /// Kept for callers that only ever wanted the light look.
  static ThemeData get light => _build();

  static ThemeData _build() {
    final dark = AppColors.dark;
    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceGray,
      outline: AppColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: (dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
    );

    OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: color),
        );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary)
          .copyWith(
            bodyLarge: TextStyle(fontSize: 15, height: 1.4, color: AppColors.textPrimary),
            bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary),
            bodySmall: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
            titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppText.screenTitle,
        systemOverlayStyle: systemOverlay,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      // Slide-in pages with swipe-from-left-edge to go back, on Android too.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceRaised,
        hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        floatingLabelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        helperStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        focusedBorder: inputBorder(AppColors.textMuted),
        errorBorder: inputBorder(AppColors.danger),
        focusedErrorBorder: inputBorder(AppColors.danger),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      // Gray secondary button, like Instagram's "Edit profile"
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceGray,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor: AppColors.surfaceGray.withValues(alpha: 0.6),
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size.fromHeight(46),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: AppColors.textMuted, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceGray,
        selectedColor: AppColors.textPrimary,
        labelStyle: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: AppColors.onInk, fontWeight: FontWeight.w600, fontSize: 13),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: AppColors.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        contentTextStyle: TextStyle(fontSize: 14.5, height: 1.4, color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 56,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: AppColors.textPrimary, size: 26),
        ),
      ),
      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 0.5, space: 0.5),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.snack,
        contentTextStyle: TextStyle(color: dark ? AppColors.bg : Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textPrimary,
        textColor: AppColors.textPrimary,
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(fontSize: 15, color: AppColors.textPrimary),
      ),
    );
  }
}


/// Colours for the map's bottom sheet, which follows the map: dark at night,
/// white by day. Read with `MapPalette.of(context)`.
class MapPalette extends InheritedWidget {
  const MapPalette({super.key, required this.light, required super.child});
  final bool light;

  Color get surface => light ? Colors.white : AppColors.mapSurface;
  Color get text => light ? const Color(0xFF000000) : AppColors.mapText;
  Color get text2 => light ? const Color(0xFF737373) : AppColors.mapTextSecondary;
  Color get tile => light ? const Color(0xFFEFEFEF) : Colors.white.withValues(alpha: 0.08);
  Color get divider => light ? const Color(0xFFDBDBDB) : Colors.white.withValues(alpha: 0.06);
  Color get handle => light ? const Color(0xFFD0D0D0) : Colors.white.withValues(alpha: 0.28);
  Color get accentBg => light ? AppColors.ink : Colors.white;
  Color get accentFg => light ? Colors.white : Colors.black;
  Color get shadow => light ? const Color(0x22000000) : const Color(0x66000000);

  /// What sheets opened outside the map tree (modal bottom sheets) fall back to.
  static bool defaultLight = true;

  static MapPalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapPalette>() ?? MapPalette(light: defaultLight, child: const SizedBox.shrink());

  @override
  bool updateShouldNotify(MapPalette old) => old.light != light;
}
