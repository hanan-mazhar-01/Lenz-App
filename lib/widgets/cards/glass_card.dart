import 'package:flutter/material.dart';

import '../ui/ui.dart';

/// White Lenz card (`.card`): paper fill, hairline border, `sh1` shadow and a
/// spring press when tappable. Kept under its old name so existing screens
/// pick up the new look without changes.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? backgroundColor;
  final Border? border;
  final VoidCallback? onTap;
  final bool enableFeedback;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 22,
    this.backgroundColor,
    this.border,
    this.onTap,
    this.enableFeedback = true,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? LenzColors.paper,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(color: LenzColors.line),
        boxShadow: LenzShadows.sh1,
      ),
      child: child,
    );

    final body = onTap == null
        ? card
        : LenzPressable(onTap: onTap!, pressedScale: .97, haptic: enableFeedback, child: card);
    return margin == null ? body : Padding(padding: margin!, child: body);
  }
}
