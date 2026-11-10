import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brote Design System: Terra ("Rooted Warmth")
/// Faithful translation of Stitch Project 9270566147008718336 tokens.
class BroteTheme {
  // Brand Primary: Forest Green
  static const Color primary = Color(0xFF4A7C59);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF78A886);
  static const Color onPrimaryContainer = Color(0xFF002110);
  static const Color primaryFixed = Color(0xFFC8E8D0);
  static const Color primaryFixedDim = Color(0xFF8ECF9E);

  // Brand Secondary: Warm Earthy Neutral
  static const Color secondary = Color(0xFF6B6358);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFF0E8DB);
  static const Color onSecondaryContainer = Color(0xFF5E5548);
  static const Color secondaryFixed = Color(0xFFF0E8DB);

  // Brand Tertiary: Warm Amber / Sunlight Accent
  static const Color tertiary = Color(0xFF705C30);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFC4A66A);
  static const Color onTertiaryContainer = Color(0xFF554020);

  // Surface & Background: Warm Cream (Never sterile white)
  static const Color background = Color(0xFFFAF6F0);
  static const Color onBackground = Color(0xFF2E3230);
  static const Color surface = Color(0xFFFAF6F0);
  static const Color onSurface = Color(0xFF2E3230);
  static const Color onSurfaceVariant = Color(0xFF4A4E4A);

  // Tonal Elevation Layers
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF5F1EA);
  static const Color surfaceContainer = Color(0xFFF0ECE4);
  static const Color surfaceContainerHigh = Color(0xFFEAE6DE);
  static const Color surfaceContainerHighest = Color(0xFFE4E0D8);
  static const Color surfaceDim = Color(0xFFDBD7CF);
  static const Color surfaceBright = Color(0xFFFAF6F0);

  // Borders & Dividers
  static const Color outline = Color(0xFF74796E);
  static const Color outlineVariant = Color(0xFFC4C8BC);

  // Semantic Errors
  static const Color error = Color(0xFFB83230);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD8);
  static const Color onErrorContainer = Color(0xFF690005);

  /// Light ColorScheme
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    secondary: secondary,
    onSecondary: onSecondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
    tertiary: tertiary,
    onTertiary: onTertiary,
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer,
    error: error,
    onError: onError,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
    shadow: Color(0x0F2E3230),
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
  );

  /// Dark ColorScheme
  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8ECF9E),
    onPrimary: Color(0xFF003919),
    primaryContainer: Color(0xFF326341),
    onPrimaryContainer: Color(0xFFD8F0DE),
    secondary: Color(0xFFD4CCBF),
    onSecondary: Color(0xFF39322A),
    secondaryContainer: Color(0xFF4A4538),
    onSecondaryContainer: Color(0xFFF0E8DB),
    tertiary: Color(0xFFDCC48E),
    onTertiary: Color(0xFF3F3006),
    tertiaryContainer: Color(0xFF554020),
    onTertiaryContainer: Color(0xFFF8E0A8),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF161820),
    onSurface: Color(0xFFE4E0D8),
    onSurfaceVariant: Color(0xFFC4C8BC),
    outline: Color(0xFF8E9287),
    outlineVariant: Color(0xFF464554),
    shadow: Color(0x33000000),
    surfaceContainerLowest: Color(0xFF0E0F14),
    surfaceContainerLow: Color(0xFF1B1D25),
    surfaceContainer: Color(0xFF22242D),
    surfaceContainerHigh: Color(0xFF292C36),
    surfaceContainerHighest: Color(0xFF333742),
  );

  /// Custom TextTheme using Literata for headlines and Nunito Sans for body
  static TextTheme createTextTheme(BuildContext context, Color textColor) {
    final baseTextTheme = Theme.of(context).textTheme;

    return baseTextTheme.copyWith(
      displayLarge: GoogleFonts.literata(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: textColor,
        letterSpacing: -0.5,
      ),
      displayMedium: GoogleFonts.literata(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textColor,
        letterSpacing: -0.5,
      ),
      headlineLarge: GoogleFonts.literata(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textColor,
        letterSpacing: -0.3,
      ),
      headlineMedium: GoogleFonts.literata(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: textColor,
        letterSpacing: -0.2,
      ),
      headlineSmall: GoogleFonts.literata(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleLarge: GoogleFonts.literata(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleMedium: GoogleFonts.nunitoSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      titleSmall: GoogleFonts.nunitoSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      bodyLarge: GoogleFonts.nunitoSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textColor,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.nunitoSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textColor,
        height: 1.45,
      ),
      bodySmall: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textColor.withValues(alpha: 0.75),
      ),
      labelLarge: GoogleFonts.nunitoSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      labelMedium: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      labelSmall: GoogleFonts.nunitoSans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: textColor.withValues(alpha: 0.7),
      ),
    );
  }

  /// ThemeData for Light Mode
  static ThemeData lightTheme(BuildContext context) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: lightColorScheme,
      scaffoldBackgroundColor: surface,
      textTheme: createTextTheme(context, onSurface),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: onSurface),
      ),
      cardTheme: CardThemeData(
        color: surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: outlineVariant, width: 0.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: 0.95),
        elevation: 2,
        indicatorColor: primaryFixed,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.nunitoSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: primary,
            );
          }
          return GoogleFonts.nunitoSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary);
          }
          return const IconThemeData(color: onSurfaceVariant);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outlineVariant, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        hintStyle: GoogleFonts.nunitoSans(color: onSurfaceVariant.withValues(alpha: 0.7), fontSize: 14),
      ),
    );
  }

  /// ThemeData for Dark Mode
  static ThemeData darkTheme(BuildContext context) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: darkColorScheme,
      scaffoldBackgroundColor: const Color(0xFF161820),
      textTheme: createTextTheme(context, const Color(0xFFE4E0D8)),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF161820),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Color(0xFFE4E0D8)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF22242D),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF464554), width: 0.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF161820).withValues(alpha: 0.95),
        elevation: 2,
        indicatorColor: const Color(0xFF326341),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.nunitoSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8ECF9E),
            );
          }
          return GoogleFonts.nunitoSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFFC4C8BC),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Color(0xFF8ECF9E));
          }
          return const IconThemeData(color: Color(0xFFC4C8BC));
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF8ECF9E),
          foregroundColor: const Color(0xFF003919),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF8ECF9E),
          side: const BorderSide(color: Color(0xFF8ECF9E), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF22242D),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF464554), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF464554), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF8ECF9E), width: 2),
        ),
        hintStyle: GoogleFonts.nunitoSans(color: const Color(0xFFC4C8BC).withValues(alpha: 0.7), fontSize: 14),
      ),
    );
  }
}
