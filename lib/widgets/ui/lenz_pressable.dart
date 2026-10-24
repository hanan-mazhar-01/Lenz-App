import 'package:flutter/widgets.dart';

import '../../core/theme/lenz_motion.dart';
import '../../services/haptics.dart';

/// Spring press feedback shared by every tappable Lenz widget.
///
/// Reproduces `.btn:active{transform:scale(.96)}` with
/// `transition: transform .25s var(--spring)`: the scale animates from its
/// *current* value to the pressed/rest value with the overshooting spring
/// curve, in both directions.
class LenzPressable extends StatefulWidget {
  const LenzPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.pressedScale = .96,
    this.duration = LenzMotion.press,
    this.haptic = true,
    this.behavior = HitTestBehavior.opaque,
    this.isButton = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration duration;

  /// Light haptic on a confirmed tap (respects the app's haptics setting).
  final bool haptic;
  final HitTestBehavior behavior;
  final bool isButton;
  final String? semanticLabel;

  @override
  State<LenzPressable> createState() => _LenzPressableState();
}

class _LenzPressableState extends State<LenzPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  double _from = 1;
  double _to = 1;
  bool _reduced = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = LenzMotion.reduced(context);
  }

  @override
  void didUpdateWidget(LenzPressable old) {
    super.didUpdateWidget(old);
    if (!_enabled && _to != 1) _setPressed(false);
  }

  double get _scale {
    if (_from == _to) return _to;
    final curve = _reduced ? Curves.easeOut : LenzMotion.spring;
    return _from + (_to - _from) * curve.transform(_c.value);
  }

  void _setPressed(bool down) {
    final target = down ? widget.pressedScale : 1.0;
    if (target == _to) return;
    _from = _scale;
    _to = target;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Transform.scale(scale: _scale, child: child),
    );
    if (_enabled) {
      child = GestureDetector(
        behavior: widget.behavior,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) Haptics.lightImpact();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: child,
      );
    }
    if (!widget.isButton) return child;
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      onTap: widget.onTap,
      child: child,
    );
  }
}
