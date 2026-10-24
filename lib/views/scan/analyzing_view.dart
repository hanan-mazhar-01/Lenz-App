import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/evidence.dart';
import '../../models/product.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// Screen displayed while authenticity analysis is in flight: ivory
/// light screen on ONE portrait page (no scrolling), journey at "Analyze", a small
/// Lenz cycling inspect / think / focus with his bubble, the user's photos
/// being ticked off next to the current stage, and the 4 steps as a 2x2 grid.
/// No ring or glow around the character.
///
/// The analysis reports no real progress, so (as before the redesign) the
/// steps advance on a timer (1.8s) and the photos cycle every 2.4s; no
/// percentage is shown.
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

/// Lenz's mood and line per stage (prototype `moods`).
const List<(LenzMood, String)> _stageMoods = [
  (LenzMood.inspect, 'Studying every stitch…'),
  (LenzMood.think, 'Comparing with known patterns…'),
  (LenzMood.focus, 'Zooming in on the details…'),
  (LenzMood.inspect, 'Almost done, hold on…'),
];

class _AnalyzingViewState extends State<AnalyzingView> with TickerProviderStateMixin {
  late final AnimationController _pulse; // active step dot

  int _currentStage =
      0; // 0: Photo Inspection, 1: AI Analysis, 2: Authenticity Check, 3: Generating Result
  int _currentPhotoIndex = 0;
  final Set<int> _seenPhotos = {}; // presentation only: photos already "ticked"
  Timer? _stageTimer;
  Timer? _photoCycleTimer;
  bool _motionStarted = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

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
          _seenPhotos.add(_currentPhotoIndex % imageList.length);
          _currentPhotoIndex = (_currentPhotoIndex + 1) % imageList.length;
        });
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motionStarted && !LenzMotion.reduced(context)) {
      _motionStarted = true;
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _stageTimer?.cancel();
    _photoCycleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageList = widget.capturedImages.values.where((p) => p.isNotEmpty).toList();
    final submittedCount = widget.items
        .where((i) => widget.capturedImages.containsKey(i.id))
        .length;
    final pad = MediaQuery.paddingOf(context);
    final stage = _stageMoods[_currentStage.clamp(0, 3)];

    // The first (identification) photo is analysed too; it is not in [items].
    final photoCount = submittedCount + 1;
    final steps = <(String, String)>[
      ('Photo inspection', 'Checking $photoCount photo${photoCount == 1 ? '' : 's'}'),
      ('AI analysis', 'Flaws & materials'),
      ('Authenticity check', 'Known patterns'),
      ('Generating result', 'Almost there'),
    ];

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LenzBlob(color: LenzColors.mint),
          // One portrait page, never scrolls: only Lenz flexes, everything
          // else is compact (photos + stage on one row, steps as a 2x2 grid).
          Padding(
            padding: EdgeInsets.fromLTRB(20, pad.top + 14, 20, 16 + pad.bottom),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  LenzTopBar(
                    title: 'Analyzing',
                    noBack: widget.onBack == null,
                    onBack: widget.onBack,
                  ),
                  const LenzJourneyStepper(
                    step: 3,
                    bottomMargin: 6,
                    rider: LenzCharacter(view: LenzView.peek, fx: false, interactive: false),
                  ),
                  Expanded(child: _hero(stage)),
                  const SizedBox(height: 8),
                  _photosAndStage(imageList),
                  const SizedBox(height: 12),
                  _stepsGrid(steps),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LenzIcon(
                        LenzIcons.lock,
                        size: 12,
                        strokeWidth: 2.4,
                        color: LenzColors.subtle,
                      ),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Your privacy is our priority',
                          style: TextStyle(
                            fontFamily: LenzText.family,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: LenzColors.subtle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero((LenzMood, String) stage) {
    return LayoutBuilder(
      builder: (context, c) {
        // Lenz is the only flexible element: at most ~74% of the width (bust crop, so about 58% in visible width), and
        // never taller than the room that is left.
        final h = math.min(c.maxHeight, c.maxWidth * .74);
        final w = h * LenzView.bust.aspectRatio;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: w,
              height: h,
              child: LenzCharacter(mood: stage.$1, view: LenzView.bust, shadow: false),
            ),
            Positioned(
              left: 0,
              top: 4,
              width: c.maxWidth * .46,
              child: LenzBubble(
                key: ValueKey(stage.$2),
                text: stage.$2,
                maxWidth: c.maxWidth * .46,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _photosAndStage(List<String> imageList) {
    final n = imageList.length;
    return LayoutBuilder(
      builder: (context, c) {
        final size = (c.maxWidth * .105).clamp(32.0, 42.0);
        return Row(
          children: [
            if (n > 0)
              Flexible(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < n && i < 5; i++)
                      _PhotoTick(
                        path: imageList[i],
                        size: size,
                        active: n > 1 && i == _currentPhotoIndex % n || n == 1,
                        done: _seenPhotos.contains(i) && i != _currentPhotoIndex % n,
                      ),
                  ],
                ),
              ),
            if (n > 0) const SizedBox(width: 10),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: _stagePill()),
            ),
          ],
        );
      },
    );
  }

  Widget _stagePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: LenzColors.mint2,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: LenzColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: .35, end: 1.0).animate(_pulse),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: LenzColors.leaf, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: FittedBox(
                key: ValueKey(_currentStage),
                fit: BoxFit.scaleDown,
                child: Text(
                  _stagePillShort(),
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: LenzText.family,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: LenzColors.forest,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Short form of the stage for the compact pill.
  String _stagePillShort() {
    switch (_currentStage) {
      case 0:
        return 'Inspecting photos';
      case 1:
        return 'AI analysis';
      case 2:
        return 'Authenticity check';
      case 3:
      default:
        return 'Finishing report';
    }
  }

  Widget _stepsGrid(List<(String, String)> steps) {
    Widget cell(int i) => Expanded(child: _stepCard(i, steps[i].$1, steps[i].$2));
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [cell(0), const SizedBox(width: 8), cell(1)],
          ),
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [cell(2), const SizedBox(width: 8), cell(3)],
          ),
        ),
      ],
    );
  }

  Widget _stepCard(int i, String title, String subtitle) {
    final done = i < _currentStage;
    final on = i == _currentStage;
    const dur = Duration(milliseconds: 500);
    return AnimatedOpacity(
      duration: dur,
      curve: LenzMotion.ease,
      opacity: on || done ? 1 : .5,
      child: AnimatedContainer(
        duration: dur,
        curve: LenzMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: on ? LenzColors.mint2 : LenzColors.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? LenzColors.leaf : LenzColors.line),
          boxShadow: on ? LenzShadows.sh1 : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? LenzColors.leaf : Colors.transparent,
                border: Border.all(
                  width: 3,
                  color: done
                      ? LenzColors.leaf
                      : on
                      ? LenzColors.leaf
                      : const Color.fromRGBO(18, 47, 36, .18),
                ),
              ),
              child: Center(
                child: done
                    ? const LenzIcon(
                        LenzIcons.check,
                        size: 13,
                        strokeWidth: 3.4,
                        color: Colors.white,
                      )
                    : on
                    ? ScaleTransition(
                        scale: Tween(begin: .7, end: 1.0).animate(_pulse),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: LenzColors.leaf,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: LenzText.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: LenzColors.ink,
                      ),
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: LenzText.family,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: LenzColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the user's photos: active (lifted, light-green border) or ticked.
class _PhotoTick extends StatelessWidget {
  const _PhotoTick({
    required this.path,
    required this.size,
    required this.active,
    required this.done,
  });

  final String path;
  final double size;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    const dur = Duration(milliseconds: 400);
    return AnimatedScale(
      duration: dur,
      curve: LenzMotion.spring,
      scale: active ? 1.12 : 1,
      child: AnimatedContainer(
        duration: dur,
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [LenzColors.mint2, LenzColors.mint],
          ),
          border: Border.all(
            width: 2,
            color: done
                ? LenzColors.leaf
                : active
                ? LenzColors.leaf
                : LenzColors.line,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppImage(imagePath: path, width: size, height: size, fit: BoxFit.cover),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 350),
                opacity: done ? 1 : 0,
                child: const ColoredBox(
                  color: Color.fromRGBO(46, 164, 79, .78),
                  child: Center(
                    child: LenzIcon(LenzIcons.check, size: 22, strokeWidth: 3, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
