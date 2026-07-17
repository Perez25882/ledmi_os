import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LedgerMind shared design tokens.
///
/// These colors mirror the Next.js dashboard palette defined in
/// `ledgermindv1-main/app/globals.css`.
class AppTheme {
  // Light mode primitives
  static const Color primary = Color(0xFF008994);
  static const Color primaryForeground = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF161616);
  static const Color card = Color(0xFFFDFDFD);
  static const Color cardForeground = Color(0xFF161616);
  static const Color secondary = Color(0xFFF2F2F2);
  static const Color secondaryForeground = Color(0xFF161616);
  static const Color muted = Color(0xFFF5F5F5);
  static const Color mutedForeground = Color(0xFF717171);
  static const Color accent = Color(0xFFDCF8FA);
  static const Color accentForeground = Color(0xFF161616);
  static const Color destructive = Color(0xFFCC272E);
  static const Color destructiveForeground = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE4E4E4);
  static const Color input = Color(0xFFFFFFFF);
  static const Color ring = Color(0xFF008994);

  // Dark mode primitives
  static const Color darkBackground = Color(0xFF060606);
  static const Color darkForeground = Color(0xFFEEEEEE);
  static const Color darkCard = Color(0xFF121212);
  static const Color darkCardForeground = Color(0xFFEEEEEE);
  static const Color darkPrimary = Color(0xFF00ADBA);
  static const Color darkPrimaryForeground = Color(0xFF030303);
  static const Color darkSecondary = Color(0xFF1B1B1A);
  static const Color darkSecondaryForeground = Color(0xFFEEEEEE);
  static const Color darkMuted = Color(0xFF1B1B1A);
  static const Color darkMutedForeground = Color(0xFF8F8F8F);
  static const Color darkAccent = Color(0xFF002022);
  static const Color darkAccentForeground = Color(0xFFEEEEEE);
  static const Color darkDestructive = Color(0xFF972527);
  static const Color darkDestructiveForeground = Color(0xFFFFB5AB);
  static const Color darkBorder = Color(0xFF1B1B1A);
  static const Color darkInput = Color(0xFF1B1B1A);

  static final TextTheme textTheme = GoogleFonts.ibmPlexSansTextTheme().apply(
    bodyColor: foreground,
    displayColor: foreground,
  );

  static ColorScheme get _lightColorScheme {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: primaryForeground,
      primaryContainer: accent,
      onPrimaryContainer: accentForeground,
      secondary: secondary,
      onSecondary: secondaryForeground,
      secondaryContainer: muted,
      onSecondaryContainer: foreground,
      error: destructive,
      onError: destructiveForeground,
      surface: background,
      onSurface: foreground,
      surfaceContainerHighest: card,
      surfaceContainerHigh: card,
      surfaceContainer: muted,
      surfaceContainerLow: card,
      surfaceContainerLowest: background,
      surfaceDim: Color(0xFFE4E4E4),
      surfaceBright: background,
      outline: border,
      outlineVariant: Color(0xFFF5F5F5),
      shadow: Color(0xFF000000),
      inverseSurface: darkBackground,
      onInverseSurface: darkForeground,
      inversePrimary: darkPrimary,
    );
  }

  static ColorScheme get _darkColorScheme {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: darkPrimary,
      onPrimary: darkPrimaryForeground,
      primaryContainer: darkAccent,
      onPrimaryContainer: darkAccentForeground,
      secondary: darkSecondary,
      onSecondary: darkSecondaryForeground,
      secondaryContainer: darkMuted,
      onSecondaryContainer: darkForeground,
      error: darkDestructive,
      onError: darkDestructiveForeground,
      surface: darkBackground,
      onSurface: darkForeground,
      surfaceContainerHighest: darkCard,
      surfaceContainerHigh: darkCard,
      surfaceContainer: darkMuted,
      surfaceContainerLow: darkCard,
      surfaceContainerLowest: darkBackground,
      surfaceDim: darkBorder,
      surfaceBright: darkCard,
      outline: darkBorder,
      outlineVariant: Color(0xFF1B1B1A),
      shadow: Color(0xFF000000),
      inverseSurface: background,
      onInverseSurface: foreground,
      inversePrimary: primary,
    );
  }

  static ThemeData _buildTheme(Brightness brightness, ColorScheme scheme) {
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surfaceContainerHighest,
      dividerColor: scheme.outline.withValues(alpha: 0.12),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shadowColor: scheme.shadow.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: scheme.surfaceContainerHighest,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? input : darkInput,
        hintStyle: TextStyle(
          color: isLight ? mutedForeground : darkMutedForeground,
          fontSize: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 4,
          shadowColor: scheme.primary.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? foreground : darkForeground,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? background : darkBackground,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static ThemeData get lightTheme => _buildTheme(
        Brightness.light,
        _lightColorScheme,
      );

  static ThemeData get darkTheme => _buildTheme(
        Brightness.dark,
        _darkColorScheme,
      );
}
