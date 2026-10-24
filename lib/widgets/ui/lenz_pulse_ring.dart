import 'package:flutter/widgets.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';

/// The expanding "ring" keyframes of the prototype
/// (`@keyframes ring{0%{scale(.96);opacity:.9}100%{scale(1.08);opacity:0}}`),
/// used by `.btn.pulse::after` (2s) and the tab bar FAB (2.4s).
///
/// Place it in a [Stack] with `clipBehavior: Clip.none`; it positions itself
/// [inset] pixels outside its parent's box.
class LenzPulseRing extends StatefulWidget {
  const LenzPulseRing({
    super.key,
    this.radius = 25,
    this.inset = 5,
    this.color = LenzColors.pulseRing,
    this.strokeWidth = 2,
    this.duration = LenzMotion.pulse,
  });

  /// Corner radius of the ring box (use a large number for a circle).
  final double radius;

  /// How far the ring box extends beyond the parent on every side.
  final double inset;
  final Color color;
  final double strokeWidth;
  final Duration duration;

  @override
  State<LenzPulseRing> createState() => _LenzPulseRingState();
}

class _LenzPulseRingState extends State<LenzPulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = LenzMotion.reduced(context);
    if (reduced && _running) {
      _c.stop();
      _running = false;
    } else if (!reduced && !_running) {
      _c.repeat();
      _running = true;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: -widget.inset,
      right: -widget.inset,
      top: -widget.inset,
      bottom: -widget.inset,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              if (!_running) return const SizedBox.shrink();
              final p = LenzMotion.cssEaseOut.transform(_c.value);
              return Opacity(
                opacity: (.9 * (1 - p)).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: .96 + .12 * p,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.radius),
                      border: Border.all(
                        color: widget.color,
                        width: widget.strokeWidth,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
