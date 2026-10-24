import 'package:flutter/material.dart';

import 'lenz_colors.dart';

/// Legacy colour tokens, kept so un-migrated screens compile.
///
/// Since the Lenz redesign every VALUE here is remapped onto the prototype
/// palette in [LenzColors] (names are unchanged). New code should use
/// [LenzColors] directly. The app is light-only; the `*Dark` constants are
/// retained for API compatibility only.
abstract final class AppColors {
  // Reference Color Scheme (Requested Palette)
  static const Color warmIvory = LenzColors.ivory; // Main background
  static const Color softWarmGray = LenzColors.mint2; // Secondary / soft surface (was warm grey)
  static const Color veryLightWarmGray = LenzColors.paper; // Card background (paper white)
  static const Color deepForestGreen = LenzColors.forest; // Primary dark green
  static const Color nearBlack = LenzColors.ink; // Main text
  static const Color charcoalGray = LenzColors.muted; // Secondary text
  static const Color softGray = LenzColors.subtle; // Muted text
  static const Color coolGray = LenzColors.placeholder; // Outer phone/frame gray
  static const Color pureWhite = LenzColors.paper; // Pure white

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
  static const Color surfaceGlass = Color(0xD1FFFFFF); // white 82%
  static const Color surfaceElevated = veryLightWarmGray;

  // Dark Mode Colors
  static const Color backgroundDark = Color(0xFF0D0D0E);
  static const Color backgroundSecondaryDark = Color(0xFF161618);
  static const Color surfaceDark = Color(0xFF1A1A1C);
  static const Color surfaceGlassDark = Color(0xCC1A1A1C);
  static const Color surfaceElevatedDark = Color(0xFF242428);

  // Borders & Dividers
  static const Color border = LenzColors.line; // forest 9%
  static const Color borderLight = Color(0x0D122F24); // forest 5%
  static const Color borderHighlighted = Color(0x2E122F24);
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
  static const Color accentHover = Color(0xFF112B21);
  static const Color accentSoft = LenzColors.mint2; // Light green pill background
  static const Color accentBorder = Color(0x33122F24);
  static const Color accentDark = LenzColors.leaf; // Slightly brighter for dark contrast
  static const Color accentSoftDark = Color(0x262EA44F);

  // Functional / Status
  static const Color success = LenzColors.ok;
  static const Color successBg = LenzColors.okSoft;
  static const Color warning = LenzColors.warn;
  static const Color warningBg = LenzColors.warnSoft;
  static const Color danger = LenzColors.bad;
  static const Color dangerBg = LenzColors.badSoft;
  static const Color neutralPill = LenzColors.mint2;
  static const Color neutralPillDark = Color(0xFF28282C);

  // Shadows
  static const Color shadow = Color(0x0D122F24);
  static const Color shadowMedium = Color(0x29122F24);
  static const Color shadowDark = Color(0x33000000);

  // Reticle / Viewfinder
  static const Color viewfinderOverlay = Color(0x73000000);
  static const Color viewfinderCorners = Color(0xFFFFFFFF);

  // Button Dark
  static const Color buttonDark = LenzColors.forest;
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
