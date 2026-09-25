import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography definitions matching Apple's Human Interface Guidelines (SF Pro aesthetic).
///
/// Neither platform bundles a custom font, so text renders in each OS's
/// system default: Roboto on Android, SF Pro on iOS. SF Pro has a visibly
/// smaller x-height than Roboto at the same nominal [fontSize], which reads
/// as "too small" on iOS even though the box model size is identical. Sizes
/// below are nudged up slightly on iOS via [_size] so both platforms read as
/// the same perceived size, without changing Android at all.
abstract final class AppTypography {
  static double _size(double base) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return base;
    return base + (base * 0.07).clamp(0.5, 2.0);
  }

  static TextStyle get displayLarge => TextStyle(
    fontSize: _size(30),
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    color: AppColors.textPrimary,
    height: 1.18,
  );

  static TextStyle get displayMedium => TextStyle(
    fontSize: _size(24),
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
    height: 1.22,
  );

  static TextStyle get titleLarge => TextStyle(
    fontSize: _size(20),
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static TextStyle get titleMedium => TextStyle(
    fontSize: _size(17),
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static TextStyle get bodyLarge => TextStyle(
    fontSize: _size(15),
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get bodyMedium => TextStyle(
    fontSize: _size(14),
    fontWeight: FontWeight.w400,
    letterSpacing: -0.15,
    color: AppColors.textSecondary,
    height: 1.42,
  );

  static TextStyle get callout => TextStyle(
    fontSize: _size(13),
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    color: AppColors.textSecondary,
    height: 1.35,
  );

  static TextStyle get caption => TextStyle(
    fontSize: _size(12),
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textTertiary,
    height: 1.3,
  );

  static TextStyle get captionMedium => TextStyle(
    fontSize: _size(12),
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static TextStyle get badge => TextStyle(
    fontSize: _size(11),
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.2,
  );

  static TextStyle get scoreNumber => TextStyle(
    fontSize: _size(40),
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    color: AppColors.textPrimary,
    height: 1.0,
  );
}

