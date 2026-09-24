import 'package:flutter/material.dart';

/// Central luxury theme color tokens supporting both Light and Dark modes.
/// Dominant visual system: Off-white / Pure Black & Graphite base with selective mint/emerald accent.
abstract final class AppColors {
  // Reference Color Scheme (Requested Palette)
  static const Color warmIvory = Color(0xFFFCF8F6); // Main background
  static const Color softWarmGray = Color(0xFFF7F3F1); // Secondary background
  static const Color veryLightWarmGray = Color(0xFFF1EDEB); // Card background
  static const Color deepForestGreen = Color(0xFF122F24); // Primary dark green
  static const Color nearBlack = Color(0xFF1F2023); // Main text
  static const Color charcoalGray = Color(0xFF5F6264); // Secondary text
  static const Color softGray = Color(0xFF8A8D91); // Muted text
  static const Color coolGray = Color(0xFF9EA3AE); // Outer phone/frame gray
  static const Color pureWhite = Color(0xFFFFFFFF); // Pure white

  // Palette Aliases matching specification
  static const Color mainBackground = warmIvory;
  static const Color secondaryBackground = softWarmGray;
  static const Color cardBackground = veryLightWarmGray;
  static const Color primaryDarkGreen = deepForestGreen;
  static const Color mainText = nearBlack;
  static const Color mutedText = softGray;
  static const Color outerFrameGray = coolGray;
  static const Color white = pureWhite;

  // Light Mode Colors
  static const Color background = warmIvory;
  static const Color backgroundSecondary = softWarmGray;
  static const Color surface = veryLightWarmGray; // Card background
  static const Color surfaceGlass = Color(0xCCF1EDEB); // 80% opacity
  static const Color surfaceElevated = veryLightWarmGray;

  // Dark Mode Colors
  static const Color backgroundDark = Color(0xFF0D0D0E);
  static const Color backgroundSecondaryDark = Color(0xFF161618);
  static const Color surfaceDark = Color(0xFF1A1A1C);
  static const Color surfaceGlassDark = Color(0xCC1A1A1C);
  static const Color surfaceElevatedDark = Color(0xFF242428);

  // Borders & Dividers
  static const Color border = Color(0x0F000000); // 6% black
  static const Color borderLight = Color(0x08000000); // 3% black
  static const Color borderHighlighted = Color(0x20122F24);
  static const Color borderDark = Color(0x1FFFFFFF); // 12% white
  static const Color borderLightDark = Color(0x0FFFFFFF);

  // Typography
  static const Color textPrimary = nearBlack;
  static const Color textSecondary = charcoalGray;
  static const Color textTertiary = softGray;
  static const Color textInverse = pureWhite;

  static const Color textPrimaryDark = Color(0xFFF5F5F7);
  static const Color textSecondaryDark = Color(0xFF98989F);
  static const Color textTertiaryDark = Color(0xFF636366);

  // Brand Accents - Selective Mint / Emerald / Deep Forest Green
  static const Color accent = deepForestGreen; // Deep Forest Green from reference CTAs
  static const Color accentHover = Color(0xFF0C2018);
  static const Color accentSoft = Color(0x1A122F24); // Light green pill background
  static const Color accentBorder = Color(0x33122F24);
  static const Color accentDark = Color(0xFF2EA44F); // Slightly brighter for dark contrast
  static const Color accentSoftDark = Color(0x262EA44F);

  // Functional / Status
  static const Color success = Color(0xFF2EA44F);
  static const Color successBg = Color(0x142EA44F);
  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0x14D97706);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerBg = Color(0x14DC2626);
  static const Color neutralPill = Color(0xFFF2F2F0);
  static const Color neutralPillDark = Color(0xFF28282C);

  // Shadows
  static const Color shadow = Color(0x0A000000);
  static const Color shadowMedium = Color(0x14000000);
  static const Color shadowDark = Color(0x33000000);

  // Reticle / Viewfinder
  static const Color viewfinderOverlay = Color(0x73000000);
  static const Color viewfinderCorners = Color(0xFFFFFFFF);

  // Button Dark
  static const Color buttonDark = Color(0xFF1C1C1E);
  static const Color buttonDarkInverse = Color(0xFFFFFFFF);

  // Helper getters for dynamic context resolution
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color bg(BuildContext context) =>
      isDark(context) ? backgroundDark : background;

  static Color backgroundOf(BuildContext context) => bg(context);

  static Color cardSurface(BuildContext context) =>
      isDark(context) ? surfaceDark : surface;

  static Color cardSurfaceOf(BuildContext context) => cardSurface(context);

  static Color text(BuildContext context) =>
      isDark(context) ? textPrimaryDark : textPrimary;

  static Color textPrimaryOf(BuildContext context) => text(context);

  static Color secondaryText(BuildContext context) =>
      isDark(context) ? textSecondaryDark : textSecondary;

  static Color textSecondaryOf(BuildContext context) => secondaryText(context);

  static Color cardBorder(BuildContext context) =>
      isDark(context) ? borderDark : border;

  static Color borderOf(BuildContext context) => cardBorder(context);

  static Color pill(BuildContext context) =>
      isDark(context) ? neutralPillDark : neutralPill;

  static Color neutralPillOf(BuildContext context) => pill(context);

  static Color brandAccent(BuildContext context) =>
      isDark(context) ? accentDark : accent;

  static Color accentOf(BuildContext context) => brandAccent(context);

  static Color textTertiaryOf(BuildContext context) =>
      isDark(context) ? textTertiaryDark : textTertiary;

  static Color surfaceOf(BuildContext context) => cardSurface(context);

  static Color accentSoftOf(BuildContext context) =>
      isDark(context) ? accentSoftDark : accentSoft;

  static Color backgroundSecondaryOf(BuildContext context) =>
      isDark(context) ? backgroundSecondaryDark : backgroundSecondary;
}
