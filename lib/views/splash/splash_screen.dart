import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// Branded cold-start splash (~4.5 s): the animated Lenz character, cropped
/// to a circle exactly like the profile avatar, with a spinning loading ring
/// around it and the "Lenz / REAL OR FAKE DETECTOR" title below.
///
/// * 0-0.7 s  the circle pops in; Lenz wakes up and waves hello.
/// * 0.3 s    the loading ring fades in and keeps spinning.
/// * 0.6-1.2 s the title and chip rise in.
/// * 2.4 s    Lenz settles into an idle mood (eyes wide, glancing around).
/// * 4.5 s    done ([totalDuration]). Tapping anywhere calls [onSkip].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onSkip, this.startAt});

  /// Called when the user taps anywhere to skip the intro.
  final VoidCallback? onSkip;

  /// Starts the timeline at this point (used by tests / previews).
  final Duration? startAt;

  /// Total length of the intro; the app should leave the splash after this.
  static const Duration totalDuration = Duration(milliseconds: 4500);

  /// Kept for compatibility with older callers (native launch icon size).
  static const double iconSize = 132;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  late final Ticker _ticker;
  bool _reduced = false;
  bool _started = false;

  static double get _end => SplashScreen.totalDuration.inMilliseconds / 1000;

  @override
  void initState() {
    super.initState();
    LenzAssets.instance.ensureAllLoaded();
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = LenzMotion.reduced(context);
    if (_started) return;
    _started = true;
    if (_reduced) {
      _t.value = _end;
    } else {
      _t.value = (widget.startAt?.inMilliseconds ?? 0) / 1000;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final start = (widget.startAt?.inMilliseconds ?? 0) / 1000;
    final t = start + elapsed.inMicroseconds / 1e6;
    _t.value = math.min(t, _end + 10);
    // Keep ticking: the ring keeps spinning until the app leaves the splash.
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  static double _ease(double t) =>
      t < 0 ? 0 : (t > 1 ? 1 : t * t * (3 - 2 * t));

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: LenzColors.ivory,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSkip,
        child: LayoutBuilder(
          builder: (context, c) {
            final sw = c.maxWidth, sh = c.maxHeight;
            final d = math.min(sw, sh) * 0.44;
            final cy = sh * 0.38;
            final ringSize = d + 34;
            return Stack(
              children: [
                // Loading ring (behind the logo).
                ValueListenableBuilder<double>(
                  valueListenable: _t,
                  builder: (context, t, _) {
                    final ro = _ease((t - 0.3) / 0.4);
                    final pop = Curves.easeOutBack.transform(
                      (t / 0.7).clamp(0.0, 1.0),
                    );
                    final spin = _reduced
                        ? 0.0
                        : (t * 340 % 360) * math.pi / 180;
                    return Positioned(
                      left: sw / 2 - ringSize / 2,
                      top: cy - ringSize / 2,
                      width: ringSize,
                      height: ringSize,
                      child: Opacity(
                        opacity: ro,
                        child: Transform.scale(
                          scale: _reduced ? 1.0 : pop,
                          child: Transform.rotate(
                            angle: spin,
                            child: const CustomPaint(
                              painter: _SplashRingPainter(),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Animated Lenz in a circle, same crop as the profile avatar.
                ValueListenableBuilder<double>(
                  valueListenable: _t,
                  builder: (context, t, _) {
                    final pop = Curves.easeOutBack.transform(
                      (t / 0.7).clamp(0.0, 1.0),
                    );
                    final appear = (t / 0.3).clamp(0.0, 1.0);
                    return Positioned(
                      left: (sw - d) / 2,
                      top: cy - d / 2,
                      width: d,
                      height: d,
                      child: Opacity(
                        opacity: appear,
                        child: Transform.scale(
                          scale: _reduced ? 1.0 : pop,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: LenzColors.mint,
                              boxShadow: [
                                BoxShadow(
                                  color: LenzColors.forest.withValues(
                                    alpha: 0.22,
                                  ),
                                  offset: const Offset(0, 16),
                                  blurRadius: 40,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _SplashLenz(size: d, t: _t),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Title + chip at 61% of the height.
                ValueListenableBuilder<double>(
                  valueListenable: _t,
                  builder: (context, t, _) {
                    final to = _ease((t - 0.6) / 0.6);
                    return Positioned(
                      left: 16,
                      right: 16,
                      top: sh * 0.61,
                      child: Opacity(
                        opacity: to,
                        child: Transform.translate(
                          offset: Offset(0, (1 - to) * 14),
                          child: const _SplashTitle(),
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 46 + bottomInset * 0.5,
                  child: const Text(
                    'Tap anywhere to skip',
                    textAlign: TextAlign.center,
                    style: LenzText.tiny,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The `peek` crop sized like the profile avatar (`width:140px;margin:-8px 0 0
/// -12px` inside a 116px circle), waving hello and settling to idle.
class _SplashLenz extends StatelessWidget {
  const _SplashLenz({required this.size, required this.t});

  final double size;
  final ValueNotifier<double> t;

  @override
  Widget build(BuildContext context) {
    final width = size * 140 / 116;
    final k = width / 140;
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: width,
      maxWidth: width,
      maxHeight: double.infinity,
      child: Transform.translate(
        offset: Offset(-12 * k, -8 * k),
        child: SizedBox(
          width: width,
          child: ValueListenableBuilder<double>(
            valueListenable: t,
            builder: (context, v, _) => LenzCharacter(
              mood: v < 2.4 ? LenzMood.hello : LenzMood.idle,
              view: LenzView.peek,
              fx: false,
              interactive: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashTitle extends StatelessWidget {
  const _SplashTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Lenz',
            style: TextStyle(
              fontFamily: LenzText.family,
              fontWeight: FontWeight.w900,
              fontSize: 50,
              letterSpacing: -.045 * 50,
              height: 1,
              color: LenzColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: LenzColors.mint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'REAL OR FAKE DETECTOR',
              maxLines: 1,
              style: TextStyle(
                fontFamily: LenzText.family,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: .12 * 12,
                color: LenzColors.forest,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// CSS `border:5px solid transparent; border-top-color:#122F24;
/// border-right-color:rgba(18,47,36,.3)` on a circle: a solid top quarter and
/// a faint right quarter.
class _SplashRingPainter extends CustomPainter {
  const _SplashRingPainter();

  static const double _w = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_w / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _w;
    canvas.drawArc(
      rect,
      -math.pi * 3 / 4,
      math.pi / 2,
      false,
      p..color = LenzColors.forest,
    );
    canvas.drawArc(
      rect,
      -math.pi / 4,
      math.pi / 2,
      false,
      p..color = LenzColors.forest.withValues(alpha: .3),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashRingPainter oldDelegate) => false;
}
