import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/rendering.dart';

import 'lenz_assets.dart';
import 'lenz_eye.dart';
import 'lenz_mood.dart';
import 'lenz_spring.dart';

const double _deg = math.pi / 180;

/// Gaze constants (prototype `EYE`).
class LenzEyeConst {
  const LenzEyeConst(this.cx, this.cy, this.nx, this.ny, this.ax, this.ay, this.rx0, this.rx1, this.ry0, this.ry1);
  final double cx, cy, nx, ny, ax, ay, rx0, rx1, ry0, ry1;
}

const LenzEyeConst kLenzEyeL = LenzEyeConst(617, 505, -12, -3, 26, 20, -40, 9, -24, 14);
const LenzEyeConst kLenzEyeR = LenzEyeConst(862, 449, 12, -1, 22, 20, -8, 36, -26, 18);

/// Paths, paints and text that are built once and reused by every frame of a
/// character instance (no per-frame allocation of Paths / Paints).
class LenzPaintCache {
  LenzPaintCache();

  LenzEyelid? eyeL, eyeR;
  LenzMeta? _meta;

  final ui.Paint image = ui.Paint()
    ..filterQuality = ui.FilterQuality.medium
    ..isAntiAlias = true;
  final LenzEyePaints eye = LenzEyePaints();

  final ui.Paint fill = ui.Paint()..isAntiAlias = true;
  final ui.Paint stroke = ui.Paint()
    ..isAntiAlias = true
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round;
  final ui.Paint layer = ui.Paint();

  // Lens glint: clip ellipse (rotated -40deg about 1022,648) and gradient band.
  late final ui.Path glintClip = () {
    final p = ui.Path()..addOval(Rect.fromCenter(center: const Offset(1022, 648), width: 196, height: 140));
    return p.transform(_rotateAboutMatrix(-40 * _deg, 1022, 648));
  }();
  final ui.Paint glint = ui.Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.linear(
      const Offset(0, 0),
      const Offset(90, 0),
      const [Color(0x00FFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
      const [0, 0.5, 1],
    );

  static final ui.Path spark = ui.Path()
    ..moveTo(0, -12)
    ..quadraticBezierTo(2, -2, 12, 0)
    ..quadraticBezierTo(2, 2, 0, 12)
    ..quadraticBezierTo(-2, 2, -12, 0)
    ..quadraticBezierTo(-2, -2, 0, -12)
    ..close();
  static final ui.Path drop = ui.Path()
    ..moveTo(0, -40)
    ..quadraticBezierTo(28, 0, 0, 28)
    ..quadraticBezierTo(-28, 0, 0, -40)
    ..close();
  static final RRect shockBar = RRect.fromRectAndRadius(const Rect.fromLTWH(668, -130, 44, 92), const Radius.circular(22));

  TextPainter? _qBig, _qSmall;
  TextPainter qmark(bool big) {
    TextPainter make(double size) => TextPainter(
          text: TextSpan(
            text: '?',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w900,
              fontSize: size,
              height: 1,
              color: const Color(0xFFD08A1E),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    return big ? (_qBig ??= make(170)) : (_qSmall ??= make(130));
  }

  // Head skin mesh: the head PNG is drawn as a grid whose lower rows blend from
  // the head transform to the body transform, so the neck never opens a gap.
  static const int headRows = 11;
  ui.Image? _headImage;
  ui.ImageShader? _headShader;
  final ui.Paint headPaint = ui.Paint()..isAntiAlias = true;
  Float32List? _headTex;
  Uint16List? _headIdx;
  final Float32List headPos = Float32List((headRows + 1) * 2 * 2);

  ui.Paint headSkin(ui.Image img) {
    if (!identical(_headImage, img)) {
      _headShader?.dispose();
      _headImage = img;
      _headShader = ui.ImageShader(
        img,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: ui.FilterQuality.medium,
      );
      headPaint.shader = _headShader;
    }
    return headPaint;
  }

  Float32List headTex(double w, double h, double blendTop, double top, double height) {
    final cached = _headTex;
    if (cached != null) return cached;
    final t = Float32List((headRows + 1) * 2 * 2);
    for (var r = 0; r <= headRows; r++) {
      final y = r == 0 ? 0.0 : (blendTop - top) + (height - (blendTop - top)) * ((r - 1) / (headRows - 1));
      final v = r == 0 ? 0.0 : y * h / height;
      t[r * 4] = 0;
      t[r * 4 + 1] = v;
      t[r * 4 + 2] = w;
      t[r * 4 + 3] = v;
    }
    return _headTex = t;
  }

  Uint16List get headIndices {
    final cached = _headIdx;
    if (cached != null) return cached;
    final idx = <int>[];
    for (var r = 0; r < headRows; r++) {
      final a = r * 2, b = a + 1, c = a + 2, d = a + 3;
      idx.addAll([a, b, c, b, d, c]);
    }
    return _headIdx = Uint16List.fromList(idx);
  }

  ui.Shader? _mask;
  Size? _maskSize;
  final ui.Paint maskPaint = ui.Paint()..blendMode = BlendMode.dstIn;
  ui.Paint bustMask(Size size) {
    if (_maskSize != size || _mask == null) {
      _maskSize = size;
      _mask = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        const [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        const [0, 0.8, 1],
      );
      maskPaint.shader = _mask;
    }
    return maskPaint;
  }

  void bind(LenzMeta meta) {
    if (identical(meta, _meta)) return;
    _meta = meta;
    eyeL = LenzEyelid(meta.openL);
    eyeR = LenzEyelid(meta.openR);
  }
}

Float64List _rotateAboutMatrix(double a, double cx, double cy) {
  final c = math.cos(a), s = math.sin(a);
  // Column-major: translate(cx,cy) * rotate(a) * translate(-cx,-cy)
  return Float64List.fromList([c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, cx - c * cx + s * cy, cy - s * cx - c * cy, 0, 1]);
}

/// One painter per character instance; repaints through [repaint] each tick.
class LenzPainter extends CustomPainter {
  LenzPainter({
    required this.rig,
    required this.cache,
    required this.view,
    required this.fx,
    required this.shadow,
    super.repaint,
  });

  final LenzRig rig;
  final LenzPaintCache cache;
  final LenzView view;
  final bool fx;
  final bool shadow;

  static void _rotateAbout(Canvas c, double deg, double cx, double cy) {
    c.translate(cx, cy);
    c.rotate(deg * _deg);
    c.translate(-cx, -cy);
  }

  void _img(Canvas canvas, LenzAssets a, String name) {
    final img = a.char[name]!;
    final r = a.charMeta!.layers[name]!;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(r.x, r.y, r.w, r.h),
      cache.image,
    );
  }

  /// Draws the head PNG as a skinned mesh. Rows above [_blendTop] follow the
  /// head transform exactly (so brows / eyes stay glued to it); towards the
  /// neck the rows blend to the body transform, so the chin always meets the
  /// collar however far the head tilts or nods.
  static const double _blendTop = 598;

  /// Share of the head's tilt that the torso leans with (about the feet).
  static const double _bodyLean = 0.3;

  void _headMesh(Canvas canvas, LenzAssets a, double tx, double ty, double tiltDeg) {
    final img = a.char['head']!;
    final r = a.charMeta!.layers['head']!;
    final pos = cache.headPos;
    final rad = tiltDeg * _deg, cs = math.cos(rad), sn = math.sin(rad);
    const cx = 760.0, cy = 690.0;
    final left = r.x, right = r.x + r.w, bottom = r.y + r.h;
    void put(int i, double x, double y, double wgt) {
      final dx = x - cx, dy = y - cy;
      final hx = cx + dx * cs - dy * sn + tx;
      final hy = cy + dx * sn + dy * cs + ty;
      final by = y;
      pos[i] = (hx + (x - hx) * wgt);
      pos[i + 1] = hy + (by - hy) * wgt;
    }

    for (var row = 0; row <= LenzPaintCache.headRows; row++) {
      final double y;
      double w = 0;
      if (row == 0) {
        y = r.y;
      } else {
        final u = (row - 1) / (LenzPaintCache.headRows - 1);
        y = _blendTop + (bottom - _blendTop) * u;
        w = u * u * (3 - 2 * u);
      }
      put(row * 4, left, y, w);
      put(row * 4 + 2, right, y, w);
    }
    final verts = ui.Vertices.raw(
      ui.VertexMode.triangles,
      pos,
      textureCoordinates: cache.headTex(img.width.toDouble(), img.height.toDouble(), _blendTop, r.y, r.h),
      indices: cache.headIndices,
    );
    canvas.drawVertices(verts, BlendMode.srcOver, cache.headSkin(img));
    verts.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = LenzAssets.instance;
    if (!a.isReady || size.isEmpty) return;
    cache.bind(a.charMeta!);
    final vb = view.viewBox;
    final s = size.width / vb.width;
    final bounds = Offset.zero & size;

    if (view.fadesBottom) {
      canvas.saveLayer(bounds, cache.layer..color = const Color(0xFF000000));
    } else {
      canvas.save();
    }
    if (view.clips) canvas.clipRect(bounds);
    canvas.save();
    canvas.scale(s, size.height / vb.height);
    canvas.translate(-vb.left, -vb.top);
    _paintRig(canvas, a);
    canvas.restore();
    if (view.fadesBottom) canvas.drawRect(bounds, cache.bustMask(size));
    canvas.restore();
  }

  void _paintRig(Canvas canvas, LenzAssets a) {
    final c = rig.cur;
    double p(LenzParam k) => c[k.index];
    final t = rig.time, m = rig.mot;
    double osc(double f, [double ph = 0]) => math.sin(t * f + ph);

    final breath = osc(2.1) * p(LenzParam.bobAmp) * 5 * m;
    final hop = p(LenzParam.hop);
    final hopY = hop * osc(7).abs() * 60 * m;
    final sqz = breath * 0.0012 + p(LenzParam.squash) + (hop != 0 ? (1 - osc(7).abs()) * 0.05 * hop * m : 0);
    final bump = p(LenzParam.bump);
    final y = bump + breath - hopY, x = osc(46) * p(LenzParam.shake) * 8 * m;

    if (shadow) {
      final sh = lenzClamp(1 - (hopY - bump) / 450, 0.4, 1.2);
      cache.fill.color = Color.fromRGBO(0, 0, 0, 0.13 * sh);
      canvas.drawOval(Rect.fromCenter(center: const Offset(690, 1234), width: 600 * sh, height: 48), cache.fill);
    }

    canvas.save(); // char
    canvas.translate(x, y);
    canvas.translate(690, 1232);
    canvas.scale(1 + sqz, 1 - sqz);
    canvas.translate(-690, -1232);

    // The torso (tail, body, head, magnifier) is one connected rig: it leans
    // from the feet with the head's tilt, and the head hangs off the body's
    // neck, so no part ever moves on its own.
    final headTilt = p(LenzParam.tilt) + osc(1.3) * 0.9 * p(LenzParam.bobAmp) * m;
    final bodyRot = headTilt * _bodyLean;
    canvas.save(); // torso
    canvas.translate(0, -breath * 0.2);
    _rotateAbout(canvas, bodyRot, 690, 1232);

    // tail
    final tailAmp = p(LenzParam.tailAmp);
    canvas.save();
    _rotateAbout(canvas, p(LenzParam.tailRot) + osc(2.2 + tailAmp * 1.6) * 3.4 * tailAmp * m, 515, 1040);
    _img(canvas, a, 'tail');
    canvas.restore();

    // body
    _img(canvas, a, 'body');

    // head (+ brows + eyes), pivoting on the neck
    final headDy = p(LenzParam.nod) + breath * 1.1;
    final headLocal = headTilt - bodyRot;
    _headMesh(canvas, a, p(LenzParam.headX), headDy, headLocal);
    canvas.save();
    canvas.translate(p(LenzParam.headX), headDy);
    _rotateAbout(canvas, headLocal, 760, 690);
    canvas.save();
    canvas.translate(0, p(LenzParam.bLy));
    _rotateAbout(canvas, p(LenzParam.bLr), 585, 344);
    _img(canvas, a, 'browL');
    canvas.restore();
    canvas.save();
    canvas.translate(0, p(LenzParam.bRy));
    _rotateAbout(canvas, p(LenzParam.bRr), 822, 281);
    _img(canvas, a, 'browR');
    canvas.restore();
    final ps = math.max(0.3, p(LenzParam.pup));
    _eye(canvas, a, true, ps, math.max(p(LenzParam.lidTL), rig.blink), p(LenzParam.lowL));
    _eye(canvas, a, false, ps, math.max(p(LenzParam.lidTR), rig.blink), p(LenzParam.lowR));
    canvas.restore();

    // magnifier (the hand is part of the torso)
    final magA = p(LenzParam.mag) + osc(1.6, 1) * 2.4 * p(LenzParam.magAmp) * m;
    final magS = p(LenzParam.magS), magX = p(LenzParam.magX), magY = p(LenzParam.magY);
    canvas.save();
    canvas.translate(magX, magY);
    canvas.translate(905, 868);
    canvas.scale(magS);
    canvas.rotate(magA * _deg);
    canvas.translate(-905, -868);
    _img(canvas, a, 'mag');
    final gp = (t * 0.33) % 1;
    final gOp = (0.35 + lenzClamp(p(LenzParam.glint)) * 0.65) * (gp < 0.7 ? 1 : 0.3);
    canvas.save();
    canvas.clipPath(cache.glintClip);
    _rotateAbout(canvas, 25, 1022, 648);
    canvas.translate(930 + gp * 230, 0);
    cache.glint.color = Color.fromRGBO(0, 0, 0, gOp);
    canvas.drawRect(const Rect.fromLTWH(0, 480, 90, 420), cache.glint);
    canvas.restore();
    canvas.restore();

    canvas.restore(); // torso
    canvas.restore(); // char

    if (fx) _paintFx(canvas, t, magA, magS, magX, magY, bodyRot, -breath * 0.2);
  }

  void _eye(Canvas canvas, LenzAssets a, bool left, double scale, double lidT, double low) {
    final e = left ? kLenzEyeL : kLenzEyeR;
    final g = lenzClamp(rig.cur[LenzParam.gazeN.index]);
    final gx = lenzLerp(0, e.nx, g), gy = lenzLerp(0, e.ny, g);
    final dx = lenzClamp(gx + rig.lookX * e.ax, e.rx0, e.rx1);
    final dy = lenzClamp(gy + rig.lookY * e.ay, e.ry0, e.ry1);
    final side = left ? 'L' : 'R';
    final meta = a.charMeta!;
    paintLenzEye(
      canvas,
      lid: left ? cache.eyeL! : cache.eyeR!,
      irisImage: a.char['iris$side']!,
      irisRect: meta.layers['iris$side']!.rect,
      lidImage: a.char['lid$side']!,
      lidRect: meta.layers['lid$side']!.rect,
      imagePaint: cache.image,
      paints: cache.eye,
      cx: e.cx,
      cy: e.cy,
      dx: dx,
      dy: dy,
      scale: scale,
      lidT: lidT,
      low: low,
    );
  }

  // ---------------------------------------------------------------- FX ----

  /// Phase in 0..1 of a CSS infinite animation with [period] and [delay].
  static double _phase(double t, double period, double delay) {
    final v = ((t - delay) / period) % 1;
    return v < 0 ? v + 1 : v;
  }

  /// Runs [draw] with group opacity [op] (saveLayer only when needed).
  void _group(Canvas canvas, double op, Rect bounds, void Function() draw) {
    if (op <= 0.002) return;
    if (op >= 0.998) {
      draw();
      return;
    }
    canvas.saveLayer(bounds, cache.layer..color = Color.fromRGBO(0, 0, 0, op));
    draw();
    canvas.restore();
  }

  void _paintFx(Canvas canvas, double t, double magA, double magS, double magX, double magY, double bodyRot, double bodyDy) {
    final c = rig.cur;
    double p(LenzParam k) => c[k.index];
    final fill = cache.fill, stroke = cache.stroke;

    // sparkles: twinkle 1.5s ease-in-out (scale .15->1, rotate 0->45, opacity .2->1)
    _group(canvas, lenzClamp(p(LenzParam.fxSparkle)), const Rect.fromLTRB(100, -60, 1220, 780), () {
      void spark(double x, double y, double sc, double d) {
        final ph = _phase(t, 1.5, d);
        final u = Curves.easeInOut.transform(ph < 0.5 ? ph / 0.5 : (1 - ph) / 0.5);
        final k = 0.15 + 0.85 * u, rot = 45 * u, op = 0.2 + 0.8 * u;
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(sc * k);
        canvas.rotate(rot * _deg);
        fill.color = Color.fromRGBO(0xFF, 0xC9, 0x3C, op);
        canvas.drawPath(LenzPaintCache.spark, fill);
        canvas.restore();
      }

      spark(170, 330, 3.4, 0);
      spark(1150, 250, 4.4, .35);
      spark(200, 700, 2.8, .7);
      spark(1140, 520, 3.2, 1.05);
      spark(470, 10, 2.6, .5);
    });

    // shock "!" with bursts, scaled about (690,-40)
    final shock = math.max(0.0, p(LenzParam.fxShock));
    if (shock > 0.001) {
      canvas.save();
      canvas.translate(690, -40);
      canvas.scale(shock);
      canvas.translate(-690, 40);
      _group(canvas, lenzClamp(shock * 2), const Rect.fromLTRB(380, -150, 1000, 50), () {
        fill.color = const Color(0xFFE2412F);
        canvas.drawRRect(LenzPaintCache.shockBar, fill);
        canvas.drawCircle(const Offset(690, -2), 25, fill);
        stroke.strokeWidth = 16;
        void burst(double x0, double y0, double x1, double y1, double d) {
          final ph = _phase(t, 0.9, d);
          final u = Curves.easeInOut.transform(ph < 0.5 ? ph / 0.5 : (1 - ph) / 0.5);
          final offset = 24 * (1 - u); // dashoffset 24 -> 0 -> 24
          final len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
          final vis = math.min(len, 60 - offset) / len;
          stroke.color = Color.fromRGBO(0xE2, 0x41, 0x2F, 0.6 + 0.4 * u);
          canvas.drawLine(Offset(x0, y0), Offset(x0 + (x1 - x0) * vis, y0 + (y1 - y0) * vis), stroke);
        }

        burst(520, -40, 450, -90, 0);
        burst(490, 20, 400, 14, .15);
        burst(860, -40, 930, -90, 0);
        burst(890, 20, 980, 14, .15);
      });
      canvas.restore();
    }

    // think bubble with pulsing dots
    _group(canvas, lenzClamp(p(LenzParam.fxThink)), const Rect.fromLTRB(900, -160, 1200, 115), () {
      void bubble(Rect r, double w) {
        fill.color = const Color(0xFFFFFFFF);
        canvas.drawOval(r, fill);
        stroke
          ..strokeWidth = w
          ..color = const Color(0xFF9AA39E);
        canvas.drawOval(r, stroke);
      }

      bubble(Rect.fromCircle(center: const Offset(930, 90), radius: 16), 6);
      bubble(Rect.fromCircle(center: const Offset(985, 30), radius: 26), 6);
      bubble(Rect.fromCenter(center: const Offset(1075, -70), width: 230, height: 160), 7);
      for (var i = 0; i < 3; i++) {
        final ph = _phase(t, 1.2, i * 0.2);
        // dotpulse: 0% scale .6 op .45 -> 40% 1.25 / 1 -> 100% .6 / .45
        final u = ph < 0.4 ? Curves.easeInOut.transform(ph / 0.4) : 1 - Curves.easeInOut.transform((ph - 0.4) / 0.6);
        fill.color = Color.fromRGBO(0x12, 0x2F, 0x24, 0.45 + 0.55 * u);
        canvas.drawCircle(Offset(1025 + i * 50.0, -70), 17 * (0.6 + 0.65 * u), fill);
      }
    });

    // unsure "?" floating (1.8s ease-in-out, translateY 0->-26, rotate -8->8)
    _group(canvas, lenzClamp(p(LenzParam.fxUnsure)), const Rect.fromLTRB(150, -80, 1180, 260), () {
      void q(double x, double y, bool big, double d) {
        final tp = cache.qmark(big);
        final ph = _phase(t, 1.8, d);
        final u = Curves.easeInOut.transform(ph < 0.5 ? ph / 0.5 : (1 - ph) / 0.5);
        final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        final left = x - tp.width / 2, top = y - baseline;
        final cx = x, cy = top + tp.height / 2;
        canvas.save();
        canvas.translate(0, -26 * u);
        _rotateAbout(canvas, -8 + 16 * u, cx, cy);
        tp.paint(canvas, Offset(left, top));
        canvas.restore();
      }

      q(250, 200, true, 0);
      q(1090, 130, false, 0.5);
    });

    // sweat drop (1.9s ease-in)
    final sweat = lenzClamp(p(LenzParam.fxSweat));
    if (sweat > 0.002) {
      final ph = _phase(t, 1.9, 0);
      double ty, sc, op;
      if (ph < 0.25) {
        final u = Curves.easeIn.transform(ph / 0.25);
        ty = -10 + 10 * u;
        sc = 0.6 + 0.4 * u;
        op = u;
      } else {
        final u = Curves.easeIn.transform((ph - 0.25) / 0.75);
        ty = 110 * u;
        sc = 1;
        op = 1 - u;
      }
      _group(canvas, sweat * op, const Rect.fromLTRB(960, 230, 1040, 460), () {
        canvas.save();
        canvas.translate(1000, 300 + ty);
        // scale about the drop's fill-box centre (0,-6)
        canvas.translate(0, -6);
        canvas.scale(sc);
        canvas.translate(0, 6);
        fill.color = const Color(0xFF8FD0F5);
        canvas.drawPath(LenzPaintCache.drop, fill);
        stroke
          ..strokeWidth = 6
          ..color = const Color(0xFF5BAEE0);
        canvas.drawPath(LenzPaintCache.drop, stroke);
        canvas.restore();
      });
    }

    // ping rings following the lens centre
    final ping = lenzClamp(p(LenzParam.fxPing));
    if (ping > 0.002) {
      final ang = magA * _deg, ddx = 117.0, ddy = -220.0, cs = math.cos(ang), sn = math.sin(ang);
      final lx = 905 + magS * (ddx * cs - ddy * sn) + magX, ly = 868 + magS * (ddx * sn + ddy * cs) + magY;
      final br = bodyRot * _deg, bc = math.cos(br), bs = math.sin(br);
      final px = 690 + (lx - 690) * bc - (ly - 1232) * bs, py = 1232 + (lx - 690) * bs + (ly - 1232) * bc + bodyDy;
      for (var i = 0; i < 2; i++) {
        final ph = _phase(t, 1.6, i * 0.8);
        final u = Curves.easeOut.transform(ph);
        final k = 0.6 + 1.1 * u;
        stroke
          ..strokeWidth = 10 * k
          ..color = Color.fromRGBO(0x2E, 0xA4, 0x4F, 0.75 * (1 - u) * ping);
        canvas.drawCircle(Offset(px, py), 90 * k, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(LenzPainter old) =>
      old.rig != rig || old.view != view || old.fx != fx || old.shadow != shadow || old.cache != cache;
}
