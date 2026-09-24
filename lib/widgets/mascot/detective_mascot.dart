import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum DetectiveMascotState {
  idle,
  curious,
  scanning,
  capturing,
  inspecting,
  thinking,
  discovering,
  success,
  suspicious,
  inconclusive,
  teaching,
}

/// Production-ready signature Detective Mascot component.
/// Supports 10 reactive investigation states, subtle optical halo,
/// and the choreographed "Detective Glance" animation.
class DetectiveMascot extends StatefulWidget {
  final DetectiveMascotState state;
  final double size;
  final bool showHalo;
  final bool triggerGlance;
  final VoidCallback? onTap;

  const DetectiveMascot({
    super.key,
    this.state = DetectiveMascotState.idle,
    this.size = 110,
    this.showHalo = false,
    this.triggerGlance = false,
    this.onTap,
  });

  @override
  State<DetectiveMascot> createState() => _DetectiveMascotState();
}

class _DetectiveMascotState extends State<DetectiveMascot>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _glanceController;

  late final Animation<double> _breathAnim;
  late final Animation<double> _tiltAnim;
  late final Animation<double> _glanceHeadTurn;
  late final Animation<double> _glanceLensZoom;
  late final Animation<double> _scanSweep;

  @override
  void initState() {
    super.initState();

    // 1. Subtle rhythmic breathing
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    _breathAnim = Tween<double>(begin: 0.985, end: 1.015).animate(
      CurvedAnimation(parent: _idleController, curve: Curves.easeInOutSine),
    );

    _tiltAnim = Tween<double>(begin: -0.015, end: 0.015).animate(
      CurvedAnimation(parent: _idleController, curve: Curves.easeInOutSine),
    );

    // 2. Signature "Detective Glance" animation controller (1.8s sequence)
    _glanceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Step 1-3: Notice item & slight head turn
    _glanceHeadTurn = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: -0.08).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 25),
      TweenSequenceItem(tween: Tween<double>(begin: -0.08, end: -0.08), weight: 35),
      TweenSequenceItem(tween: Tween<double>(begin: -0.08, end: 0.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 40),
    ]).animate(_glanceController);

    // Step 4-5: Magnifying glass forward & focus
    _glanceLensZoom = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.06).chain(CurveTween(curve: Curves.easeOutBack)), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.06, end: 1.06), weight: 35),
      TweenSequenceItem(tween: Tween<double>(begin: 1.06, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 35),
    ]).animate(_glanceController);

    // Step 6: Subtle scanning glint
    _scanSweep = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _glanceController,
        curve: const Interval(0.25, 0.75, curve: Curves.easeInOut),
      ),
    );

    if (widget.triggerGlance) {
      _glanceController.repeat(reverse: false, period: const Duration(milliseconds: 3200));
    }
  }

  @override
  void didUpdateWidget(covariant DetectiveMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.triggerGlance && !_glanceController.isAnimating) {
      _glanceController.repeat(reverse: false, period: const Duration(milliseconds: 3200));
    } else if (!widget.triggerGlance && _glanceController.isAnimating) {
      _glanceController.stop();
      _glanceController.reset();
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _glanceController.dispose();
    super.dispose();
  }

  String _resolveAssetPath() {
    switch (widget.state) {
      case DetectiveMascotState.inspecting:
      case DetectiveMascotState.thinking:
        return 'assets/images/mascot_inspecting.png';
      case DetectiveMascotState.discovering:
      case DetectiveMascotState.scanning:
        return 'assets/images/mascot_identifying.png';
      case DetectiveMascotState.capturing:
      case DetectiveMascotState.curious:
        return 'assets/images/mascot_ready.png';
      case DetectiveMascotState.teaching:
        return 'assets/images/mascot_tip.png';
      case DetectiveMascotState.success:
      case DetectiveMascotState.suspicious:
      case DetectiveMascotState.inconclusive:
      case DetectiveMascotState.idle:
        return widget.size < 75
            ? 'assets/images/mascot_home.png'
            : 'assets/images/mascot_welcome.png';
    }
  }

  Color _getBadgeAccentColor() {
    switch (widget.state) {
      case DetectiveMascotState.success:
        return AppColors.accent;
      case DetectiveMascotState.suspicious:
        return AppColors.danger;
      case DetectiveMascotState.inconclusive:
      case DetectiveMascotState.thinking:
        return AppColors.warning;
      case DetectiveMascotState.discovering:
      case DetectiveMascotState.scanning:
      case DetectiveMascotState.curious:
      case DetectiveMascotState.capturing:
      case DetectiveMascotState.inspecting:
      case DetectiveMascotState.teaching:
      case DetectiveMascotState.idle:
        return AppColors.accent;
    }
  }

  double _getStaticTilt() {
    switch (widget.state) {
      case DetectiveMascotState.curious:
        return 0.06;
      case DetectiveMascotState.scanning:
        return -0.04;
      case DetectiveMascotState.inspecting:
        return -0.05;
      case DetectiveMascotState.thinking:
        return 0.04;
      case DetectiveMascotState.suspicious:
        return -0.04;
      case DetectiveMascotState.inconclusive:
        return -0.03;
      default:
        return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final assetPath = _resolveAssetPath();
    final accentColor = _getBadgeAccentColor();

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idleController, _glanceController]),
          builder: (context, child) {
            final double breathScale = reduceMotion ? 1.0 : _breathAnim.value;
            final double glanceScale = reduceMotion ? 1.0 : _glanceLensZoom.value;
            final double totalScale = breathScale * glanceScale;

            final double idleTilt = reduceMotion ? 0.0 : _tiltAnim.value;
            final double glanceTilt = reduceMotion ? 0.0 : _glanceHeadTurn.value;
            final double totalTilt = _getStaticTilt() + idleTilt + glanceTilt;

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // 1. Optical Ambient Glow Halo
                if (widget.showHalo)
                  Container(
                    width: widget.size * 0.92,
                    height: widget.size * 0.92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.20),
                          blurRadius: widget.size * 0.28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),

                // 2. Animated Character Body
                Transform.scale(
                  scale: totalScale,
                  child: Transform.rotate(
                    angle: totalTilt,
                    child: Image.asset(
                      assetPath,
                      width: widget.size,
                      height: widget.size,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),

                // 3. Subtle Scanning Sweep Glint
                if (_glanceController.isAnimating && !reduceMotion)
                  Positioned.fill(
                    child: ClipOval(
                      child: Transform.rotate(
                        angle: math.pi / 4,
                        child: FractionallySizedBox(
                          widthFactor: 0.35,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                transform: GradientRotation(_scanSweep.value * math.pi),
                                colors: [
                                  Colors.white.withOpacity(0.0),
                                  Colors.white.withOpacity(0.25),
                                  Colors.white.withOpacity(0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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
