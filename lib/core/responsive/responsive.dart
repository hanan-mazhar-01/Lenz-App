import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Centralized responsive utility system for Lenz.
/// Handles cross-device consistency across small Android phones,
/// standard devices, iPhone SE, iPhone 11-14, iPhone 14-16 Pro (Dynamic Island),
/// and iPhone Pro Max.
class Responsive {
  Responsive._();

  /// Standard reference width (based on modern standard smartphone viewport 390-393pt).
  static const double _baseWidth = 390.0;

  /// Returns total screen width.
  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  /// Returns total screen height.
  static double screenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  /// True for compact/small phones like iPhone SE, small Androids (width < 375 or height < 700).
  static bool isSmallPhone(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width < 375 || size.height < 700;
  }

  /// True for standard phones (iPhone 11-15, standard Android: width 375..414).
  static bool isStandardPhone(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 375 && w <= 414;
  }

  /// True for large phones (iPhone Pro Max, Plus, large Androids: width > 414).
  static bool isLargePhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width > 414;

  /// True if height is constrained (e.g. iPhone SE, keyboard open, landscape).
  static bool isShortScreen(BuildContext context) =>
      MediaQuery.sizeOf(context).height < 720;

  /// Returns top padding (status bar / notch / Dynamic Island: 44-59pt).
  static double topPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).top;

  /// Returns bottom padding (home indicator / navigation bar: 0-34pt).
  static double bottomPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  /// Returns a fractional width (0.0 to 1.0).
  static double width(BuildContext context, double factor) =>
      screenWidth(context) * factor;

  /// Returns a fractional height (0.0 to 1.0).
  static double height(BuildContext context, double factor) =>
      screenHeight(context) * factor;

  /// Responsive horizontal screen margin:
  /// Compact phones get 16, standard get 20, large phones get 24.
  static double horizontalPadding(BuildContext context) {
    final w = screenWidth(context);
    if (w < 375) return 16.0;
    if (w > 420) return 24.0;
    return 20.0;
  }

  /// Scales a font size gently relative to reference width, clamped within safe limits.
  /// Prevents text from becoming tiny on iPhone Pro/Pro Max (which have high PPI but 393/430pt width)
  /// or overflowing on small phones.
  static double fontSize(
    BuildContext context,
    double baseSize, {
    double? minSize,
    double? maxSize,
  }) {
    final w = screenWidth(context);
    // Gentle scaling factor: only 35% of the width variation is applied to font size
    // to preserve readability without extreme shrinkage or enlargement.
    final scale = 1.0 + ((w - _baseWidth) / _baseWidth) * 0.35;
    final calculated = baseSize * scale;

    final minimum = minSize ?? (baseSize * 0.88);
    final maximum = maxSize ?? (baseSize * 1.18);

    return calculated.clamp(minimum, maximum);
  }

  /// Responsive vertical spacing that shrinks gracefully on shorter screens.
  static double verticalSpacing(BuildContext context, double baseSpacing) {
    final h = screenHeight(context);
    if (h < 700) {
      return math.max(baseSpacing * 0.7, 4.0);
    } else if (h < 780) {
      return math.max(baseSpacing * 0.85, 6.0);
    }
    return baseSpacing;
  }

  /// Clamps a value between lower and upper bounds.
  static double clamp(double value, double min, double max) =>
      value.clamp(min, max);
}

/// Convenience extensions on [BuildContext] for responsive access.
extension ResponsiveContext on BuildContext {
  double get screenWidth => Responsive.screenWidth(this);
  double get screenHeight => Responsive.screenHeight(this);
  bool get isSmallPhone => Responsive.isSmallPhone(this);
  bool get isLargePhone => Responsive.isLargePhone(this);
  bool get isShortScreen => Responsive.isShortScreen(this);
  double get topSafeArea => Responsive.topPadding(this);
  double get bottomSafeArea => Responsive.bottomPadding(this);
  double get responsiveHorizontalPadding => Responsive.horizontalPadding(this);

  double responsiveWidth(double factor) => Responsive.width(this, factor);
  double responsiveHeight(double factor) => Responsive.height(this, factor);
  double responsiveFontSize(double baseSize, {double? min, double? max}) =>
      Responsive.fontSize(this, baseSize, minSize: min, maxSize: max);
  double responsiveVerticalSpacing(double base) =>
      Responsive.verticalSpacing(this, base);
}
