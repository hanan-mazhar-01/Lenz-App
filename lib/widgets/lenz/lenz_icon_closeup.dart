import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'lenz_assets.dart';
import 'lenz_eye.dart';
import 'lenz_spring.dart';

/// Gaze constants of the icon close-up eyes (prototype splash `SE`).
class _SE {
  const _SE(this.cx, this.cy, this.ax, this.ay, this.rx0, this.rx1, this.ry0, this.ry1);
  final double cx, cy, ax, ay, rx0, rx1, ry0, ry1;
}

const _SE _seL = _SE(435, 894, 60, 46, -84, 14, -60, 30);
const _SE _seR = _SE(918, 693, 50, 46, -20, 70, -60, 40);

/// Drives a [LenzIconCloseup]. All values may be changed every frame; the
/// widget repaints without rebuilding.
class LenzIconCloseupController extends ChangeNotifier {
  LenzIconCloseupController({
    double lookX = 0,
    double lookY = 0,
    double lid = 0,
    double pupil = 1,
    Rect viewBox = startViewBox,
  })  : _lookX = lookX,
        _lookY = lookY,
        _lid = lid,
        _pupil = pupil,
        _viewBox = viewBox;

  /// Initial close-up crop of the splash: a square window on the face with
  /// both eyes fully in view (the prototype's `250 470 850 640` slice cut the
  /// eyes off on a portrait phone).
  static const Rect startViewBox = Rect.fromLTWH(110, 154, 1100, 1100);

  /// The whole icon (prototype `0 0 1254 1254`).
  static const Rect fullViewBox = Rect.fromLTWH(0, 0, 1254, 1254);

  double _lookX, _lookY, _lid, _pupil;
  Rect _viewBox;

  /// Gaze direction, each -1..1 (scaled by the per-eye amplitude).
  double get lookX => _lookX;
  double get lookY => _lookY;

  /// Upper lid amount: 0 open, 1 closed.
  double get lid => _lid;

  /// Iris/pupil scale (1 = artwork size).
  double get pupil => _pupil;

  /// Visible window in the 1254x1254 artwork, fitted with BoxFit.cover
  /// (SVG `preserveAspectRatio="xMidYMid slice"`).
  Rect get viewBox => _viewBox;

  void set({double? lookX, double? lookY, double? lid, double? pupil, Rect? viewBox}) {
    _lookX = lookX ?? _lookX;
    _lookY = lookY ?? _lookY;
    _lid = lid ?? _lid;
    _pupil = pupil ?? _pupil;
    _viewBox = viewBox ?? _viewBox;
    notifyListeners();
  }

  static double _ease(double t) => t < 0 ? 0 : (t > 1 ? 1 : t * t * (3 - 2 * t));
  static double _easeOut(double t) => 1 - math.pow(1 - lenzClamp(t), 3).toDouble();

  /// Applies the prototype splash choreography at [t] seconds: lids open
  /// (0.35-0.85 s), look left, sweep right, settle, blink at 2.35 s, then the
  /// crop zooms out to the full icon (2.5-3.5 s). The pull-back into a circle
  /// (3.5-4.4 s), ring and title are the splash screen's job.
  void applySplashScript(double t) {
    double lx = 0, ly = 0, lid = 0, pup = 1;
    if (t < 0.35) {
      lid = 1;
    } else if (t < 0.85) {
      lid = 1 - _easeOut((t - 0.35) / 0.5);
    }
    if (t >= 0.9 && t < 1.5) {
      final u = _ease((t - 0.9) / 0.35);
      lx = -u;
      ly = -0.2 * u;
      pup = 1.05;
    } else if (t >= 1.5 && t < 2.1) {
      final u = _ease((t - 1.5) / 0.4);
      lx = lenzLerp(-1, 0.9, u);
      ly = lenzLerp(-0.2, 0.3, u);
    } else if (t >= 2.1) {
      final u = _ease((t - 2.1) / 0.3);
      lx = lenzLerp(0.9, 0.2, u);
      ly = lenzLerp(0.3, 0, u);
    }
    if (t >= 3.0) {
      // Idle life while the logo settles: small glances and two more blinks.
      final w = _ease((t - 3.0) / 0.6);
      lx += w * (0.28 * math.sin(t * 1.7) + 0.1 * math.sin(t * 4.1));
      ly += w * (0.16 * math.sin(t * 1.3 + 1));
    }
    for (final at in const [2.35, 4.35, 5.25]) {
      final bd = (t - at) / 0.2;
      if (bd > 0 && bd < 1) lid = math.max(lid, math.sin(bd * math.pi));
    }
    final z = _ease((t - 2.5) / 1.0);
    final vb = Rect.lerp(startViewBox, fullViewBox, z)!;
    set(lookX: lx, lookY: ly, lid: lid, pupil: pup, viewBox: vb);
  }
}

/// The splash icon close-up (base artwork + animated eyes). Fills its parent
/// with BoxFit.cover semantics; wrap it in a ClipOval / sized box / Transform
/// to do the pull-back. Call `LenzAssets.instance.ensureIconLoaded()` early.
class LenzIconCloseup extends StatefulWidget {
  const LenzIconCloseup({super.key, this.controller, this.background = const Color(0xFFFCF8F6)});

  final LenzIconCloseupController? controller;

  /// Fill behind the artwork (prototype `#FCF8F6`).
  final Color background;

  @override
  State<LenzIconCloseup> createState() => _LenzIconCloseupState();
}

class _LenzIconCloseupState extends State<LenzIconCloseup> {
  LenzIconCloseupController? _own;
  final _IconCache _cache = _IconCache();

  LenzIconCloseupController get _ctrl => widget.controller ?? (_own ??= LenzIconCloseupController());

  @override
  void initState() {
    super.initState();
    final a = LenzAssets.instance;
    if (!a.isIconReady) {
      a.ensureIconLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _LenzIconCloseupPainter(controller: _ctrl, cache: _cache, background: widget.background),
      ),
    );
  }
}

class _IconCache {
  LenzMeta? meta;
  LenzEyelid? eyeL, eyeR;
  final ui.Paint image = ui.Paint()
    ..filterQuality = ui.FilterQuality.medium
    ..isAntiAlias = true;
  final LenzEyePaints eye = LenzEyePaints(upperWidth: 9);
  final ui.Paint bg = ui.Paint();
  final ui.Paint patch = ui.Paint()..isAntiAlias = true;
  final ui.Paint catchlight = ui.Paint()
    ..isAntiAlias = true
    ..color = const ui.Color(0xF2FFFFFF);

  void bind(LenzMeta m) {
    if (identical(m, meta)) return;
    meta = m;
    eyeL = LenzEyelid(m.openL);
    eyeR = LenzEyelid(m.openR);
  }
}

/// Painter for [LenzIconCloseup].
class _LenzIconCloseupPainter extends CustomPainter {
  _LenzIconCloseupPainter({required this.controller, required _IconCache cache, required this.background})
      : _cache = cache,
        super(repaint: controller);

  final LenzIconCloseupController controller;
  final _IconCache _cache;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    if (background.a > 0) canvas.drawRect(bounds, _cache.bg..color = background);
    final a = LenzAssets.instance;
    if (!a.isIconReady) return;
    final meta = a.iconMeta!;
    _cache.bind(meta);
    final vb = controller.viewBox;
    final s = math.max(size.width / vb.width, size.height / vb.height);
    canvas.save();
    canvas.clipRect(bounds);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-vb.center.dx, -vb.center.dy);

    final base = a.icon['base']!;
    final br = meta.layers['base']!.rect;
    canvas.drawImageRect(base, Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()), br, _cache.image);

    for (final left in const [true, false]) {
      final e = left ? _seL : _seR;
      final side = left ? 'L' : 'R';
      paintLenzEye(
        canvas,
        lid: left ? _cache.eyeL! : _cache.eyeR!,
        irisImage: a.icon['iris$side']!,
        irisRect: meta.layers['iris$side']!.rect,
        lidImage: a.icon['lid$side']!,
        lidRect: meta.layers['lid$side']!.rect,
        imagePaint: _cache.image,
        paints: _cache.eye,
        cx: e.cx,
        cy: e.cy,
        dx: lenzClamp(controller.lookX * e.ax, e.rx0, e.rx1),
        dy: lenzClamp(controller.lookY * e.ay, e.ry0, e.ry1),
        scale: controller.pupil,
        lidT: controller.lid,
        // The right iris artwork has a keyhole cut out where its catchlight
        // was; fill it with iris colours and paint a round catchlight so it
        // doesn't show the white behind.
        irisUnder: left ? null : (c) => _fillKeyhole(c, meta.layers['irisR']!.rect),
        irisOver: left ? null : (c) => c.drawCircle(Offset(meta.layers['irisR']!.x + 171, meta.layers['irisR']!.y + 49), 25, _cache.catchlight),
      );
    }
    canvas.restore();
  }

  void _fillKeyhole(Canvas canvas, Rect iris) {
    final c = iris.center;
    _cache.patch.shader = ui.Gradient.radial(
      c,
      iris.width * 0.49,
      const [Color(0xFF040A0B), Color(0xFF040A0B), Color(0xFF6A2A10), Color(0xFFB8531E), Color(0xFF3A1708)],
      const [0, 0.5, 0.62, 0.86, 1],
    );
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(iris.left + 132, iris.top + 8, 80, 112));
    canvas.drawCircle(c, iris.width * 0.49, _cache.patch);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LenzIconCloseupPainter old) =>
      old.controller != controller || old.background != background || old._cache != _cache;
}
