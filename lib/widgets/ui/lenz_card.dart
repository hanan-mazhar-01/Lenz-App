import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_text.dart';
import 'lenz_pressable.dart';

/// The prototype's `.card`: paper, radius 26, hairline border, `sh1`.
/// Pass [onTap] to make it a pressable card (scale .97 spring).
class LenzCard extends StatelessWidget {
  const LenzCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = LenzRadii.card,
    this.color = LenzColors.paper,
    this.gradient,
    this.border = true,
    this.shadows = LenzShadows.sh1,
    this.onTap,
    this.clip = false,
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color color;
  final Gradient? gradient;
  final bool border;

  /// Defaults to `LenzShadows.sh1`; pass `const []` for a flat card.
  final List<BoxShadow> shadows;
  final VoidCallback? onTap;

  /// Clip children to the rounded rectangle (needed for images / overflow).
  final bool clip;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    Widget card = Container(
      width: width,
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: br,
        border: border ? Border.all(color: LenzColors.line) : null,
        boxShadow: shadows,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      padding: padding,
      child: child,
    );
    if (onTap != null) {
      card = LenzPressable(onTap: onTap, pressedScale: .97, child: card);
    }
    return card;
  }
}

/// The prototype's `.sectionhead`: baseline-aligned title and optional link
/// (`margin: 22px 2px 12px`).
class LenzSectionHeader extends StatelessWidget {
  const LenzSectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.margin = const EdgeInsets.fromLTRB(2, 22, 2, 12),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LenzText.section,
            ),
          ),
          if (actionLabel != null)
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(actionLabel!, style: LenzText.link),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The prototype's `.divider` ("or continue with"): hairlines either side of
/// a muted label. Without a [label] it is a plain hairline.
class LenzDivider extends StatelessWidget {
  const LenzDivider({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: SizedBox(height: 1, child: ColoredBox(color: LenzColors.line)),
    );
    if (label == null) {
      return const SizedBox(
        height: 1,
        child: ColoredBox(color: LenzColors.line),
      );
    }
    return Row(
      children: [
        line,
        const SizedBox(width: 12),
        Flexible(
          flex: 0,
          child: Text(label!, style: LenzText.divider, textAlign: TextAlign.center),
        ),
        const SizedBox(width: 12),
        line,
      ],
    );
  }
}
