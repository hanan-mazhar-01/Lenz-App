import 'dart:math' as math;
import 'dart:typed_data';

import 'lenz_mood.dart';

double lenzClamp(double v, [double a = 0, double b = 1]) => v < a ? a : (v > b ? b : v);
double lenzLerp(double a, double b, double t) => a + (b - a) * t;

/// Rig state: per-parameter springs plus the blink / wander / wake
/// schedulers of the prototype `Lenz` class (rig.js). Pure Dart, no Flutter
/// dependencies, so it can be unit-tested.
class LenzRig {
  LenzRig({
    LenzMood mood = LenzMood.idle,
    bool wake = true,
    this.reduceMotion = false,
    math.Random? random,
  })  : _rnd = random ?? math.Random(),
        _mood = mood {
    for (final p in LenzParam.values) {
      cur[p.index] = kLenzDefaults[p]!;
      tgt[p.index] = kLenzDefaults[p]!;
    }
    nextBlink = 1500 + _rnd.nextDouble() * 2500;
    setMood(mood, instant: true);
    if (wake) {
      cur[LenzParam.lidTL.index] = 1;
      cur[LenzParam.lidTR.index] = 1;
      tgt[LenzParam.lidTL.index] = 1;
      tgt[LenzParam.lidTR.index] = 1;
      _wakeAt = 260;
    }
  }

  static const int paramCount = 35;
  static const double softK = 260;
  static final double softC = 2 * math.sqrt(softK);
  static const double hardK = 190;
  static const double hardC = 15;
  static final List<bool> _soft = [for (final p in LenzParam.values) kLenzSoftParams.contains(p)];

  final math.Random _rnd;
  final Float64List cur = Float64List(LenzParam.values.length);
  final Float64List tgt = Float64List(LenzParam.values.length);
  final Float64List vel = Float64List(LenzParam.values.length);

  /// Reduced motion (MediaQuery.disableAnimations): all springs soft,
  /// oscillation amplitudes x0.3, no idle wander.
  bool reduceMotion;
  double get mot => reduceMotion ? 0.3 : 1.0;

  LenzMood _mood;
  LenzMood get mood => _mood;

  /// Rig clock in milliseconds (advanced by [advance]).
  double now = 0;
  double get time => now / 1000;

  double blinkT0 = -1e9;
  double nextBlink = 0;
  double nextWander = 0;
  double wanX = 0, wanY = 0;
  double lookX = 0, lookY = 0;

  /// Current blink lid amount (0..1).
  double blink = 0;
  double? _wakeAt;

  double operator [](LenzParam p) => cur[p.index];

  void setMood(LenzMood mood, {bool instant = false}) {
    _mood = mood;
    for (final p in LenzParam.values) {
      if (p == LenzParam.bump) continue;
      tgt[p.index] = lenzMoodValue(mood, p);
    }
    if (instant) {
      for (final p in LenzParam.values) {
        if (p == LenzParam.bump) continue;
        cur[p.index] = tgt[p.index];
        vel[p.index] = 0;
      }
    } else {
      vel[LenzParam.bump.index] -= (mood == LenzMood.happy || mood == LenzMood.shocked) ? 700 : 300;
    }
  }

  void hop() => vel[LenzParam.bump.index] -= 900;

  /// Tap bounce.
  void bounce() {
    vel[LenzParam.bump.index] -= 800;
    vel[LenzParam.lowL.index] += 5;
    vel[LenzParam.lowR.index] += 5;
  }

  /// Spring integration (explicit Euler, 8 ms substeps), dt in seconds.
  void step(double dt) {
    final n = math.max(1, (dt / 0.008).ceil());
    final h = dt / n;
    final reduce = reduceMotion;
    for (var i = 0; i < n; i++) {
      for (var k = 0; k < paramCount; k++) {
        final soft = reduce || _soft[k];
        final kk = soft ? softK : hardK;
        final cc = soft ? softC : hardC;
        vel[k] += (kk * (tgt[k] - cur[k]) - cc * vel[k]) * h;
        cur[k] += vel[k] * h;
      }
    }
  }

  /// Advances the rig by [dt] seconds. [aim] is the pointer-derived gaze target
  /// (each component in -1..1) or null to use the idle wander.
  void advance(double dt, {double? aimX, double? aimY}) {
    now += dt * 1000;
    final wakeAt = _wakeAt;
    if (wakeAt != null && now >= wakeAt) {
      _wakeAt = null;
      tgt[LenzParam.lidTL.index] = lenzMoodValue(_mood, LenzParam.lidTL);
      tgt[LenzParam.lidTR.index] = lenzMoodValue(_mood, LenzParam.lidTR);
      vel[LenzParam.bump.index] -= 260;
    }
    step(dt);

    if (now > nextBlink) {
      blinkT0 = now;
      nextBlink = now + 1900 + _rnd.nextDouble() * 3200;
      if (_rnd.nextDouble() < 0.22) nextBlink = now + 330;
    }
    final bd = (now - blinkT0) / 1000;
    blink = (bd < 0 || bd > 0.18) ? 0 : math.sin((bd / 0.18) * math.pi);
    if (now > nextWander) {
      if (!reduceMotion) {
        wanX = (_rnd.nextDouble() * 2 - 1) * 0.8;
        wanY = (_rnd.nextDouble() * 2 - 1) * 0.5;
      }
      nextWander = now + 1200 + _rnd.nextDouble() * 2200;
    }

    final ax = aimX ?? wanX, ay = aimY ?? wanY;
    final w = lenzClamp(cur[LenzParam.lookW.index]);
    final k = 1 - math.exp(-dt * 12);
    lookX += (lenzLerp(cur[LenzParam.lookX.index], ax, w) - lookX) * k;
    lookY += (lenzLerp(cur[LenzParam.lookY.index], ay, w) - lookY) * k;
  }
}
