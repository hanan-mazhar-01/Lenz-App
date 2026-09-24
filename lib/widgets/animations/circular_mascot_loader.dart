import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Luxury circular loading ring that surrounds the Detective Mascot.
/// Displays:
/// - Smooth rotating gradient scanner arc with an illuminated head dot
/// - Ambient breathing radar ripples
/// - High-tech sweeping laser scan lines & light wash across the character
class CircularMascotLoader extends StatefulWidget {
  final Widget child;
  final double size;
  final double strokeWidth;
  final bool showScanLines;
  final Color? accentColor;
  final Color? glowColor;

  const CircularMascotLoader({
    super.key,
    required this.child,
    this.size = 175.0,
    this.strokeWidth = 3.5,
    this.showScanLines = true,
    this.accentColor,
    this.glowColor,
  });

  @override
  State<CircularMascotLoader> createState() => _CircularMascotLoaderState();
}

class _CircularMascotLoaderState extends State<CircularMascotLoader>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _pulseController;
  late final AnimationController _scanLineController;

  late final Animation<double> _pulseAnimation;
  late final Animation<double> _radarWaveAnimation;
  late final Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Continuous smooth 360-degree rotation (2.2s per revolution)
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    // 2. Breathing / radar expansion effect
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _radarWaveAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOutQuad,
    );

    // 3. Sweeping laser scan line across the character (1.6s back & forth)
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _scanLineAnimation = Tween<double>(begin: 0.08, end: 0.92).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    _pulseController.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Color effectiveAccent =
        widget.accentColor ?? AppColors.accentOf(context);
    final Color effectiveGlow =
        widget.glowColor ?? const Color(0xFF2EA44F); // Fresh emerald accent
    final Color surfaceColor = AppColors.surfaceOf(context);

    final double innerSize = widget.size - (widget.strokeWidth * 2) - 8;

    return SizedBox(
      width: widget.size + 36,
      height: widget.size + 36,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // ─── Layer 1: Outward Pulsing Radar Waves ───
          if (!reduceMotion)
            AnimatedBuilder(
              animation: _radarWaveAnimation,
              builder: (context, _) {
                final double progress = _radarWaveAnimation.value;
                final double currentSize = widget.size + (30 * progress);
                final double opacity = (1.0 - progress).clamp(0.0, 1.0) * 0.28;

                return Container(
                  width: currentSize,
                  height: currentSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: effectiveAccent.withOpacity(opacity),
                      width: 1.5,
                    ),
                  ),
                );
              },
            ),

          // ─── Layer 2: Ambient Soft Glow Disc ───
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) {
              final double scale = reduceMotion ? 1.0 : _pulseAnimation.value;
              return Container(
                width: widget.size * 0.94 * scale,
                height: widget.size * 0.94 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: effectiveAccent.withOpacity(0.08),
                      blurRadius: 28,
                      spreadRadius: 6,
                    ),
                    BoxShadow(
                      color: effectiveGlow.withOpacity(0.06),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              );
            },
          ),

          // ─── Layer 3: Inner Surface Disc Behind Character ───
          Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: surfaceColor,
              border: Border.all(
                color: effectiveAccent.withOpacity(0.06),
                width: 1.0,
              ),
            ),
          ),

          // ─── Layer 4: Static Track Ring ───
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: effectiveAccent.withOpacity(0.12),
                  width: widget.strokeWidth,
                ),
              ),
            ),
          ),

          // ─── Layer 5: Rotating Scanning Arc & Glowing Head ───
          if (!reduceMotion)
            AnimatedBuilder(
              animation: _spinController,
              builder: (context, _) {
                return CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _CircularScannerPainter(
                    progress: _spinController.value,
                    accentColor: effectiveAccent,
                    glowColor: effectiveGlow,
                    strokeWidth: widget.strokeWidth,
                  ),
                );
              },
            )
          else
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _CircularScannerPainter(
                progress: 0.25,
                accentColor: effectiveAccent,
                glowColor: effectiveGlow,
                strokeWidth: widget.strokeWidth,
              ),
            ),

          // ─── Layer 6: Character + Sweeping Laser Scan Lines ───
          SizedBox(
            width: innerSize,
            height: innerSize,
            child: ClipOval(
              child: Stack(
                alignment: Alignment.center,
                fit: StackFit.expand,
                children: [
                  // The Detective Mascot
                  Center(child: widget.child),

                  // Subtle horizontal scan lines grid
                  if (widget.showScanLines)
                    CustomPaint(
                      painter: _ScanGridPainter(
                        color: effectiveAccent.withOpacity(0.05),
                      ),
                    ),

                  // Sweeping laser scan line + light trail over character
                  if (widget.showScanLines && !reduceMotion)
                    AnimatedBuilder(
                      animation: _scanLineAnimation,
                      builder: (context, _) {
                        final double yPos = _scanLineAnimation.value * innerSize;
                        final bool movingDown =
                            _scanLineController.status == AnimationStatus.forward;

                        return Stack(
                          children: [
                            // Laser light wash trail
                            Positioned(
                              top: movingDown
                                  ? (yPos - 26).clamp(0.0, innerSize)
                                  : yPos,
                              left: 0,
                              right: 0,
                              height: 26,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: movingDown
                                        ? Alignment.topCenter
                                        : Alignment.bottomCenter,
                                    end: movingDown
                                        ? Alignment.bottomCenter
                                        : Alignment.topCenter,
                                    colors: [
                                      effectiveGlow.withOpacity(0.0),
                                      effectiveGlow.withOpacity(0.14),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Bright Glowing Laser Scan Line
                            Positioned(
                              top: yPos,
                              left: 6,
                              right: 6,
                              child: Container(
                                height: 2.2,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  gradient: LinearGradient(
                                    colors: [
                                      effectiveGlow.withOpacity(0.0),
                                      effectiveGlow.withOpacity(0.65),
                                      Colors.white,
                                      effectiveGlow,
                                      effectiveGlow.withOpacity(0.0),
                                    ],
                                    stops: const [0.0, 0.22, 0.5, 0.78, 1.0],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: effectiveGlow.withOpacity(0.75),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for forensic horizontal scanlines
class _ScanGridPainter extends CustomPainter {
  final Color color;

  const _ScanGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    for (double y = 5.0; y < size.height; y += 8.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Custom painter that renders a smooth gradient arc with rounded ends
/// and an illuminated scanner head dot.
class _CircularScannerPainter extends CustomPainter {
  final double progress;
  final Color accentColor;
  final Color glowColor;
  final double strokeWidth;

  const _CircularScannerPainter({
    required this.progress,
    required this.accentColor,
    required this.glowColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = (size.width - strokeWidth) / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final double startAngle = (progress * 2 * math.pi);
    // Main scanning arc spans ~140 degrees (2.44 radians)
    const double sweepAngle = 2.45;

    // 1. Main Gradient Arc
    final Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: sweepAngle,
        colors: [
          accentColor.withOpacity(0.0),
          accentColor.withOpacity(0.40),
          accentColor,
        ],
        stops: const [0.0, 0.45, 1.0],
        transform: GradientRotation(startAngle),
      ).createShader(rect);

    canvas.drawArc(rect, startAngle, sweepAngle, false, arcPaint);

    // 2. Secondary subtle counter-arc (gives sophisticated radar symmetry)
    const double secondarySweepAngle = 1.05;
    final double secondaryStartAngle = startAngle + math.pi;

    final Paint secondaryArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.75
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: secondarySweepAngle,
        colors: [
          accentColor.withOpacity(0.0),
          accentColor.withOpacity(0.25),
        ],
        stops: const [0.0, 1.0],
        transform: GradientRotation(secondaryStartAngle),
      ).createShader(rect);

    canvas.drawArc(
      rect,
      secondaryStartAngle,
      secondarySweepAngle,
      false,
      secondaryArcPaint,
    );

    // 3. Glowing Scanner Head Dot at the front tip of the main arc
    final double headAngle = startAngle + sweepAngle;
    final double headX = center.dx + radius * math.cos(headAngle);
    final double headY = center.dy + radius * math.sin(headAngle);
    final Offset headOffset = Offset(headX, headY);

    // Glow halo behind the dot
    final Paint glowPaint = Paint()
      ..color = glowColor.withOpacity(0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(headOffset, strokeWidth * 1.5, glowPaint);

    // Solid bright core dot
    final Paint dotPaint = Paint()..color = glowColor;
    canvas.drawCircle(headOffset, strokeWidth * 0.9, dotPaint);

    // Tiny white focal spark in center of dot
    final Paint sparkPaint = Paint()..color = Colors.white.withOpacity(0.9);
    canvas.drawCircle(headOffset, strokeWidth * 0.4, sparkPaint);
  }

  @override
  bool shouldRepaint(covariant _CircularScannerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
