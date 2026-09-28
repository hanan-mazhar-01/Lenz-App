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
class CaptureGuideOverlay extends StatelessWidget {
  final CaptureGuideType type;
  final String? label;

  const CaptureGuideOverlay({super.key, required this.type, this.label});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: CaptureGuidePainter(type: type)),
          if (label != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  label!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 11.5, fontWeight: FontWeight.w500),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CaptureGuidePainter extends CustomPainter {
  final CaptureGuideType type;

  /// Dim the area outside the guide (camera overlay) or not (illustration).
  final bool scrim;
  final Color color;

  CaptureGuidePainter({required this.type, this.scrim = true, this.color = Colors.white});

  static Rect guideRect(CaptureGuideType type, Size size) {
    final g = _GuideShape.of(type);
    var w = size.width * g.widthFactor;
    var h = w * g.aspect;
    final maxH = size.height * 0.86;
    if (h > maxH) {
      h = maxH;
      w = h / g.aspect;
    }
    return Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = _GuideShape.of(type);
    final rect = guideRect(type, size);
    final r = Radius.circular(math.min(rect.width, rect.height) * g.radius);
    final guide = RRect.fromRectAndRadius(rect, r);

    if (scrim) {
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(guide);
      canvas.drawPath(path, Paint()..color = Colors.black.withOpacity(0.38));
    }

    final stroke = Paint()
      ..color = color.withOpacity(scrim ? 0.85 : 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scrim ? 2 : 1.6;
    canvas.drawRRect(guide, stroke);

    if (scrim) _corners(canvas, rect, color);

    final sketch = Paint()
      ..color = color.withOpacity(scrim ? 0.5 : 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scrim ? 1.4 : 1.3
      ..strokeCap = StrokeCap.round;
    _sketch(canvas, rect, sketch);
  }

  void _corners(Canvas canvas, Rect rect, Color c) {
    final p = Paint()
      ..color = c
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final l = math.min(rect.width, rect.height) * 0.12;
    final o = rect.inflate(6);
    for (final (corner, dx, dy) in [
      (o.topLeft, 1.0, 1.0),
      (o.topRight, -1.0, 1.0),
      (o.bottomLeft, 1.0, -1.0),
      (o.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner + Offset(l * dx, 0), p);
      canvas.drawLine(corner, corner + Offset(0, l * dy), p);
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
            Rect.fromCenter(center: c, width: r.width * 0.72, height: r.height * 0.56), Radius.circular(r.height * 0.2));
        canvas.drawRRect(body, p);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(body.right - body.width * 0.05, c.dy - r.height * 0.18, r.width * 0.07, r.height * 0.36),
                Radius.circular(r.height * 0.06)),
            p);
        canvas.drawLine(Offset(body.left + body.width * 0.4, body.bottom - body.height * 0.2),
            Offset(body.left + body.width * 0.62, body.bottom - body.height * 0.2), p);
      case CaptureGuideType.shoeSide:
        final path = Path()
          ..moveTo(r.left + r.width * 0.08, r.top + r.height * 0.72)
          ..lineTo(r.left + r.width * 0.12, r.top + r.height * 0.3)
          ..quadraticBezierTo(r.left + r.width * 0.3, r.top + r.height * 0.2, r.left + r.width * 0.55, r.top + r.height * 0.42)
          ..quadraticBezierTo(r.left + r.width * 0.85, r.top + r.height * 0.5, r.right - r.width * 0.06, r.top + r.height * 0.7)
          ..lineTo(r.right - r.width * 0.06, r.top + r.height * 0.82)
          ..lineTo(r.left + r.width * 0.08, r.top + r.height * 0.82)
          ..close();
        canvas.drawPath(path, p);
      case CaptureGuideType.shoeSole:
        final sole = Path()
          ..addOval(Rect.fromLTWH(r.left + r.width * 0.12, r.top + r.height * 0.04, r.width * 0.76, r.height * 0.56))
          ..addOval(Rect.fromLTWH(r.left + r.width * 0.2, r.top + r.height * 0.55, r.width * 0.6, r.height * 0.4));
        canvas.drawPath(sole, p);
        for (var i = 0; i < 6; i++) {
          final y = r.top + r.height * (0.12 + i * 0.13);
          canvas.drawLine(Offset(r.left + r.width * 0.3, y), Offset(r.right - r.width * 0.3, y), p);
        }
      case CaptureGuideType.shoeHeel:
        canvas.drawRRect(
            RRect.fromRectAndRadius(r.deflate(s * 0.14), Radius.circular(s * 0.3)), p);
        canvas.drawLine(Offset(c.dx, r.top + s * 0.14), Offset(c.dx, r.top + s * 0.34), p);
      case CaptureGuideType.label:
        for (var i = 0; i < 4; i++) {
          final y = r.top + r.height * (0.25 + i * 0.17);
          canvas.drawLine(Offset(r.left + r.width * 0.12, y), Offset(r.right - r.width * (i.isEven ? 0.12 : 0.3), y), p);
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
        final body = Rect.fromLTWH(r.left + r.width * 0.12, r.top + r.height * 0.34, r.width * 0.76, r.height * 0.56);
        canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(s * 0.06)), p);
        canvas.drawArc(Rect.fromLTWH(r.left + r.width * 0.3, r.top + r.height * 0.1, r.width * 0.4, r.height * 0.5),
            math.pi, math.pi, false, p);
      case CaptureGuideType.bagInterior:
        canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(s * 0.12), Radius.circular(s * 0.06)), p);
        canvas.drawRect(Rect.fromCenter(center: c + Offset(0, -r.height * 0.12), width: r.width * 0.34, height: r.height * 0.12), p);
      case CaptureGuideType.glassesFront:
        final lw = r.width * 0.34, lh = r.height * 0.6;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left + r.width * 0.1, c.dy - lh / 2, lw, lh), Radius.circular(lh * 0.4)), p);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.right - r.width * 0.1 - lw, c.dy - lh / 2, lw, lh), Radius.circular(lh * 0.4)), p);
        canvas.drawLine(Offset(r.left + r.width * 0.44, c.dy - lh * 0.2), Offset(r.right - r.width * 0.44, c.dy - lh * 0.2), p);
      case CaptureGuideType.templeArm:
        canvas.drawLine(Offset(r.left + r.width * 0.06, c.dy), Offset(r.right - r.width * 0.12, c.dy), p);
        canvas.drawLine(Offset(r.right - r.width * 0.12, c.dy), Offset(r.right - r.width * 0.04, c.dy + r.height * 0.25), p);
        for (var i = 0; i < 3; i++) {
          final x = r.left + r.width * (0.2 + i * 0.15);
          canvas.drawLine(Offset(x, c.dy - r.height * 0.18), Offset(x + r.width * 0.1, c.dy - r.height * 0.18), p);
        }
      case CaptureGuideType.bottle:
        final neck = Rect.fromCenter(center: Offset(c.dx, r.top + r.height * 0.14), width: r.width * 0.3, height: r.height * 0.14);
        canvas.drawRect(neck, p);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left + r.width * 0.14, r.top + r.height * 0.26, r.width * 0.72, r.height * 0.66), Radius.circular(s * 0.1)), p);
      case CaptureGuideType.fullItem:
      case CaptureGuideType.generic:
        canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(s * 0.18), Radius.circular(s * 0.05)), p);
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
      old.type != type || old.scrim != scrim || old.color != color;
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
    this.background = const Color(0xFF1F3A2E),
    this.foreground = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.22)),
      padding: EdgeInsets.all(size * 0.08),
      child: CustomPaint(painter: CaptureGuidePainter(type: type, scrim: false, color: foreground)),
    );
  }
}
