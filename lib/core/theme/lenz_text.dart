import 'package:flutter/painting.dart';

import 'lenz_colors.dart';

/// Type scale of the prototype (`app.css`). Font: Nunito 600/700/800/900.
///
/// `letter-spacing` values in the CSS are in `em`; they are converted to
/// logical pixels here (e.g. `-.035em` at 32px = `-1.12`).
abstract final class LenzText {
  static const String family = 'Nunito';

  static const TextStyle _base = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontWeight: FontWeight.w800,
  );

  /// `.display` 32 / 900 / -.035em / 1.04.
  static const TextStyle display = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 32,
    fontWeight: FontWeight.w900,
    height: 1.04,
    letterSpacing: -1.12,
  );

  /// `.hero h3` 25 / 900 / -.03em / 1.05.
  static const TextStyle hero = TextStyle(
    fontFamily: family,
    color: Color(0xFFFFFFFF),
    fontSize: 25,
    fontWeight: FontWeight.w900,
    height: 1.05,
    letterSpacing: -.75,
  );

  /// `.hero p` 13.5 / 700 on dark green.
  static const TextStyle heroSub = TextStyle(
    fontFamily: family,
    color: LenzColors.onHeroMuted,
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );

  /// `.title` 22 / 900 / -.025em / 1.1.
  static const TextStyle title = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 22,
    fontWeight: FontWeight.w900,
    height: 1.1,
    letterSpacing: -.55,
  );

  /// `.sectionhead b` and `.topbar h2` 19 / 900 / -.02em.
  static const TextStyle section = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 19,
    fontWeight: FontWeight.w900,
    letterSpacing: -.38,
  );

  /// `.sub` 14.5 / 700 muted / 1.45.
  static const TextStyle sub = TextStyle(
    fontFamily: family,
    color: LenzColors.muted,
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    height: 1.45,
  );

  /// `.cap` 12.5 / 800 muted.
  static const TextStyle cap = TextStyle(
    fontFamily: family,
    color: LenzColors.muted,
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
  );

  /// `.tiny` 11.5 / 700 muted / 1.4 (centre aligned in CSS).
  static const TextStyle tiny = TextStyle(
    fontFamily: family,
    color: LenzColors.muted,
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );

  /// `.btn` 16.5 / 900 / -.01em (white).
  static const TextStyle button = TextStyle(
    fontFamily: family,
    color: Color(0xFFFFFFFF),
    fontSize: 16.5,
    fontWeight: FontWeight.w900,
    letterSpacing: -.165,
  );

  /// `.btn.sm` 14.5 / 900.
  static const TextStyle buttonSm = TextStyle(
    fontFamily: family,
    color: Color(0xFFFFFFFF),
    fontSize: 14.5,
    fontWeight: FontWeight.w900,
    letterSpacing: -.145,
  );

  /// `.chip` 13.5 / 800.
  static const TextStyle chip = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 13.5,
    fontWeight: FontWeight.w800,
  );

  /// `.pill` 12 / 900.
  static const TextStyle pill = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 12,
    fontWeight: FontWeight.w900,
  );

  /// `.divider` 13 / 800 muted.
  static const TextStyle divider = TextStyle(
    fontFamily: family,
    color: LenzColors.muted,
    fontSize: 13,
    fontWeight: FontWeight.w800,
  );

  /// `.sectionhead button` 13.5 / 800 forest2.
  static const TextStyle link = TextStyle(
    fontFamily: family,
    color: LenzColors.forest2,
    fontSize: 13.5,
    fontWeight: FontWeight.w800,
  );

  /// `.stat b` 26 / 900 / -.03em / 1.
  static const TextStyle stat = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 26,
    fontWeight: FontWeight.w900,
    height: 1,
    letterSpacing: -.78,
  );

  /// `.stat span` 12 / 800 muted.
  static const TextStyle statLabel = TextStyle(
    fontFamily: family,
    color: LenzColors.muted,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  /// `.item b` 15.5 / 900 / -.01em.
  static const TextStyle item = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 15.5,
    fontWeight: FontWeight.w900,
    letterSpacing: -.155,
  );

  /// `.item small` 12.5 / 700 muted.
  static const TextStyle itemSub = TextStyle(
    fontFamily: family,
    color: LenzColors.muted,
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
  );

  /// `.setting` 15.5 / 800.
  static const TextStyle setting = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 15.5,
    fontWeight: FontWeight.w800,
  );

  /// `.setting small` 12 / 700 muted.
  static const TextStyle settingSub = TextStyle(
    fontFamily: family,
    color: LenzColors.muted,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  /// `.field input` 16 / 800.
  static const TextStyle field = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );

  /// `.field input::placeholder` 16 / 700 `#9AA39E`.
  static const TextStyle placeholder = TextStyle(
    fontFamily: family,
    color: LenzColors.placeholder,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  /// `.seg button` 14.5 / 900.
  static const TextStyle segment = TextStyle(
    fontFamily: family,
    color: LenzColors.muted,
    fontSize: 14.5,
    fontWeight: FontWeight.w900,
  );

  /// `.tab` 11 / 800.
  static const TextStyle tab = TextStyle(
    fontFamily: family,
    color: LenzColors.subtle,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// `.jl span` 10.5 / 800 muted.
  static const TextStyle journeyLabel = TextStyle(
    fontFamily: family,
    color: LenzColors.muted,
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
  );

  /// `.bubble` 13.5 / 800 / 1.3.
  static const TextStyle bubble = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 13.5,
    fontWeight: FontWeight.w800,
    height: 1.3,
  );

  /// `.bullet` 14.5 / 700 / 1.4.
  static const TextStyle bullet = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );

  /// `.toast` 13.5 / 800 white.
  static const TextStyle toast = TextStyle(
    fontFamily: family,
    color: Color(0xFFFFFFFF),
    fontSize: 13.5,
    fontWeight: FontWeight.w800,
  );

  /// `.social` 15.5 / 900.
  static const TextStyle social = TextStyle(
    fontFamily: family,
    color: LenzColors.ink,
    fontSize: 15.5,
    fontWeight: FontWeight.w900,
  );

  /// Generic helper: Nunito at [size] / [weight], ink by default.
  static TextStyle of(
    double size, {
    FontWeight weight = FontWeight.w800,
    Color color = LenzColors.ink,
    double? height,
    double letterSpacingEm = 0,
  }) =>
      _base.copyWith(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacingEm * size,
      );
}
