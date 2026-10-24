import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import 'lenz_animated_value.dart';

/// The prototype's `ringSVG()`: a progress ring whose stroke animates from
/// empty to [value] (`stroke-dashoffset` 1.4s `cubic-bezier(.2,.8,.2,1)`,
/// starting 300ms after mount), round caps, starting at 12 o'clock.
///
/// [child] is centred inside (e.g. an [AnimatedCount] plus a caption).
class LenzRing extends StatelessWidget {
  const LenzRing({
    super.key,
    required this.value,
    this.size = 104,
    this.strokeWidth = 10,
    this.color = LenzColors.leaf,
    this.trackColor = LenzColors.ringTrack,
    this.child,
    this.duration = LenzMotion.ring,
    this.delay = LenzMotion.ringDelay,
    this.animate = true,
  });

  /// Progress 0..1.
  final double value;
  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;
  final Widget? child;
  final Duration duration;
  final Duration delay;

  /// When false the ring is drawn at [value] immediately.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    return LenzAnimatedDouble(
      value: target,
      initialValue: 0,
      duration: duration,
      delay: delay,
      curve: LenzMotion.ease,
      animate: animate,
      builder: (context, v) {
        return SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: LenzRingPainter(
              progress: v,
              color: color,
              trackColor: trackColor,
              strokeWidth: strokeWidth,
            ),
            child: child == null ? null : Center(child: child),
          ),
        );
      },
    );
  }
}

/// Painter of [LenzRing] (public so tests can read the drawn progress).
class LenzRingPainter extends CustomPainter {
  const LenzRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (math.min(size.width, size.height) - strokeWidth) / 2;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, base..color = trackColor);
    if (progress > 0.0005) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        base..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(LenzRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}

/// The prototype's `.meter`: 10px bar on a faint track whose gradient fill
/// grows to [value] (1.2s `cubic-bezier(.2,.8,.2,1)`, 350ms after mount).
class LenzMeter extends StatelessWidget {
  const LenzMeter({
    super.key,
    required this.value,
    this.gradient = LenzGradients.meter,
    this.height = 10,
    this.duration = LenzMotion.meter,
    this.delay = LenzMotion.meterDelay,
    this.animate = true,
  });

  /// Amber variant used for weak measurements (blurry photo, warnings).
  const LenzMeter.warn({
    super.key,
    required this.value,
    this.height = 10,
    this.duration = LenzMotion.meter,
    this.delay = LenzMotion.meterDelay,
    this.animate = true,
  }) : gradient = LenzGradients.meterWarn;

  /// Fill 0..1.
  final double value;
  final Gradient gradient;
  final double height;
  final Duration duration;
  final Duration delay;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return LenzAnimatedDouble(
      value: value.clamp(0.0, 1.0),
      initialValue: 0,
      duration: duration,
      delay: delay,
      curve: LenzMotion.ease,
      animate: animate,
      builder: (context, v) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: LenzColors.meterTrack,
            borderRadius: BorderRadius.circular(height),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v.clamp(0.0, 1.0),
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The prototype's `countUp()`: counts from [from] to [to] with a cubic
/// ease-out (`1-(1-p)^3`) over [duration]; changing [to] re-targets from the
/// currently shown number.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.to,
    this.from = 0,
    this.duration = LenzMotion.count,
    this.delay = Duration.zero,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.textAlign,
    this.animate = true,
  });

  final num to;
  final num from;
  final Duration duration;
  final Duration delay;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return LenzAnimatedDouble(
      value: to.toDouble(),
      initialValue: from.toDouble(),
      duration: duration,
      delay: delay,
      curve: LenzMotion.countUp,
      animate: animate,
      builder: (context, v) => Text(
        '$prefix${v.round()}$suffix',
        style: style,
        textAlign: textAlign,
        maxLines: 1,
      ),
    );
  }
}
