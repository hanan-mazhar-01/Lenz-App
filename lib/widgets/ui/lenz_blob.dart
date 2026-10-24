import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';

/// The prototype's `.blob`: a mood-tinted radial glow behind the top of a
/// screen (`radial-gradient(60% 60% at 50% 40%, mood, transparent 72%)`,
/// opacity .9, extends 20% past both sides and 10% above the screen, 420px
/// tall). The colour cross-fades in 600ms when [color] changes.
///
/// Must be a child of a [Stack] that fills the screen (it positions itself).
class LenzBlob extends StatelessWidget {
  const LenzBlob({
    super.key,
    this.color = LenzColors.mint,
    this.height = 420,
    this.opacity = .9,
  });

  final Color color;
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: color),
            duration: const Duration(milliseconds: 600),
            builder: (context, c, _) => CustomPaint(
              painter: _BlobPainter(c ?? color, height, opacity),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter(this.color, this.height, this.opacity);
  final Color color;
  final double height;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTWH(
      -size.width * .2,
      -size.height * .1,
      size.width * 1.4,
      height,
    );
    final rx = box.width * .6, ry = box.height * .6;
    final cx = box.left + box.width * .5, cy = box.top + box.height * .4;
    final m = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(rx, ry, 1, 1);
    final c0 = color.withValues(alpha: color.a * opacity);
    final shader = ui.Gradient.radial(
      Offset.zero,
      1,
      [c0, c0.withValues(alpha: 0)],
      const [0, .72],
      TileMode.clamp,
      m.storage,
    );
    canvas.drawRect(box, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.color != color || old.height != height || old.opacity != opacity;
}

/// Ivory screen background with the mood [LenzBlob]; the content goes on top.
///
/// ```dart
/// LenzMoodBackground(mood: LenzVerdictStyle.auth.bg, child: ...)
/// ```
class LenzMoodBackground extends StatelessWidget {
  const LenzMoodBackground({
    super.key,
    required this.child,
    this.mood = LenzColors.mint,
    this.background = LenzColors.ivory,
  });

  final Widget child;
  final Color mood;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: Stack(
        fit: StackFit.expand,
        children: [LenzBlob(color: mood), child],
      ),
    );
  }
}
