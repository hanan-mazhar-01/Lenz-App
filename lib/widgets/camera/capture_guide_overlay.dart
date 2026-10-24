import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/capture_guide.dart';

/// Geometry of a guide, as fractions of the available box.
class _GuideShape {
  /// Width as a fraction of the box width.
  final double widthFactor;

  /// Height relative to width.
  final double aspect;

  /// Corner radius relative to the guide's shorter side (0.5 = circle/pill).
  final double radius;

  const _GuideShape(this.widthFactor, this.aspect, this.radius);

  static _GuideShape of(CaptureGuideType t) => switch (t) {
    CaptureGuideType.fullItem => const _GuideShape(0.84, 1.1, 0.06),
    CaptureGuideType.watchFaceRound => const _GuideShape(0.7, 1.0, 0.5),
    CaptureGuideType.watchFaceSquare => const _GuideShape(0.6, 1.2, 0.22),
    CaptureGuideType.watchBack => const _GuideShape(0.72, 1.0, 0.5),
    CaptureGuideType.watchSide => const _GuideShape(0.84, 0.42, 0.18),
    CaptureGuideType.shoeSide => const _GuideShape(0.88, 0.5, 0.2),
    CaptureGuideType.shoeSole => const _GuideShape(0.46, 1.9, 0.45),
    CaptureGuideType.shoeHeel => const _GuideShape(0.56, 1.25, 0.35),
    CaptureGuideType.label => const _GuideShape(0.78, 0.55, 0.08),
    CaptureGuideType.macro => const _GuideShape(0.6, 1.0, 0.08),
    CaptureGuideType.bagFull => const _GuideShape(0.84, 0.9, 0.12),
    CaptureGuideType.bagInterior => const _GuideShape(0.66, 1.3, 0.1),
    CaptureGuideType.hardware => const _GuideShape(0.56, 1.0, 0.3),
    CaptureGuideType.glassesFront => const _GuideShape(0.9, 0.42, 0.2),
    CaptureGuideType.templeArm => const _GuideShape(0.9, 0.28, 0.1),
    CaptureGuideType.hinge => const _GuideShape(0.52, 1.0, 0.12),
    CaptureGuideType.screen => const _GuideShape(0.6, 1.35, 0.1),
    CaptureGuideType.bottle => const _GuideShape(0.5, 1.6, 0.12),
    CaptureGuideType.generic => const _GuideShape(0.78, 1.0, 0.06),
  };
}

/// Camera framing overlay: dims everything outside the guide, outlines it
/// and sketches the part inside. It is a framing aid only; it does not
/// detect or verify alignment, and capture is always allowed.
///
/// Lenz look (mock `evidence_capture_redesign`): the area outside the guide is
/// dimmed `rgba(4,10,7,.5)`, white dashed outline with rounded corner
/// brackets, a green scan line sweeping inside the guide and one short
/// caption chip hanging off the guide's bottom edge. With [animate] the guide
/// breathes (scale 1 -> 1.035, 3s) and the line sweeps (2.4s); reduced motion
/// keeps both still.
class CaptureGuideOverlay extends StatefulWidget {
  final CaptureGuideType type;

  /// Short caption (a few words) shown as a white chip on the guide's bottom
  /// edge.
  final String? label;
  final bool animate;

  /// The shutter was pressed: hold the guide exactly as it is (no more
  /// breathing or scan line).
  final bool frozen;

  const CaptureGuideOverlay({
    super.key,
    required this.type,
    this.label,
    this.animate = false,
    this.frozen = false,
  });

  @override
  State<CaptureGuideOverlay> createState() => _CaptureGuideOverlayState();
}

class _CaptureGuideOverlayState extends State<CaptureGuideOverlay> with TickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// Room kept below the guide for the caption chip (half of it hangs off).
  static const double _capRoom = 22;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant CaptureGuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.frozen) {
      _breathe.stop();
      _sweep.stop();
    } else if (widget.animate && !reduced) {
      if (!_breathe.isAnimating) _breathe.repeat();
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _breathe.stop();
      _breathe.value = 0;
      _sweep.stop();
      _sweep.value = .25;
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          final rect = CaptureGuidePainter.guideRect(
            widget.type,
            size,
            maxHeightFactor: .84,
            bottomRoom: label == null ? 0 : _capRoom,
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_breathe, _sweep]),
                  builder: (context, _) {
                    final b = Curves.ease.transform(1 - (2 * _breathe.value - 1).abs());
                    final s = Curves.easeInOut.transform(1 - (2 * _sweep.value - 1).abs());
                    return CustomPaint(
                      painter: CaptureGuidePainter(
                        type: widget.type,
                        guideScale: 1 + .035 * b,
                        maxHeightFactor: .84,
                        bottomRoom: label == null ? 0 : _capRoom,
                        sweep: s,
                      ),
                    );
                  },
                ),
              ),
              if (label != null)
                Positioned(
                  left: 12,
                  right: 12,
                  top: rect.bottom - 17,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, .5),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                            spreadRadius: -6,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            color: Color(0xFF122F24),
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class CaptureGuidePainter extends CustomPainter {
  final CaptureGuideType type;

  /// Dim the area outside the guide (camera overlay) or not (illustration).
  final bool scrim;
  final Color color;

  /// Scale of the guide about its centre (breathing animation); 1 = static.
  final double guideScale;

  /// Largest guide height as a share of the box, and room kept free below the
  /// guide (for the caption chip); the guide is centred in what is left.
  final double maxHeightFactor;
  final double bottomRoom;

  /// 0-1 position of the scan line inside the guide; null = no line.
  final double? sweep;

  /// Colour dimming the area outside the guide.
  static const Color scrimColor = Color.fromRGBO(4, 10, 7, .5);

  CaptureGuidePainter({
    required this.type,
    this.scrim = true,
    this.color = Colors.white,
    this.guideScale = 1,
    this.maxHeightFactor = .86,
    this.bottomRoom = 0,
    this.sweep,
  });

  static Rect guideRect(
    CaptureGuideType type,
    Size size, {
    double maxHeightFactor = .86,
    double bottomRoom = 0,
  }) {
    final g = _GuideShape.of(type);
    final availH = size.height - bottomRoom;
    var w = size.width * g.widthFactor;
    var h = w * g.aspect;
    final maxH = availH * maxHeightFactor;
    if (h > maxH) {
      h = maxH;
      w = h / g.aspect;
    }
    return Rect.fromCenter(center: Offset(size.width / 2, availH / 2), width: w, height: h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = _GuideShape.of(type);
    final base = guideRect(type, size, maxHeightFactor: maxHeightFactor, bottomRoom: bottomRoom);
    final rect = guideScale == 1
        ? base
        : Rect.fromCenter(
            center: base.center,
            width: base.width * guideScale,
            height: base.height * guideScale,
          );
    final r = Radius.circular(math.min(rect.width, rect.height) * g.radius);
    final guide = RRect.fromRectAndRadius(rect, r);

    if (scrim) {
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(guide);
      canvas.drawPath(path, Paint()..color = scrimColor);
    }

    final stroke = Paint()
      ..color = color.withOpacity(scrim ? 0.9 : 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scrim ? 3 : 1.6
      ..strokeCap = StrokeCap.round;
    if (scrim) {
      // Prototype guide: white dashed outline (dash 14, gap 12).
      _dashed(canvas, Path()..addRRect(guide), stroke, 14, 12);
    } else {
      canvas.drawRRect(guide, stroke);
    }

    if (scrim) {
      if (sweep != null) _scanLine(canvas, rect, guide, sweep!);
      _corners(canvas, rect, color);
    }

    final sketch = Paint()
      ..color = color.withOpacity(scrim ? 0.6 : 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scrim ? 1.8 : 1.3
      ..strokeCap = StrokeCap.round;
    _sketch(canvas, rect, sketch);
  }

  static void _dashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  /// Green scan line sweeping inside the guide (mock `.scanline`: 8% in from
  /// both sides, 12% -> 88% of the height). Decorative only.
  void _scanLine(Canvas canvas, Rect rect, RRect guide, double t) {
    final y = rect.top + rect.height * (.12 + .76 * t);
    final line = Rect.fromLTWH(rect.left + rect.width * .08, y - 1, rect.width * .84, 2);
    const glow = Color(0xFF5CE08A);
    final shader = const LinearGradient(colors: [Color(0x005CE08A), glow, Color(0x005CE08A)])
        .createShader(line);
    canvas.save();
    canvas.clipRRect(guide);
    canvas.drawRRect(
      RRect.fromRectAndRadius(line.inflate(3), const Radius.circular(6)),
      Paint()
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
        ..color = glow.withOpacity(.6),
    );
    canvas.drawRect(line, Paint()..shader = shader);
    canvas.restore();
  }

  /// Rounded corner brackets just outside the guide (prototype `.vf i`).
  void _corners(Canvas canvas, Rect rect, Color c) {
    final p = Paint()
      ..color = c
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final l = math.max(14.0, math.min(rect.width, rect.height) * 0.14);
    final o = rect.inflate(7);
    final rr = math.min(l * 0.6, 18.0);
    for (final (cx, cy, sx, sy) in [
      (o.left, o.top, 1.0, 1.0),
      (o.right, o.top, -1.0, 1.0),
      (o.left, o.bottom, 1.0, -1.0),
      (o.right, o.bottom, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(cx, cy + sy * l)
        ..lineTo(cx, cy + sy * rr)
        ..arcToPoint(Offset(cx + sx * rr, cy), radius: Radius.circular(rr), clockwise: sx * sy > 0)
        ..lineTo(cx + sx * l, cy);
      canvas.drawPath(path, p);
    }
  }

  /// A light sketch of the part, so the user knows what belongs inside.
  void _sketch(Canvas canvas, Rect r, Paint p) {
    final c = r.center;
    final s = math.min(r.width, r.height);
    switch (type) {
      case CaptureGuideType.watchBack:
        canvas.drawCircle(c, s * 0.26, p);
        canvas.drawCircle(c, s * 0.12, p);
        for (var i = 0; i < 4; i++) {
          final a = math.pi / 4 + i * math.pi / 2;
          canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * s * 0.19, s * 0.025, p);
        }
        _arcText(canvas, c, s * 0.36, p);
      case CaptureGuideType.watchFaceRound:
        canvas.drawCircle(c, s * 0.38, p);
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(c + d * s * 0.33, c + d * s * 0.38, p);
        }
        canvas.drawLine(c, c + Offset(0, -s * 0.24), p);
        canvas.drawLine(c, c + Offset(s * 0.17, 0), p);
      case CaptureGuideType.watchFaceSquare:
      case CaptureGuideType.screen:
        final inner = RRect.fromRectAndRadius(r.deflate(s * 0.1), Radius.circular(s * 0.12));
        canvas.drawRRect(inner, p);
        if (type == CaptureGuideType.screen) {
          for (var i = 0; i < 5; i++) {
            final y = inner.top + inner.height * (0.2 + i * 0.14);
            canvas.drawLine(Offset(inner.left + s * 0.08, y), Offset(inner.right - s * 0.08, y), p);
          }
        }
      case CaptureGuideType.watchSide:
        final body = RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: r.width * 0.72, height: r.height * 0.56),
          Radius.circular(r.height * 0.2),
        );
        canvas.drawRRect(body, p);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              body.right - body.width * 0.05,
              c.dy - r.height * 0.18,
              r.width * 0.07,
              r.height * 0.36,
            ),
            Radius.circular(r.height * 0.06),
          ),
          p,
        );
        canvas.drawLine(
          Offset(body.left + body.width * 0.4, body.bottom - body.height * 0.2),
          Offset(body.left + body.width * 0.62, body.bottom - body.height * 0.2),
          p,
        );
      case CaptureGuideType.shoeSide:
        final path = Path()
          ..moveTo(r.left + r.width * 0.08, r.top + r.height * 0.72)
          ..lineTo(r.left + r.width * 0.12, r.top + r.height * 0.3)
          ..quadraticBezierTo(
            r.left + r.width * 0.3,
            r.top + r.height * 0.2,
            r.left + r.width * 0.55,
            r.top + r.height * 0.42,
          )
          ..quadraticBezierTo(
            r.left + r.width * 0.85,
            r.top + r.height * 0.5,
            r.right - r.width * 0.06,
            r.top + r.height * 0.7,
          )
          ..lineTo(r.right - r.width * 0.06, r.top + r.height * 0.82)
          ..lineTo(r.left + r.width * 0.08, r.top + r.height * 0.82)
          ..close();
        canvas.drawPath(path, p);
      case CaptureGuideType.shoeSole:
        final sole = Path()
          ..addOval(
            Rect.fromLTWH(
              r.left + r.width * 0.12,
              r.top + r.height * 0.04,
              r.width * 0.76,
              r.height * 0.56,
            ),
          )
          ..addOval(
            Rect.fromLTWH(
              r.left + r.width * 0.2,
              r.top + r.height * 0.55,
              r.width * 0.6,
              r.height * 0.4,
            ),
          );
        canvas.drawPath(sole, p);
        for (var i = 0; i < 6; i++) {
          final y = r.top + r.height * (0.12 + i * 0.13);
          canvas.drawLine(Offset(r.left + r.width * 0.3, y), Offset(r.right - r.width * 0.3, y), p);
        }
      case CaptureGuideType.shoeHeel:
        canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(s * 0.14), Radius.circular(s * 0.3)), p);
        canvas.drawLine(Offset(c.dx, r.top + s * 0.14), Offset(c.dx, r.top + s * 0.34), p);
      case CaptureGuideType.label:
        for (var i = 0; i < 4; i++) {
          final y = r.top + r.height * (0.25 + i * 0.17);
          canvas.drawLine(
            Offset(r.left + r.width * 0.12, y),
            Offset(r.right - r.width * (i.isEven ? 0.12 : 0.3), y),
            p,
          );
        }
      case CaptureGuideType.macro:
      case CaptureGuideType.hinge:
        canvas.drawLine(c - Offset(s * 0.08, 0), c + Offset(s * 0.08, 0), p);
        canvas.drawLine(c - Offset(0, s * 0.08), c + Offset(0, s * 0.08), p);
        canvas.drawCircle(c, s * 0.22, p);
      case CaptureGuideType.hardware:
        canvas.drawCircle(c, s * 0.24, p);
        canvas.drawLine(c - Offset(s * 0.12, 0), c + Offset(s * 0.12, 0), p);
      case CaptureGuideType.bagFull:
        final body = Rect.fromLTWH(
          r.left + r.width * 0.12,
          r.top + r.height * 0.34,
          r.width * 0.76,
          r.height * 0.56,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(s * 0.06)), p);
        canvas.drawArc(
          Rect.fromLTWH(
            r.left + r.width * 0.3,
            r.top + r.height * 0.1,
            r.width * 0.4,
            r.height * 0.5,
          ),
          math.pi,
          math.pi,
          false,
          p,
        );
      case CaptureGuideType.bagInterior:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.deflate(s * 0.12), Radius.circular(s * 0.06)),
          p,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: c + Offset(0, -r.height * 0.12),
            width: r.width * 0.34,
            height: r.height * 0.12,
          ),
          p,
        );
      case CaptureGuideType.glassesFront:
        final lw = r.width * 0.34, lh = r.height * 0.6;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(r.left + r.width * 0.1, c.dy - lh / 2, lw, lh),
            Radius.circular(lh * 0.4),
          ),
          p,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(r.right - r.width * 0.1 - lw, c.dy - lh / 2, lw, lh),
            Radius.circular(lh * 0.4),
          ),
          p,
        );
        canvas.drawLine(
          Offset(r.left + r.width * 0.44, c.dy - lh * 0.2),
          Offset(r.right - r.width * 0.44, c.dy - lh * 0.2),
          p,
        );
      case CaptureGuideType.templeArm:
        canvas.drawLine(
          Offset(r.left + r.width * 0.06, c.dy),
          Offset(r.right - r.width * 0.12, c.dy),
          p,
        );
        canvas.drawLine(
          Offset(r.right - r.width * 0.12, c.dy),
          Offset(r.right - r.width * 0.04, c.dy + r.height * 0.25),
          p,
        );
        for (var i = 0; i < 3; i++) {
          final x = r.left + r.width * (0.2 + i * 0.15);
          canvas.drawLine(
            Offset(x, c.dy - r.height * 0.18),
            Offset(x + r.width * 0.1, c.dy - r.height * 0.18),
            p,
          );
        }
      case CaptureGuideType.bottle:
        final neck = Rect.fromCenter(
          center: Offset(c.dx, r.top + r.height * 0.14),
          width: r.width * 0.3,
          height: r.height * 0.14,
        );
        canvas.drawRect(neck, p);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              r.left + r.width * 0.14,
              r.top + r.height * 0.26,
              r.width * 0.72,
              r.height * 0.66,
            ),
            Radius.circular(s * 0.1),
          ),
          p,
        );
      case CaptureGuideType.fullItem:
      case CaptureGuideType.generic:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.deflate(s * 0.18), Radius.circular(s * 0.05)),
          p,
        );
    }
  }

  void _arcText(Canvas canvas, Offset c, double radius, Paint p) {
    for (var i = 0; i < 18; i++) {
      final a = -math.pi * 0.85 + i * (math.pi * 1.7 / 17);
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * radius, c + d * (radius + 4), p);
    }
  }

  @override
  bool shouldRepaint(covariant CaptureGuidePainter old) =>
      old.type != type ||
      old.scrim != scrim ||
      old.color != color ||
      old.guideScale != guideScale ||
      old.sweep != sweep ||
      old.maxHeightFactor != maxHeightFactor ||
      old.bottomRoom != bottomRoom;
}

/// Small drawn illustration of what to frame. Shown as the "example" on the
/// capture screen; it is not a reference image of the genuine product.
class CaptureGuideIllustration extends StatelessWidget {
  final CaptureGuideType type;
  final double size;
  final Color background;
  final Color foreground;

  const CaptureGuideIllustration({
    super.key,
    required this.type,
    this.size = 64,
    this.background = const Color(0xFF122F24),
    this.foreground = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      padding: EdgeInsets.all(size * 0.08),
      child: CustomPaint(
        painter: CaptureGuidePainter(type: type, scrim: false, color: foreground),
      ),
    );
  }
}
