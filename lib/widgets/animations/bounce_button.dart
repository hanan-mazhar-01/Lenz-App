import 'package:flutter/material.dart';

import '../../core/theme/lenz_motion.dart';
import '../ui/lenz_pressable.dart';

/// Press-to-shrink wrapper used across the app.
///
/// Restyled for the Lenz redesign: the press uses the prototype's spring
/// (`cubic-bezier(.34,1.56,.64,1)`, 250ms) instead of the old ease/elastic
/// pair. The constructor is unchanged so existing screens keep working; new
/// screens should prefer `LenzButton` / `LenzPressable` / `LenzCard(onTap:)`.
class BounceButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleLower;
  final Duration duration;
  final HitTestBehavior behavior;

  const BounceButton({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleLower = 0.95,
    this.duration = LenzMotion.press,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: onTap,
      pressedScale: scaleLower,
      duration: duration,
      behavior: behavior,
      isButton: false,
      child: child,
    );
  }
}
