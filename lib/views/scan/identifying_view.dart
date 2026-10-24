import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../viewmodels/scan_flow_viewmodel.dart';
import '../../widgets/camera/lenz_camera_chrome.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// Shows real request progress. The stages advance because the pipeline
/// advanced — there are no timed or decorative steps (§3).
///
/// Lenz layout (prototype `SCREENS.identify`): journey stepper at Identify,
/// a searching stage with Lenz inspecting, then the result card with the
/// identification's own match confidence.
class IdentifyingView extends StatelessWidget {
  final ScanLifecycleState scanState;
  final Product? product;
  final String? capturedImagePath;
  final int evidenceCount;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  const IdentifyingView({
    super.key,
    required this.scanState,
    required this.product,
    required this.onContinue,
    required this.onBack,
    this.capturedImagePath,
    this.evidenceCount = 0,
  });

  bool get _isIdentified => scanState == ScanLifecycleState.identified && product != null;

  bool get _hasPhoto => capturedImagePath != null && capturedImagePath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final stages = <_Stage>[
      _Stage(
        'Working out what this is',
        done: scanState != ScanLifecycleState.identifying,
        active: scanState == ScanLifecycleState.identifying,
      ),
      _Stage(
        'Working out which photos we need',
        done: _isIdentified,
        active: scanState == ScanLifecycleState.creatingEvidencePlan,
      ),
    ];

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: LenzMoodBackground(
        mood: _isIdentified ? const Color(0xFFCFEED6) : const Color(0xFFD9E4F6),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.of(context).padding.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LenzTopBar(
                  title: _isIdentified ? 'Item identified' : 'Identifying',
                  onBack: onBack,
                ),
                const LenzJourneyStepper(step: 1, rider: LenzJourneyRider()),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  switchInCurve: LenzMotion.ease,
                  child: _isIdentified ? _buildResult(context) : _buildSearching(context, stages),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ searching

  Widget _buildSearching(BuildContext context, List<_Stage> stages) {
    final planning = scanState == ScanLifecycleState.creatingEvidencePlan;
    final width = MediaQuery.of(context).size.width - 40;
    final circle = width < 300 ? 184.0 : 224.0;
    final lenzWidth = width < 300 ? 140.0 : 182.0;
    return Column(
      key: const ValueKey('searching'),
      children: [
        SizedBox(
          height: circle + 72,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: (width - circle) / 2,
                top: 10,
                width: circle,
                height: circle,
                child: _SearchDisc(
                  child: _hasPhoto
                      ? AppImage(imagePath: capturedImagePath!, fit: BoxFit.cover)
                      : const Center(
                          child: LenzIcon(LenzIcons.scan, size: 64, color: LenzColors.forest2),
                        ),
                ),
              ),
              Positioned(
                right: -10,
                top: circle * .5,
                width: lenzWidth,
                child: LenzCharacter(
                  mood: planning ? LenzMood.think : LenzMood.inspect,
                  view: LenzView.bust,
                ),
              ),
              Positioned(
                left: 0,
                top: circle * .67,
                child: LenzBubble(
                  text: planning
                      ? 'Working out which photos we need…'
                      : 'Working out what this is…',
                  maxWidth: 150,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('Identifying your item', textAlign: TextAlign.center, style: LenzText.title),
        const SizedBox(height: 6),
        Text('Looking at your photo...', textAlign: TextAlign.center, style: LenzText.sub),
        const SizedBox(height: 18),
        LenzCard(
          radius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              for (final s in stages)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: s.done
                            ? const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: LenzColors.leaf,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: LenzIcon(
                                    LenzIcons.check,
                                    size: 14,
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : s.active
                            ? const Padding(
                                padding: EdgeInsets.all(2),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: LenzColors.leaf,
                                ),
                              )
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: LenzColors.dotBorder, width: 3),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.label,
                          style: LenzText.item.copyWith(
                            fontSize: 14.5,
                            color: s.done || s.active ? LenzColors.ink : LenzColors.muted,
                            fontWeight: s.done || s.active ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- result

  Widget _buildResult(BuildContext context) {
    final p = product!;
    final confidence = p.identificationConfidence.clamp(0.0, 1.0);
    final pct = (confidence * 100).round();
    final (confLabel, confVariant) = confidence >= 0.75
        ? ('High confidence', LenzPillVariant.auth)
        : confidence >= 0.5
        ? ('Medium confidence', LenzPillVariant.mint)
        : ('Low confidence', LenzPillVariant.unsure);
    final low = p.identificationConfidence < 0.5;
    final showModel = p.model.isNotEmpty && p.model.toLowerCase() != p.name.toLowerCase();

    return LenzStagger(
      key: const ValueKey('result'),
      spacing: 14,
      children: [
        LenzCard(
          radius: 32,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  const LenzPill(label: 'Best match', icon: LenzIcons.sparkles),
                  LenzPill(label: confLabel, variant: confVariant),
                ],
              ),
              Container(
                width: 112,
                height: 112,
                margin: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                decoration: BoxDecoration(
                  color: LenzColors.mint2,
                  borderRadius: BorderRadius.circular(34),
                ),
                alignment: Alignment.center,
                child: _hasPhoto
                    ? AppImage(
                        imagePath: capturedImagePath!,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(24),
                        placeholder: Image.asset(
                          lenzCategoryArt(p.category),
                          width: 84,
                          height: 84,
                        ),
                      )
                    : Image.asset(lenzCategoryArt(p.category), width: 84, height: 84),
              ),
              Text(
                '${p.category.label} · ${p.brand}',
                textAlign: TextAlign.center,
                style: LenzText.cap.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                p.name,
                textAlign: TextAlign.center,
                style: LenzText.display.copyWith(fontSize: 30),
              ),
              if (showModel) ...[
                const SizedBox(height: 4),
                Text(p.model, textAlign: TextAlign.center, style: LenzText.cap),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Match confidence',
                            style: LenzText.cap.copyWith(fontSize: 13),
                          ),
                        ),
                        AnimatedCount(
                          to: pct,
                          suffix: '%',
                          style: LenzText.item.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    low ? LenzMeter.warn(value: confidence) : LenzMeter(value: confidence),
                  ],
                ),
              ),
              if (low) ...[
                const SizedBox(height: 10),
                Text(
                  "We're not very sure what this is. You can carry on, "
                  "but we won't be able to say as much.",
                  textAlign: TextAlign.center,
                  style: LenzText.cap.copyWith(color: LenzColors.warn),
                ),
              ],
            ],
          ),
        ),
        LenzCoach(
          mood: low ? LenzMood.unsure : LenzMood.happy,
          width: 130,
          text: evidenceCount > 0
              ? "Does this look right? Next I'll show you the $evidenceCount photos we need."
              : "Does this look right? Next we'll show you which photos to take.",
        ),
        LenzButton(label: 'Yes, continue', onPressed: onContinue, pulse: true),
        LenzButton(label: 'Not this item', onPressed: onBack, variant: LenzButtonVariant.ghost),
      ],
    );
  }
}

/// The searching disc: a slowly spinning dashed ring around the photo, with
/// a green scan line sweeping across it.
class _SearchDisc extends StatefulWidget {
  const _SearchDisc({required this.child});

  final Widget child;

  @override
  State<_SearchDisc> createState() => _SearchDiscState();
}

class _SearchDiscState extends State<_SearchDisc> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (LenzMotion.reduced(context)) {
      _spin.stop();
      _sweep.stop();
      _sweep.value = .25;
    } else {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_sweep.isAnimating) _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Positioned(
          left: -12,
          top: -12,
          right: -12,
          bottom: -12,
          child: RotationTransition(
            turns: _spin,
            child: const CustomPaint(painter: _DashedRingPainter()),
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment(-.35, -1),
              end: Alignment(.35, 1),
              colors: [Colors.white, Color(0xFFE3EEE7)],
            ),
            boxShadow: LenzShadows.sh2,
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) {
                    final t = Curves.easeInOut.transform(1 - (2 * _sweep.value - 1).abs());
                    return Align(
                      alignment: Alignment(0, -0.84 + 1.64 * t),
                      child: FractionallySizedBox(
                        widthFactor: .88,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: const LinearGradient(
                              colors: [Color(0x002EA44F), LenzColors.leaf, Color(0x002EA44F)],
                            ),
                            boxShadow: const [BoxShadow(color: LenzColors.leaf, blurRadius: 18)],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color.fromRGBO(18, 47, 36, .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final rect = (Offset.zero & size).deflate(2);
    const dashes = 48;
    const sweep = 2 * 3.141592653589793 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * .55, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) => false;
}

class _Stage {
  final String label;
  final bool done;
  final bool active;
  const _Stage(this.label, {required this.done, required this.active});
}
