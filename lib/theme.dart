// lib/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Dracula-ish palette
  static const _purple = Color(0xFFBD93F9);
  static const _pink = Color(0xFFFF79C6);
  static const _cyan = Color(0xFF8BE9FD);
  static const _red = Color(0xFFFF5555);

  static const _bg = Color(0xFF282A36);
  static const _surface = Color(0xFF2E3140);
  static const _surfaceVariant = Color(0xFF44475A);
  static const _fg = Color(0xFFF8F8F2);
  static const _outline = Color(0xFF6272A4);

  static ThemeData get dark => _buildDark();

  static ThemeData _buildDark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _purple,
      onPrimary: Colors.black,
      primaryContainer: Color(0xFF7F62C8),
      onPrimaryContainer: _fg,
      secondary: _pink,
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFFBD5A95),
      onSecondaryContainer: _fg,
      tertiary: _cyan,
      onTertiary: Colors.black,
      tertiaryContainer: Color(0xFF63CFE6),
      onTertiaryContainer: Colors.black,
      error: _red,
      onError: Colors.black,
      errorContainer: Color(0xFFB23B3B),
      onErrorContainer: _fg,
      surface: _surface,
      onSurface: _fg,
      surfaceContainerHighest: _surfaceVariant,
      onSurfaceVariant: Color(0xFFDBDCE6),
      outline: _outline,
      outlineVariant: _surfaceVariant,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: _fg,
      onInverseSurface: _bg,
      inversePrimary: _pink,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
    );

    // Inter Tight everywhere
    final inter = GoogleFonts.interTightTextTheme(base.textTheme);

    // Push “Black” feel for display/title; keep body readable
    final t = inter.copyWith(
      displayLarge: inter.displayLarge?.copyWith(fontWeight: FontWeight.w900),
      displayMedium: inter.displayMedium?.copyWith(fontWeight: FontWeight.w900),
      displaySmall: inter.displaySmall?.copyWith(fontWeight: FontWeight.w900),
      headlineLarge: inter.headlineLarge?.copyWith(fontWeight: FontWeight.w900),
      headlineMedium: inter.headlineMedium?.copyWith(
        fontWeight: FontWeight.w900,
      ),
      headlineSmall: inter.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
      titleLarge: inter.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: inter.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: inter.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: inter.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: inter.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: inter.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: inter.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      labelMedium: inter.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      labelSmall: inter.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    );

    return base.copyWith(
      textTheme: t,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: t.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: _rounded(scheme),
        enabledBorder: _rounded(scheme),
        focusedBorder: _rounded(scheme, focused: true),
        errorBorder: _rounded(scheme, error: true),
        focusedErrorBorder: _rounded(scheme, focused: true, error: true),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(color: scheme.onSurface),
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.secondaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
    );
  }

  static OutlineInputBorder _rounded(
    ColorScheme scheme, {
    bool focused = false,
    bool error = false,
  }) {
    final color = error
        ? scheme.error
        : (focused ? scheme.primary : scheme.outlineVariant);
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: focused ? 1.6 : 1.0),
    );
  }
}
