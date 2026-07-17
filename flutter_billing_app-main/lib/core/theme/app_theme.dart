import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LedgerMind shared design tokens.
///
/// These colors mirror the Next.js dashboard palette defined in
/// `ledgermindv1-main/app/globals.css`. The primary brand is the cyan/teal
/// defined by `--primary: oklch(0.55 0.15 200)`.
class AppTheme {
  // Primitive brand palette (light mode)
  static const Color primary = Color(0xFF008994);
  static const Color primaryForeground = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF161616);
  static const Color card = Color(0xFFFDFDFD);
  static const Color cardForeground = Color(0xFF161616);
  static const Color popover = Color(0xFFFFFFFF);
  static const Color popoverForeground = Color(0xFF161616);
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
  static const Color darkPopover = Color(0xFF121212);
  static const Color darkPopoverForeground = Color(0xFFEEEEEE);
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
  static const Color darkRing = Color(0xFF008994);

  // Backward-compatible aliases used throughout the existing POS code
  static const Color primaryColor = primary;
  static const Color secondaryColor = secondary;
  static const Color backgroundColor = background;
  static const Color surfaceColor = card;
  static const Color errorColor = destructive;

  static final TextTheme _baseTextTheme = GoogleFonts.ibmPlexSansTextTheme();

  static TextTheme get textTheme {
    return _baseTextTheme.copyWith(
      bodyLarge: GoogleFonts.ibmPlexSans(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: foreground,
      ),
    );
  }

  static ColorScheme get lightColorScheme {
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
      surfaceContainerLow: popover,
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

  static ColorScheme get darkColorScheme {
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
      surfaceContainerLow: darkPopover,
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
    final bg = scheme.surface;
    final fg = scheme.onSurface;
    final surfaceContainer = isLight ? muted : darkMuted;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: scheme.surfaceContainerHighest,
      dividerColor: scheme.outline.withValues(alpha: 0.12),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
      ),
      textTheme: textTheme.apply(
        bodyColor: fg,
        displayColor: fg,
        decorationColor: fg,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
        iconTheme: IconThemeData(color: fg),
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
          fontWeight: FontWeight.normal,
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
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
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: scheme.primary,
        labelStyle: TextStyle(color: fg),
        secondaryLabelStyle: TextStyle(color: scheme.onPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: scheme.surfaceContainerHighest,
        textColor: fg,
        iconColor: fg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedItemColor: scheme.primary,
        unselectedItemColor: isLight ? mutedForeground : darkMutedForeground,
      ),
    );
  }

  static ThemeData get lightTheme => _buildTheme(
        Brightness.light,
        lightColorScheme,
      );

  static ThemeData get darkTheme => _buildTheme(
        Brightness.dark,
        darkColorScheme,
      );
}
