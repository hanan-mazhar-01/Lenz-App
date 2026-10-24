import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/theme/lenz_motion.dart';

/// Fires bursts on a [LenzConfetti] layer.
class LenzConfettiController extends ChangeNotifier {
  final List<_Burst> _pending = [];

  /// Launches [count] particles from [origin] (logical px inside the layer).
  /// When [origin] is null the burst starts at (centre, 35% height), like
  /// `FX.confetti()` without coordinates.
  void burst({Offset? origin, int count = 110}) {
    _pending.add(_Burst(origin, count));
    notifyListeners();
  }
}

class _Burst {
  const _Burst(this.origin, this.count);
  final Offset? origin;
  final int count;
}

/// Full-screen confetti particle layer: port of the prototype's
/// `FX.confetti` (core.js). 110 particles, 7 colours, gravity 900 px/s²,
/// horizontal drag `vx *= 1 - .8 dt`, spin, fade out over the last 0.5s of a
/// 1.8-2.7s life. One [CustomPainter] driven by a [Ticker]; the ticker only
/// runs while particles are alive. Does nothing when animations are disabled
/// (the prototype skips confetti under reduced motion).
///
/// Put it on top of a [Stack] (`Positioned.fill`); it ignores pointers.
class LenzConfetti extends StatefulWidget {
  const LenzConfetti({super.key, required this.controller, this.random});

  final LenzConfettiController controller;

  /// Optional seeded random source (tests).
  final math.Random? random;

  static const List<Color> colors = [
    Color(0xFFFFC93C),
    Color(0xFF7BC043),
    Color(0xFFF26B5B),
    Color(0xFF6FB7F2),
    Color(0xFFFFFFFF),
    Color(0xFFB58BF0),
    Color(0xFF2EA44F),
  ];

  @override
  State<LenzConfetti> createState() => _LenzConfettiState();
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.w,
    required this.h,
    required this.rot,
    required this.vr,
    required this.color,
    required this.max,
  });

  double x, y, vx, vy, rot;
  final double w, h, vr, max;
  final Color color;
  double life = 0;
}

class _LenzConfettiState extends State<LenzConfetti>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final math.Random _rnd = widget.random ?? math.Random();
  final List<_Particle> _parts = [];
  final _ConfettiRepaint _repaint = _ConfettiRepaint();
  Size _size = Size.zero;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onBurst);
  }

  @override
  void didUpdateWidget(covariant LenzConfetti oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onBurst);
      widget.controller.addListener(_onBurst);
    }
  }

  void _onBurst() {
    final bursts = List.of(widget.controller._pending);
    widget.controller._pending.clear();
    if (!mounted || LenzMotion.reduced(context)) return;
    for (final b in bursts) {
      final o = b.origin ?? Offset(_size.width / 2, _size.height * .35);
      for (var i = 0; i < b.count; i++) {
        final ang = -math.pi / 2 + (_rnd.nextDouble() - .5) * 2.4;
        final sp = 260 + _rnd.nextDouble() * 520;
        _parts.add(_Particle(
          x: o.dx,
          y: o.dy,
          vx: math.cos(ang) * sp,
          vy: math.sin(ang) * sp,
          w: 5 + _rnd.nextDouble() * 7,
          h: 8 + _rnd.nextDouble() * 10,
          rot: _rnd.nextDouble() * 6,
          vr: (_rnd.nextDouble() - .5) * 14,
          color: LenzConfetti.colors[_rnd.nextInt(LenzConfetti.colors.length)],
          max: 1.8 + _rnd.nextDouble() * .9,
        ));
      }
    }
    if (_parts.isNotEmpty && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = math.min(.033, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    for (var i = _parts.length - 1; i >= 0; i--) {
      final p = _parts[i];
      p.life += dt;
      p.vy += 900 * dt;
      p.vx *= 1 - .8 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
      if (p.life > p.max) _parts.removeAt(i);
    }
    if (_parts.isEmpty) _ticker.stop();
    _repaint.ping();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onBurst);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          _size = c.biggest;
          return CustomPaint(
            size: c.biggest,
            painter: _ConfettiPainter(_parts, _repaint),
          );
        },
      ),
    );
  }
}

class _ConfettiRepaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.parts, Listenable repaint) : super(repaint: repaint);

  final List<_Particle> parts;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in parts) {
      final a = ((p.max - p.life) / .5).clamp(0.0, 1.0);
      if (a <= 0) continue;
      _paint.color = p.color.withValues(alpha: a);
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rot);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h),
        _paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => false;
}
