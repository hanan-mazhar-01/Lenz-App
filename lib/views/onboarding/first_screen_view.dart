import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../services/haptics.dart';

/// First screen (Welcome Hero & Character-Driven Onboarding)
/// Features a staged, cinematic entrance, living character micro-movements,
/// and iOS-grade tactile interactions.
class FirstScreenView extends StatefulWidget {
  final VoidCallback? onGetStarted;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;

  const FirstScreenView({
    super.key,
    this.onGetStarted,
    this.onSkip,
    this.onBack,
  });

  @override
  State<FirstScreenView> createState() => _FirstScreenViewState();
}

class _FirstScreenViewState extends State<FirstScreenView>
    with TickerProviderStateMixin {
  // 1. Staged Master Entry Controller (1500ms)
  late final AnimationController _entryController;

  // Character entrance (150ms - 800ms)
  late final Animation<double> _characterOpacity;
  late final Animation<double> _characterScale;
  late final Animation<double> _characterSlide;

  // "Lenz" label (300ms - 550ms)
  late final Animation<double> _lenzTagOpacity;
  late final Animation<double> _lenzTagSlide;

  // "REAL OR FAKE DETECTOR" badge (370ms - 620ms)
  late final Animation<double> _detectorBadgeOpacity;
  late final Animation<double> _detectorBadgeSlide;

  // Headline (450ms - 750ms)
  late final Animation<double> _headlineOpacity;
  late final Animation<double> _headlineSlide;

  // Feature cards staggered (850ms - 1500ms)
  late final Animation<double> _card1Opacity;
  late final Animation<double> _card1Slide;
  late final Animation<double> _card1Scale;

  late final Animation<double> _card2Opacity;
  late final Animation<double> _card2Slide;
  late final Animation<double> _card2Scale;

  late final Animation<double> _card3Opacity;
  late final Animation<double> _card3Slide;
  late final Animation<double> _card3Scale;

  // Quote Card (1100ms - 1350ms)
  late final Animation<double> _quoteOpacity;
  late final Animation<double> _quoteSlide;

  // "Get Started" CTA (1250ms - 1500ms)
  late final Animation<double> _btnOpacity;
  late final Animation<double> _btnScale;
  late final Animation<double> _btnSlide;

  // 2. Button Single Breathing Highlight Controller (runs once after entry)
  late final AnimationController _btnHighlightController;
  late final Animation<double> _btnHighlightAnim;

  // 3. Subtle Character Ambient / Breathing Controller (3000ms loop)
  late final AnimationController _characterIdleController;
  late final Animation<double> _characterBreatheAnim;

  // 4. Character Tap Micro-Reaction Controller (500ms one-shot)
  late final AnimationController _characterTapController;
  late final Animation<double> _characterTapTiltAnim;
  late final Animation<double> _characterTapScaleAnim;

  @override
  void initState() {
    super.initState();

    // --- 1. Staged Entrance Sequence ---
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Subtle custom back curve: small gentle overshoot (~8%)
    const subtleBackCurve = Cubic(0.2, 0.9, 0.35, 1.08);

    // Character entrance: 150ms - 800ms (0.10 -> 0.533)
    _characterOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.10, 0.48, curve: Curves.easeOut),
    );
    _characterScale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.10, 0.533, curve: subtleBackCurve),
      ),
    );
    _characterSlide = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.10, 0.533, curve: Curves.easeOutCubic),
      ),
    );

    // "Lenz" label: 300ms - 550ms (0.20 -> 0.366)
    _lenzTagOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.20, 0.366, curve: Curves.easeOut),
    );
    _lenzTagSlide = Tween<double>(begin: -15.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.20, 0.366, curve: Curves.easeOutCubic),
      ),
    );

    // "REAL OR FAKE DETECTOR" badge: 370ms - 620ms (0.247 -> 0.413)
    _detectorBadgeOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.247, 0.413, curve: Curves.easeOut),
    );
    _detectorBadgeSlide = Tween<double>(begin: -15.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.247, 0.413, curve: Curves.easeOutCubic),
      ),
    );

    // Main headline: 450ms - 750ms (0.30 -> 0.50)
    _headlineOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.30, 0.50, curve: Curves.easeOut),
    );
    _headlineSlide = Tween<double>(begin: 18.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.30, 0.50, curve: Curves.easeOutCubic),
      ),
    );

    // Card 1: 850ms - 1300ms (0.567 -> 0.867)
    _card1Opacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.567, 0.82, curve: Curves.easeOut),
    );
    _card1Slide = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.567, 0.867, curve: Curves.easeOutCubic),
      ),
    );
    _card1Scale = Tween<double>(begin: 0.98, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.567, 0.867, curve: Curves.easeOutCubic),
      ),
    );

    // Card 2: 950ms - 1400ms (0.633 -> 0.933)
    _card2Opacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.633, 0.88, curve: Curves.easeOut),
    );
    _card2Slide = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.633, 0.933, curve: Curves.easeOutCubic),
      ),
    );
    _card2Scale = Tween<double>(begin: 0.98, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.633, 0.933, curve: Curves.easeOutCubic),
      ),
    );

    // Card 3: 1050ms - 1500ms (0.70 -> 1.0)
    _card3Opacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.70, 0.94, curve: Curves.easeOut),
    );
    _card3Slide = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.70, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _card3Scale = Tween<double>(begin: 0.98, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.70, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    // Quote Card: 1100ms - 1350ms (0.733 -> 0.90)
    _quoteOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.733, 0.90, curve: Curves.easeOut),
    );
    _quoteSlide = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.733, 0.90, curve: Curves.easeOutCubic),
      ),
    );

    // "Get Started" CTA: 1250ms - 1500ms (0.833 -> 1.0)
    _btnOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.833, 0.98, curve: Curves.easeOut),
    );
    _btnScale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.833, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _btnSlide = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.833, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    // --- 2. Button Single Breathing Highlight Sequence ---
    _btnHighlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _btnHighlightAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_btnHighlightController);

    // Trigger single highlight once entry completes
    _entryController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _btnHighlightController.forward();
          }
        });
      }
    });

    // --- 3. Subtle Character Ambient / Breathing ---
    _characterIdleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _characterBreatheAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _characterIdleController,
        curve: Curves.easeInOutSine,
      ),
    );

    // --- 4. Character Tap Micro-Reaction Sequence ---
    _characterTapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _characterTapTiltAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -0.04)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.04, end: 0.015)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.015, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
    ]).animate(_characterTapController);

    _characterTapScaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.04)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.04, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 60,
      ),
    ]).animate(_characterTapController);

    // Start staged entry
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _btnHighlightController.dispose();
    _characterIdleController.dispose();
    _characterTapController.dispose();
    super.dispose();
  }

  void _onMascotTap() {
    Haptics.lightImpact();
    if (!_characterTapController.isAnimating) {
      _characterTapController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      _entryController.value = 1.0;
    }

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clean luxury top spacing
              // Hero section with centered circular portrait and copy
              _buildHeroSection(),

              const SizedBox(height: 16),

              // Three Guided Feature Cards with reference icons
              _buildAnimatedCard(
                opacity: _card1Opacity,
                slide: _card1Slide,
                scale: _card1Scale,
                icon: CupertinoIcons.camera,
                title: '5 guided angle shots',
                subtitle: 'Macro cues for alignment & grain',
              ),
              const SizedBox(height: 10),

              _buildAnimatedCard(
                opacity: _card2Opacity,
                slide: _card2Slide,
                scale: _card2Scale,
                icon: CupertinoIcons.slider_horizontal_3,
                title: 'Specific point-by-point breakdown',
                subtitle: 'Stitching, fonts, and heat-stamped tags',
              ),
              const SizedBox(height: 10),

              _buildAnimatedCard(
                opacity: _card3Opacity,
                slide: _card3Slide,
                scale: _card3Scale,
                icon: CupertinoIcons.stopwatch,
                title: 'Plain-language verdict in 30 seconds',
                subtitle: 'A clear AI-assisted read, without technical jargon',
              ),

              const SizedBox(height: 10),

              // Lenz Quote Card (COMPLETELY UNTOUCHED AS REQUESTED)
              AnimatedBuilder(
                animation: _quoteSlide,
                builder: (context, child) {
                  return Opacity(
                    opacity: _quoteOpacity.value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, _quoteSlide.value),
                      child: child,
                    ),
                  );
                },
                child: _buildQuoteCard(),
              ),

              const SizedBox(height: 18),

              // Primary Get Started CTA with staged scale & single breathing highlight
              AnimatedBuilder(
                animation: Listenable.merge([_btnSlide, _btnHighlightAnim]),
                builder: (context, child) {
                  final highlightScale = 1.0 + (_btnHighlightAnim.value * 0.015);
                  final scale = _btnScale.value * highlightScale;

                  return Opacity(
                    opacity: _btnOpacity.value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, _btnSlide.value),
                      child: Transform.scale(
                        scale: scale,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _buildGetStartedButton(context),
              ),

              const SizedBox(height: 14),

              // "Already have an account? Log in" row
              AnimatedBuilder(
                animation: _btnSlide,
                builder: (context, child) {
                  return Opacity(
                    opacity: _btnOpacity.value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, _btnSlide.value * 0.5),
                      child: child,
                    ),
                  );
                },
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      Haptics.lightImpact();
                      widget.onSkip?.call();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      child: RichText(
                        text: TextSpan(
                          style: AppTypography.captionMedium.copyWith(
                            color: AppColors.charcoalGray,
                            fontSize: 13,
                          ),
                          children: [
                            const TextSpan(text: 'Already have an account? '),
                            TextSpan(
                              text: 'Log in',
                              style: TextStyle(
                                color: AppColors.deepForestGreen,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.deepForestGreen
                                    .withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'AI-assisted opinion, not an official brand authentication.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, color: AppColors.softGray),
                ),
              ),

              // Bottom safe area spacing
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  // --- Hero Section (Character & Centered Editorial Copy) ---
  Widget _buildHeroSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 8),

        // 1. Centered Character Mascot (with breathing and tap animations)
        Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _characterSlide,
              _characterBreatheAnim,
              _characterTapController,
            ]),
            builder: (context, child) {
              final breathT = _characterBreatheAnim.value;
              final floatY = math.sin(breathT * math.pi) * 1.5;
              final breathScale = 0.995 + (breathT * 0.01);
              final tapScale = _characterTapScaleAnim.value;
              final tapTilt = _characterTapTiltAnim.value;

              final currentScale = _characterScale.value * breathScale * tapScale;
              final currentTranslateY = _characterSlide.value - floatY;

              return Opacity(
                opacity: _characterOpacity.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, currentTranslateY),
                  child: Transform.rotate(
                    angle: tapTilt,
                    child: Transform.scale(
                      scale: currentScale,
                      child: GestureDetector(
                        onTap: _onMascotTap,
                        behavior: HitTestBehavior.opaque,
                        child: Image.asset(
                          'assets/images/mascot_welcome.png',
                          height: 205,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // 2. Identity Row: Lenz + REAL OR FAKE DETECTOR
        AnimatedBuilder(
          animation: _lenzTagSlide,
          builder: (context, child) {
            return Opacity(
              opacity: _lenzTagOpacity.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(_lenzTagSlide.value, 0),
                child: child,
              ),
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Lenz',
                style: TextStyle(
                  color: AppColors.nearBlack,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: _detectorBadgeSlide,
                builder: (context, child) {
                  return Opacity(
                    opacity: _detectorBadgeOpacity.value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(_detectorBadgeSlide.value, 0),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6E8DE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'REAL OR FAKE DETECTOR',
                    style: TextStyle(
                      color: AppColors.deepForestGreen,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 3. Main Headline
        AnimatedBuilder(
          animation: _headlineSlide,
          builder: (context, child) {
            return Opacity(
              opacity: _headlineOpacity.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, _headlineSlide.value),
                child: child,
              ),
            );
          },
          child: const Text(
            'Spot the fakes before you\nspend.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.nearBlack,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ],
    );
  }

  // --- Animated Feature Card with Staggered Entrance & Tactile Feedback ---
  Widget _buildAnimatedCard({
    required Animation<double> opacity,
    required Animation<double> slide,
    required Animation<double> scale,
    IconData? icon,
    String? imagePath,
    required String title,
    required String subtitle,
  }) {
    return AnimatedBuilder(
      animation: slide,
      builder: (context, child) {
        return Opacity(
          opacity: opacity.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, slide.value),
            child: Transform.scale(
              scale: scale.value,
              child: child,
            ),
          ),
        );
      },
      child: _InteractiveFeatureCard(
        icon: icon,
        imagePath: imagePath,
        title: title,
        subtitle: subtitle,
      ),
    );
  }

  // --- Lenz Quote Card ---
  Widget _buildQuoteCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.veryLightWarmGray,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E2DD), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Lenz Avatar
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 44,
              height: 44,
              color: AppColors.softWarmGray,
              child: Image.asset(
                'assets/images/onboarding_lenz_avatar.png',
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/images/mascot_home.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Quote Copy & Signature
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '“Never trust an auction house screenshot alone. Send me clean light, and we\'ll crack the case together.”',
                  style: AppTypography.caption.copyWith(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                    color: AppColors.charcoalGray,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '— Lenz',
                  style: AppTypography.captionMedium.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.softGray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Primary Action Button (Get Started →) with One-Time Breathing Highlight ---
  Widget _buildGetStartedButton(BuildContext context) {
    return BounceButton(
      onTap: () {
        Haptics.mediumImpact();
        widget.onGetStarted?.call();
      },
      child: AnimatedBuilder(
        animation: _btnHighlightAnim,
        builder: (context, child) {
          final highlightOpacity = _btnHighlightAnim.value * 0.25;

          return Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.deepForestGreen,
              borderRadius: BorderRadius.circular(27),
              boxShadow: [
                BoxShadow(
                  color: AppColors.deepForestGreen.withOpacity(
                    0.35 + (_btnHighlightAnim.value * 0.15),
                  ),
                  blurRadius: 14 + (_btnHighlightAnim.value * 6),
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Subtle single breathing highlight overlay
                if (highlightOpacity > 0.01)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(27),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.0),
                            Colors.white.withOpacity(highlightOpacity),
                            Colors.white.withOpacity(0.0),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),

                // Button Content
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Get Started',
                      style: AppTypography.callout.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.pureWhite,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      CupertinoIcons.arrow_right,
                      size: 16,
                      color: AppColors.pureWhite,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Interactive feature card providing smooth iOS-grade tactile feedback
class _InteractiveFeatureCard extends StatefulWidget {
  final IconData? icon;
  final String? imagePath;
  final String title;
  final String subtitle;

  const _InteractiveFeatureCard({
    this.icon,
    this.imagePath,
    required this.title,
    required this.subtitle,
  });

  @override
  State<_InteractiveFeatureCard> createState() =>
      _InteractiveFeatureCardState();
}

class _InteractiveFeatureCardState extends State<_InteractiveFeatureCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.veryLightWarmGray,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isPressed
                  ? AppColors.deepForestGreen.withOpacity(0.2)
                  : const Color(0xFFECE7E3),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0x06000000),
                blurRadius: _isPressed ? 3 : 8,
                offset: Offset(0, _isPressed ? 1 : 2),
              ),
            ],
          ),
          child: Row(
            children: [
              if (widget.icon != null)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E3DF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 21,
                    color: AppColors.nearBlack,
                  ),
                )
              else if (widget.imagePath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 44,
                    height: 44,
                    color: AppColors.softWarmGray,
                    child: Image.asset(
                      widget.imagePath!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

              const SizedBox(width: 14),

              // Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: AppTypography.titleMedium.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.nearBlack,
                      ),
                    ),
                    const SizedBox(height: 2.5),
                    Text(
                      widget.subtitle,
                      style: AppTypography.caption.copyWith(
                        fontSize: 11.5,
                        color: AppColors.charcoalGray,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
