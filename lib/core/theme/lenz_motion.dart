import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Curves and durations of the Lenz prototype (`--spring`, `--ease`,
/// `transition()` in core.js, the keyframes of app.css).
abstract final class LenzMotion {
  /// `--spring` = `cubic-bezier(.34,1.56,.64,1)`: presses, pops, thumbs.
  static const Curve spring = Cubic(.34, 1.56, .64, 1);

  /// `--ease` = `cubic-bezier(.2,.8,.2,1)`: entrances, rings, meters.
  static const Curve ease = Cubic(.2, .8, .2, 1);

  /// Route transitions `cubic-bezier(.2,.85,.2,1)`.
  static const Curve route = Cubic(.2, .85, .2, 1);

  /// Sheet slide-up `cubic-bezier(.2,.9,.2,1)`.
  static const Curve sheetIn = Cubic(.2, .9, .2, 1);

  /// Sheet slide-down `cubic-bezier(.5,0,.8,.4)`.
  static const Curve sheetOut = Cubic(.5, 0, .8, .4);

  /// CSS `ease-out` (`cubic-bezier(0,0,.58,1)`), used by the pulse rings.
  static const Curve cssEaseOut = Cubic(0, 0, .58, 1);

  /// `1 - (1 - t)^3`, the ease of `countUp()`.
  static const Curve countUp = _PowerOut(3);

  // ---- durations --------------------------------------------------------
  static const Duration press = Duration(milliseconds: 250);
  static const Duration pressIcon = Duration(milliseconds: 200);
  static const Duration chip = Duration(milliseconds: 250);
  static const Duration field = Duration(milliseconds: 250);
  static const Duration segThumb = Duration(milliseconds: 450);
  static const Duration switchThumb = Duration(milliseconds: 350);
  static const Duration switchTrack = Duration(milliseconds: 300);
  static const Duration check = Duration(milliseconds: 300);
  static const Duration rise = Duration(milliseconds: 700);
  static const Duration riseStep = Duration(milliseconds: 55);
  static const Duration riseDelay = Duration(milliseconds: 120);
  static const Duration ring = Duration(milliseconds: 1400);
  static const Duration ringDelay = Duration(milliseconds: 300);
  static const Duration meter = Duration(milliseconds: 1200);
  static const Duration meterDelay = Duration(milliseconds: 350);
  static const Duration count = Duration(milliseconds: 1200);
  static const Duration journey = Duration(milliseconds: 900);
  static const Duration journeyDelay = Duration(milliseconds: 250);
  static const Duration pulse = Duration(milliseconds: 2000);
  static const Duration fabPulse = Duration(milliseconds: 2400);
  static const Duration tabBarToggle = Duration(milliseconds: 500);
  static const Duration tabPop = Duration(milliseconds: 450);
  static const Duration tabIcon = Duration(milliseconds: 350);
  static const Duration toast = Duration(milliseconds: 2600);
  static const Duration sheetIn520 = Duration(milliseconds: 520);
  static const Duration sheetOut380 = Duration(milliseconds: 380);
  static const Duration routeForward = Duration(milliseconds: 560);
  static const Duration routeModalUp = Duration(milliseconds: 640);
  static const Duration routeModalDown = Duration(milliseconds: 560);
  static const Duration routeZoom = Duration(milliseconds: 700);
  static const Duration routeFade = Duration(milliseconds: 420);

  /// True when the platform asks to reduce motion
  /// (`MediaQuery.disableAnimations`).
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Scales a distance/amplitude down to ~30% for reduced motion.
  static double amp(BuildContext context, double value) =>
      reduced(context) ? value * .3 : value;
}

class _PowerOut extends Curve {
  const _PowerOut(this.power);
  final double power;

  @override
  double transformInternal(double t) => 1 - math.pow(1 - t, power).toDouble();
}

/// CSS keyframe `pop`: `0% scale .6 / opacity 0, 70% scale 1.06, 100% scale 1 /
/// opacity 1`, with [LenzMotion.spring] easing between keyframes.
class LenzPopCurve {
  const LenzPopCurve._();

  /// Scale for progress [t] (0..1).
  static double scale(double t) {
    if (t <= 0) return .6;
    if (t >= 1) return 1;
    if (t < .7) {
      return .6 + (1.06 - .6) * LenzMotion.spring.transform(t / .7);
    }
    return 1.06 + (1 - 1.06) * LenzMotion.spring.transform((t - .7) / .3);
  }

  /// Opacity for progress [t]: the keyframes only define it at 0% and 100%, so
  /// it eases (with the spring, clamped to 0..1) over the whole duration.
  static double opacity(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return LenzMotion.spring.transform(t).clamp(0.0, 1.0);
  }
}
