import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import 'lenz_icons.dart';
import 'lenz_pressable.dart';

/// The prototype's `.icon-btn`: 44x44, radius 16, paper with hairline border
/// and `sh1`. [dark] is the glass variant used over camera / dark screens.
class LenzIconButton extends StatelessWidget {
  const LenzIconButton({
    super.key,
    this.icon,
    this.child,
    required this.onTap,
    this.dark = false,
    this.size = 44,
    this.radius = LenzRadii.iconButton,
    this.iconSize = 22,
    this.strokeWidth = 2,
    this.iconColor,
    this.semanticLabel,
  }) : assert(icon != null || child != null, 'Provide an icon or a child');

  /// Name of a [LenzIcon].
  final String? icon;

  /// Custom content (overrides [icon]).
  final Widget? child;
  final VoidCallback? onTap;
  final bool dark;
  final double size;
  final double radius;
  final double iconSize;
  final double strokeWidth;
  final Color? iconColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fg = iconColor ?? (dark ? Colors.white : LenzColors.ink);
    final content = child ??
        LenzIcon(icon!, size: iconSize, strokeWidth: strokeWidth, color: fg);
    final br = BorderRadius.circular(radius);

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color.fromRGBO(255, 255, 255, .14) : LenzColors.paper,
        borderRadius: br,
        border: Border.all(
          color: dark ? const Color.fromRGBO(255, 255, 255, .2) : LenzColors.line,
        ),
        boxShadow: dark ? null : LenzShadows.sh1,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: IconTheme(
            data: IconThemeData(color: fg, size: iconSize),
            child: content,
          ),
        ),
      ),
    );
    if (dark) {
      body = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: body,
        ),
      );
    }
    return LenzPressable(
      onTap: onTap,
      pressedScale: .9,
      duration: LenzMotion.pressIcon,
      semanticLabel: semanticLabel,
      child: body,
    );
  }
}
