import 'dart:math' as math;
import 'dart:ui' as ui;

import 'lenz_assets.dart';

/// Per-eye cache of the eyelid sweep paths (prototype `_upPath` / `_loPath`).
/// Paths are reused and only rebuilt when the lid amount changes.
class LenzEyelid {
  LenzEyelid(this.opening);

  final LenzEyeOpening opening;
  // Eyeball shading, built once per eye from the opening's bounding box.
  late final ui.Paint sclera = ui.Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.radial(
      ui.Offset((opening.x0 + opening.x1) / 2, (opening.y0 + opening.y1) / 2),
      math.max(opening.x1 - opening.x0, opening.y1 - opening.y0) * 0.62,
      const [ui.Color(0xFFFDFBF8), ui.Color(0xFFF3EFE8), ui.Color(0xFFE2DBCE)],
      const [0, 0.62, 1],
    );
  late final ui.Paint roundness = ui.Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.radial(
      ui.Offset((opening.x0 + opening.x1) / 2, (opening.y0 + opening.y1) / 2),
      math.max(opening.x1 - opening.x0, opening.y1 - opening.y0) * 0.56,
      const [ui.Color(0x00281A0E), ui.Color(0x00281A0E), ui.Color(0x3D281A0E)],
      const [0, 0.66, 1],
    );
  late final ui.Paint lidShadow = ui.Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.linear(
      ui.Offset(0, opening.y0),
      ui.Offset(0, opening.y0 + (opening.y1 - opening.y0) * 0.34),
      const [ui.Color(0x66281A0E), ui.Color(0x00281A0E)],
    );
  final ui.Path upClip = ui.Path();
  final ui.Path upLine = ui.Path();
  final ui.Path loClip = ui.Path();
  final ui.Path loLine = ui.Path();
  double _ut = double.nan;
  double _lt = double.nan;

  /// Upper lid: t in 0..1 (0 open, 1 closed).
  void updateUpper(double t) {
    if (t == _ut) return;
    _ut = t;
    final o = opening;
    final x0 = o.x0, y0 = o.y0, x1 = o.x1, y1 = o.y1;
    final cx = (x0 + x1) / 2, top = y0 - 16;
    final ly = top + t * (y1 - y0 + 32);
    final sag = 0.16 * (x1 - x0) * math.sin(math.pi * math.min(1, t));
    upClip
      ..reset()
      ..moveTo(x0 - 30, top - 60)
      ..lineTo(x1 + 30, top - 60)
      ..lineTo(x1 + 30, ly)
      ..quadraticBezierTo(cx, ly + sag, x0 - 30, ly)
      ..close();
    upLine
      ..reset()
      ..moveTo(x0 - 30, ly)
      ..quadraticBezierTo(cx, ly + sag, x1 + 30, ly);
  }

  /// Lower lid: t in 0..1 (0 open, 1 = 66% raised).
  void updateLower(double t) {
    if (t == _lt) return;
    _lt = t;
    final o = opening;
    final x0 = o.x0, y0 = o.y0, x1 = o.x1, y1 = o.y1;
    final cx = (x0 + x1) / 2, bot = y1 + 16;
    final ly = bot - t * (y1 - y0 + 32) * 0.66;
    final sag = -0.2 * (x1 - x0) * math.sin(math.pi * math.min(1, t / 0.9));
    loClip
      ..reset()
      ..moveTo(x0 - 30, bot + 60)
      ..lineTo(x1 + 30, bot + 60)
      ..lineTo(x1 + 30, ly)
      ..quadraticBezierTo(cx, ly + sag, x0 - 30, ly)
      ..close();
    loLine
      ..reset()
      ..moveTo(x0 - 30, ly)
      ..quadraticBezierTo(cx, ly + sag, x1 + 30, ly);
  }
}

/// Shared paints for eye drawing.
class LenzEyePaints {
  LenzEyePaints({double upperWidth = 6})
      : upper = ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = upperWidth
          ..strokeCap = ui.StrokeCap.round
          ..isAntiAlias = true
          ..color = const ui.Color(0xE62B1A12); // #2b1a12 @ .9

  final ui.Paint upper;
  final ui.Paint lower = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 5
    ..strokeCap = ui.StrokeCap.round
    ..isAntiAlias = true
    ..color = const ui.Color(0x803A5A1C); // #3a5a1c @ .5
}

ui.Rect _src(ui.Image i) => ui.Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble());

/// Draws one eye: iris (offset + pupil scale about [cx],[cy]) clipped to the
/// opening, then the lid skin patch clipped to (opening ∩ upper sweep) and
/// (opening ∩ lower sweep), then lash lines. Same method as rig.js `eye()`.
void paintLenzEye(
  ui.Canvas canvas, {
  required LenzEyelid lid,
  required ui.Image irisImage,
  required ui.Rect irisRect,
  required ui.Image lidImage,
  required ui.Rect lidRect,
  required ui.Paint imagePaint,
  required LenzEyePaints paints,
  required double cx,
  required double cy,
  required double dx,
  required double dy,
  required double scale,
  required double lidT,
  double low = 0,
  void Function(ui.Canvas canvas)? irisUnder,
  void Function(ui.Canvas canvas)? irisOver,
}) {
  final up = lidT < 0 ? 0.0 : (lidT > 1 ? 1.0 : lidT);
  final lo = low < 0 ? 0.0 : (low > 1 ? 1.0 : low);
  final o = lid.opening;
  canvas.save();
  canvas.clipPath(o.smooth);

  // A clean eyeball under the iris: the base artwork keeps remnants of the
  // old iris / glass glare in the white, which show as loose parts when the
  // iris moves away from them.
  final box = ui.Rect.fromLTRB(o.x0 - 4, o.y0 - 4, o.x1 + 4, o.y1 + 4);
  canvas.drawRect(box, lid.sclera);

  canvas.save();
  canvas.translate(cx + dx, cy + dy);
  canvas.scale(scale);
  canvas.translate(-cx, -cy);
  irisUnder?.call(canvas);
  canvas.drawImageRect(irisImage, _src(irisImage), irisRect, imagePaint);
  irisOver?.call(canvas);
  canvas.restore();

  // Roundness + shade under the upper lid so iris and white read as one eyeball.
  canvas.drawRect(box, lid.roundness);
  canvas.drawRect(box, lid.lidShadow);

  if (up > 0) {
    lid.updateUpper(up);
    canvas.save();
    canvas.clipPath(lid.upClip);
    canvas.drawImageRect(lidImage, _src(lidImage), lidRect, imagePaint);
    canvas.restore();
  }
  if (lo > 0) {
    lid.updateLower(lo);
    canvas.save();
    canvas.clipPath(lid.loClip);
    canvas.drawImageRect(lidImage, _src(lidImage), lidRect, imagePaint);
    canvas.restore();
  }
  if (lidT > 0.04) canvas.drawPath(lid.upLine, paints.upper);
  if (low > 0.06) canvas.drawPath(lid.loLine, paints.lower);
  canvas.restore();
}
