import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/lenz_motion.dart';
import '../ui/lenz_stagger.dart' show LenzEntranceScope;

/// Fades, slides and slightly scales its child in once on mount (the
/// prototype's `rise` keyframes).
///
/// Restyled for the Lenz redesign: defaults are now 22px up, scale .98 -> 1,
/// 700ms `cubic-bezier(.2,.8,.2,1)`. The constructor is unchanged so existing
/// screens keep working, and [delay] keeps its old meaning (the child stays
/// invisible until the delay has elapsed, then animates). New screens should
/// prefer `LenzRise` / `LenzStagger`, which fold the delay into the animation.
class FadeSlideTransition extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;
  final Curve curve;
  final double beginScale;

  const FadeSlideTransition({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = LenzMotion.rise,
    this.beginOffset = const Offset(0, 22),
    this.curve = LenzMotion.ease,
    this.beginScale = .98,
  });

  @override
  State<FadeSlideTransition> createState() => _FadeSlideTransitionState();
}

class _FadeSlideTransitionState extends State<FadeSlideTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (LenzMotion.reduced(context) || LenzEntranceScope.covers(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (_controller.value >= 1) return child!;
        final e = widget.curve.transform(_controller.value);
        return Opacity(
          opacity: e.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: widget.beginOffset * (1 - e),
            child: widget.beginScale == 1
                ? child
                : Transform.scale(
                    scale: widget.beginScale + (1 - widget.beginScale) * e,
                    child: child,
                  ),
          ),
        );
      },
    );
  }
}
