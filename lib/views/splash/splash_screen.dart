import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Branded cold-start splash: circular app icon with an orbiting loading
/// ring, followed by the "Lenz" wordmark and the "REAL OR FAKE DETECTOR"
/// badge.
///
/// The icon sits at the exact screen center at 132pt - the same size and
/// position as the native iOS/Android launch image - so the hand-off from
/// the OS launch screen to Flutter is seamless; everything else animates in
/// around it.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const double iconSize = 132;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const Color _mint = Color(0xFFD6E8DE);
  static const double _ringSize = SplashScreen.iconSize + 28;

  late final AnimationController _entry;
  late final AnimationController _spin;
  late final AnimationController _pulse;

  late final Animation<double> _ringOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleSlide;
  late final Animation<double> _badgeOpacity;
  late final Animation<double> _badgeSlide;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..forward();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);

    _ringOpacity = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _titleOpacity = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.15, 0.60, curve: Curves.easeOut),
    );
    _titleSlide = Tween<double>(begin: 14, end: 0).animate(
      CurvedAnimation(parent: _entry, curve: const Interval(0.15, 0.60, curve: Curves.easeOutCubic)),
    );
    _badgeOpacity = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
    );
    _badgeSlide = Tween<double>(begin: 14, end: 0).animate(
      CurvedAnimation(parent: _entry, curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic)),
    );
  }

  @override
  void dispose() {
    _entry.dispose();
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final centerY = constraints.maxHeight / 2;
          return Stack(
            children: [
              // Soft mint glow behind the icon, breathing slowly.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 0.55 + 0.06 * _pulse.value,
                        colors: [
                          _mint.withValues(alpha: 0.55 * _ringOpacity.value),
                          AppColors.warmIvory.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Icon + orbiting loading ring, pinned to the exact center.
              Center(
                child: SizedBox(
                  width: _ringSize,
                  height: _ringSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FadeTransition(
                        opacity: _ringOpacity,
                        child: RotationTransition(
                          turns: _spin,
                          child: const CustomPaint(
                            size: Size.square(_ringSize),
                            painter: _OrbitRingPainter(),
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: Listenable.merge([_pulse, _ringOpacity]),
                        builder: (context, child) => DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.deepForestGreen
                                    .withValues(alpha: (0.10 + 0.08 * _pulse.value) * _ringOpacity.value),
                                blurRadius: 28,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: child,
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/app_icon_circle.png',
                            width: SplashScreen.iconSize,
                            height: SplashScreen.iconSize,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Wordmark + badge, below the ring.
              Positioned(
                left: 24,
                right: 24,
                top: centerY + _ringSize / 2 + 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _entry,
                      builder: (context, child) => Opacity(
                        opacity: _titleOpacity.value,
                        child: Transform.translate(offset: Offset(0, _titleSlide.value), child: child),
                      ),
                      child: const Text(
                        'Lenz',
                        style: TextStyle(
                          color: AppColors.nearBlack,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.0,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedBuilder(
                      animation: _entry,
                      builder: (context, child) => Opacity(
                        opacity: _badgeOpacity.value,
                        child: Transform.translate(offset: Offset(0, _badgeSlide.value), child: child),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _mint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'REAL OR FAKE DETECTOR',
                          style: TextStyle(
                            color: AppColors.deepForestGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A faint full track plus a bright comet-tail arc that fades from
/// transparent to deep forest green; rotated externally to read as loading.
class _OrbitRingPainter extends CustomPainter {
  const _OrbitRingPainter();

  static const double _stroke = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(_stroke / 2);

    canvas.drawCircle(
      rect.center,
      arcRect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = AppColors.deepForestGreen.withValues(alpha: 0.08),
    );

    const sweep = math.pi * 1.35;
    canvas.drawArc(
      arcRect,
      0,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          endAngle: sweep,
          colors: [
            AppColors.deepForestGreen.withValues(alpha: 0),
            AppColors.deepForestGreen,
          ],
        ).createShader(arcRect),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter oldDelegate) => false;
}
