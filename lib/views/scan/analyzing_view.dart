import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/evidence.dart';
import '../../models/product.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/common/app_image.dart';

/// Screen displayed while authenticity analysis is in flight.
/// Matches the reference layout with animated circular scanner visualizer,
/// multi-step progress checklist, and privacy assurance footer.
class AnalyzingView extends StatefulWidget {
  final List<EvidenceItem> items;
  final Map<String, String> capturedImages;
  final Product? product;
  final VoidCallback? onBack;

  const AnalyzingView({
    super.key,
    required this.items,
    required this.capturedImages,
    this.product,
    this.onBack,
  });

  @override
  State<AnalyzingView> createState() => _AnalyzingViewState();
}

class _AnalyzingViewState extends State<AnalyzingView> with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _scanLineController;
  late final AnimationController _pulseController;

  int _currentStage = 0; // 0: Photo Inspection, 1: AI Analysis, 2: Authenticity Check, 3: Generating Result
  int _currentPhotoIndex = 0;
  Timer? _stageTimer;
  Timer? _photoCycleTimer;

  @override
  void initState() {
    super.initState();

    // 1. Spinning outer arc controller
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    // 2. Vertical scan sweep line controller
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // 3. Pulse dot controller
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Step progression animation timer
    _stageTimer = Timer.periodic(const Duration(milliseconds: 1800), (timer) {
      if (!mounted) return;
      if (_currentStage < 3) {
        setState(() => _currentStage++);
      }
    });

    // Image cycling timer (cycles through captured evidence photos)
    final imageList = widget.capturedImages.values.where((p) => p.isNotEmpty).toList();
    if (imageList.length > 1) {
      _photoCycleTimer = Timer.periodic(const Duration(milliseconds: 2400), (timer) {
        if (!mounted) return;
        setState(() {
          _currentPhotoIndex = (_currentPhotoIndex + 1) % imageList.length;
        });
      });
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _scanLineController.dispose();
    _pulseController.dispose();
    _stageTimer?.cancel();
    _photoCycleTimer?.cancel();
    super.dispose();
  }

  String _getStagePillText() {
    switch (_currentStage) {
      case 0:
        return 'Analyzing image...';
      case 1:
        return 'Analyzing features & materials...';
      case 2:
        return 'Checking authenticity benchmarks...';
      case 3:
      default:
        return 'Generating final report...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageList = widget.capturedImages.values.where((p) => p.isNotEmpty).toList();
    final activePhotoPath = imageList.isNotEmpty ? imageList[_currentPhotoIndex % imageList.length] : '';
    final submittedCount = widget.items.where((i) => widget.capturedImages.containsKey(i.id)).length;

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 8),

              // ─── 1. Top Bar: Back button, Title & Subtitle
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.onBack != null)
                    BounceButton(
                      onTap: widget.onBack!,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.veryLightWarmGray,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.nearBlack.withOpacity(0.06),
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            CupertinoIcons.chevron_back,
                            color: AppColors.nearBlack,
                            size: 18,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                  const Expanded(
                    child: Text(
                      'Analyzing',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.nearBlack,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),

              const SizedBox(height: 10),

              // Subtitle
              Text(
                widget.product != null
                    ? "Our AI is checking your ${widget.product!.name} for authenticity,\nit will only take a moment..."
                    : "Our AI is checking the image for authenticity,\nit will only take a moment...",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.charcoalGray,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 24),

              // ─── 2. Circular Scanner Visualizer
              Center(
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_rotationController, _scanLineController]),
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _AnalyzingScannerPainter(
                          rotation: _rotationController.value,
                          trackColor: const Color(0xFFDCE9E1),
                          arcColor: AppColors.deepForestGreen,
                        ),
                        child: Center(
                          child: Container(
                            width: 134,
                            height: 134,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.veryLightWarmGray,
                              border: Border.all(
                                color: const Color(0xFFE2ECE5),
                                width: 2,
                              ),
                            ),
                            child: ClipOval(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Photo being analyzed
                                  if (activePhotoPath.isNotEmpty)
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 500),
                                      child: AppImage(
                                        key: ValueKey(activePhotoPath),
                                        imagePath: activePhotoPath,
                                        width: 134,
                                        height: 134,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else
                                    Container(
                                      color: AppColors.softWarmGray,
                                      child: const Icon(
                                        CupertinoIcons.photo,
                                        size: 44,
                                        color: AppColors.softGray,
                                      ),
                                    ),

                                  // Semi-transparent dark wash for high tech scan contrast
                                  Container(
                                    color: Colors.black.withOpacity(0.12),
                                  ),

                                  // Subtle scanning grid overlay
                                  CustomPaint(
                                    painter: _ScannerGridPainter(),
                                  ),

                                  // Reticle corner brackets
                                  CustomPaint(
                                    painter: _ReticleCornersPainter(
                                      color: AppColors.deepForestGreen,
                                    ),
                                  ),

                                  // Sweeping laser scan line
                                  Positioned(
                                    top: _scanLineController.value * 134,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 2,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.deepForestGreen.withOpacity(0.0),
                                            AppColors.deepForestGreen.withOpacity(0.85),
                                            AppColors.deepForestGreen.withOpacity(0.0),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.deepForestGreen.withOpacity(0.6),
                                            blurRadius: 6,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ─── 3. Dynamic Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F2EC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFD2E6DB),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _pulseController,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.deepForestGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getStagePillText(),
                      style: const TextStyle(
                        color: AppColors.deepForestGreen,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ─── 4. Step-by-Step Status Card
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.veryLightWarmGray,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.nearBlack.withOpacity(0.06),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.nearBlack.withOpacity(0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStepRow(
                        stepIndex: 0,
                        icon: Icons.crop_free_rounded,
                        title: 'Photo Inspection',
                        subtitle: 'Checking $submittedCount submitted photo angles...',
                        isFirst: true,
                        isLast: false,
                      ),
                      _buildStepRow(
                        stepIndex: 1,
                        icon: Icons.psychology_outlined,
                        title: 'AI Analysis',
                        subtitle: 'Checking for replica flaws & materials...',
                        isFirst: false,
                        isLast: false,
                      ),
                      _buildStepRow(
                        stepIndex: 2,
                        icon: CupertinoIcons.shield_lefthalf_fill,
                        title: 'Authenticity Check',
                        subtitle: 'Scoring evidence against known construction patterns...',
                        isFirst: false,
                        isLast: false,
                      ),
                      _buildStepRow(
                        stepIndex: 3,
                        icon: Icons.article_outlined,
                        title: 'Generating Result',
                        subtitle: 'Almost there...',
                        isFirst: false,
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ─── 5. Privacy Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 1,
                    color: AppColors.nearBlack.withOpacity(0.12),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 15,
                      color: AppColors.deepForestGreen.withOpacity(0.85),
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 1,
                    color: AppColors.nearBlack.withOpacity(0.12),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'Your privacy is our priority',
                style: TextStyle(
                  color: AppColors.charcoalGray,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Single step row in the timeline card
  Widget _buildStepRow({
    required int stepIndex,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isFirst,
    required bool isLast,
  }) {
    final bool isCompleted = stepIndex < _currentStage;
    final bool isActive = stepIndex == _currentStage;

    final Color iconBg = isCompleted || isActive
        ? const Color(0xFFE2EDE6)
        : AppColors.softWarmGray;

    final Color iconColor = isCompleted || isActive
        ? AppColors.deepForestGreen
        : AppColors.softGray;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon circular badge
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(icon, size: 21, color: iconColor),
          ),
        ),

        const SizedBox(width: 14),

        // Title and subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isCompleted || isActive ? AppColors.nearBlack : AppColors.charcoalGray,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2.5),
              Text(
                subtitle,
                style: TextStyle(
                  color: isCompleted || isActive ? AppColors.charcoalGray : AppColors.softGray,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // Status indicator: Green check / spinner / empty circle
        if (isCompleted)
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppColors.deepForestGreen,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.check,
                color: Colors.white,
                size: 14,
              ),
            ),
          )
        else if (isActive)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.deepForestGreen),
            ),
          )
        else
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.nearBlack.withOpacity(0.18),
                width: 1.8,
              ),
            ),
          ),
      ],
    );
  }
}

/// Custom painter for the outer spinning scanner arc
class _AnalyzingScannerPainter extends CustomPainter {
  final double rotation;
  final Color trackColor;
  final Color arcColor;

  const _AnalyzingScannerPainter({
    required this.rotation,
    required this.trackColor,
    required this.arcColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Track circle
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawCircle(center, radius - 4, trackPaint);

    // Rotating active arc (~120 degrees)
    final arcPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round;

    final startAngle = rotation * 2 * math.pi;
    const sweepAngle = math.pi * 0.7; // ~126 degrees
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AnalyzingScannerPainter oldDelegate) {
    return oldDelegate.rotation != rotation;
  }
}

/// Painter for the subtle grid overlay inside the circular image
class _ScannerGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 0.8;

    const step = 16.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painter for the 4 corner reticles ([ ])
class _ReticleCornersPainter extends CustomPainter {
  final Color color;

  const _ReticleCornersPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final inset = size.width * 0.22;
    const len = 14.0;

    final l = inset;
    final r = size.width - inset;
    final t = inset;
    final b = size.height - inset;

    // Top-Left ┌
    canvas.drawLine(Offset(l, t + len), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + len, t), paint);

    // Top-Right ┐
    canvas.drawLine(Offset(r - len, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), paint);

    // Bottom-Left └
    canvas.drawLine(Offset(l, b - len), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l + len, b), paint);

    // Bottom-Right ┘
    canvas.drawLine(Offset(r - len, b), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
