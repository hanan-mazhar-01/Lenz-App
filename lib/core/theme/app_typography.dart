import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'lenz_text.dart';

/// Legacy typography tokens, kept so un-migrated screens compile.
///
/// Every style is now Nunito (600/700/800/900) mapped onto the closest style
/// of the Lenz type scale ([LenzText]). New code should use [LenzText].
abstract final class AppTypography {
  /// 32 / 900 / -.035em (prototype `.display`).
  static TextStyle get displayLarge => LenzText.display.copyWith(
        color: AppColors.textPrimary,
      );

  /// 25 / 900 / -.03em (prototype `.hero h3`).
  static TextStyle get displayMedium => LenzText.hero.copyWith(
        color: AppColors.textPrimary,
      );

  /// 22 / 900 / -.025em (prototype `.title`).
  static TextStyle get titleLarge => LenzText.title.copyWith(
        color: AppColors.textPrimary,
      );

  /// 17 / 900 (between `.item b` 15.5 and `.topbar h2` 19).
  static TextStyle get titleMedium => LenzText.of(
        17,
        weight: FontWeight.w900,
        color: AppColors.textPrimary,
        height: 1.25,
        letterSpacingEm: -.015,
      );

  /// 15.5 / 800 (prototype `.setting`).
  static TextStyle get bodyLarge => LenzText.setting.copyWith(
        color: AppColors.textPrimary,
        height: 1.4,
      );

  /// 14.5 / 700 muted (prototype `.sub`).
  static TextStyle get bodyMedium => LenzText.sub.copyWith(
        color: AppColors.textSecondary,
      );

  /// 13.5 / 800 muted.
  static TextStyle get callout => LenzText.of(
        13.5,
        color: AppColors.textSecondary,
        height: 1.35,
      );

  /// 12.5 / 700 subtle (prototype `.cap`).
  static TextStyle get caption => LenzText.of(
        12.5,
        weight: FontWeight.w700,
        color: AppColors.textTertiary,
        height: 1.3,
      );

  /// 12.5 / 800 ink.
  static TextStyle get captionMedium => LenzText.of(
        12.5,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  /// 12 / 900 (prototype `.pill`).
  static TextStyle get badge => const TextStyle(
        fontFamily: LenzText.family,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        height: 1.2,
      );

  /// 40 / 900 / -.03em for big numbers.
  static TextStyle get scoreNumber => LenzText.of(
        40,
        weight: FontWeight.w900,
        color: AppColors.textPrimary,
        height: 1.0,
        letterSpacingEm: -.03,
      );
}
