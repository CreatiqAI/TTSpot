import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TT Spot palette: white ground, near-black text, brand red for actions and
/// highlights (sampled from the logo). Flat, thin gray borders.
abstract final class AppColors {
  // Ground
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceRaised = Color(0xFFFAFAFA);   // input fill
  static const surfaceGray = Color(0xFFEFEFEF);     // secondary buttons, chips
  static const border = Color(0xFFDBDBDB);
  static const divider = Color(0xFFEFEFEF);

  // Text
  static const textPrimary = Color(0xFF000000);
  static const textSecondary = Color(0xFF737373);
  static const textMuted = Color(0xFFA8A8A8);

  // Brand
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

  // Map screen stays dark (matches Instagram's map)
  static const mapBg = Color(0xFF0F1115);
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
  static const wordmark = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w800,
    fontSize: 46,
    height: 1,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );
  static const screenTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const sectionTitle = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const link = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary);
}

abstract final class AppTheme {
  static const systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
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
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.black.withValues(alpha: 0.04),
    );

    OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: color),
        );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary)
          .copyWith(
            bodyLarge: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.textPrimary),
            bodyMedium: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary),
            bodySmall: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
            titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppText.screenTitle,
        systemOverlayStyle: systemOverlay,
      ),
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
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        helperStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
          side: const BorderSide(color: AppColors.border),
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
        side: const BorderSide(color: AppColors.textMuted, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceGray,
        selectedColor: AppColors.textPrimary,
        labelStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: AppColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 56,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => const IconThemeData(color: AppColors.textPrimary, size: 26),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 0.5, space: 0.5),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF262626),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textPrimary,
        textColor: AppColors.textPrimary,
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(fontSize: 15, color: AppColors.textPrimary),
      ),
    );
  }
}
