import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../core/theme/lenz_text.dart';
import '../../models/authentication_result.dart';
import '../../services/haptics.dart';
import 'lenz_icons.dart';
import 'lenz_verdict_style.dart';

/// The prototype's `.chip`: 34px pill, paper with hairline border; the `on`
/// state is solid forest with white text (animated 250ms).
class LenzChip extends StatelessWidget {
  const LenzChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.iconSize = 16,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Name of a [LenzIcon] shown before the label.
  final String? icon;
  final double iconSize;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : LenzColors.ink;
    final chip = AnimatedContainer(
      duration: LenzMotion.chip,
      curve: LenzMotion.ease,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: selected ? LenzColors.forest : LenzColors.paper,
        borderRadius: BorderRadius.circular(LenzRadii.pill),
        border: Border.all(
          color: selected ? Colors.transparent : LenzColors.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)]
          else if (icon != null) ...[
            LenzIcon(icon!, size: iconSize, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: LenzMotion.chip,
              curve: LenzMotion.ease,
              style: LenzText.chip.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: Text(label),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.selectionClick();
          onTap!();
        },
        child: chip,
      ),
    );
  }
}

enum LenzPillVariant { auth, fake, unsure, mint, gold }

/// The prototype's `.pill`: 26px tall badge with optional icon.
///
/// ```dart
/// LenzPill.verdict(Verdict.likelyAuthentic)   // "Authentic" with shield icon
/// LenzPill(label: 'Done', variant: LenzPillVariant.auth)
/// ```
class LenzPill extends StatelessWidget {
  const LenzPill({
    super.key,
    required this.label,
    this.variant = LenzPillVariant.mint,
    this.icon,
    this.iconSize = 13,
    this.iconStrokeWidth = 2.4,
    this.background,
    this.foreground,
  });

  /// Verdict pill with the short label (`Authentic` / `Replica` / `Not sure`)
  /// and the verdict icon, like `verdictPill()` in core.js.
  factory LenzPill.verdict(Verdict verdict, {Key? key, bool short = true}) {
    final v = LenzVerdictStyle.of(verdict);
    return LenzPill(
      key: key,
      label: short ? v.short : v.label,
      variant: switch (v.kind) {
        LenzVerdictKind.auth => LenzPillVariant.auth,
        LenzVerdictKind.fake => LenzPillVariant.fake,
        LenzVerdictKind.unsure => LenzPillVariant.unsure,
      },
      icon: v.icon,
    );
  }

  final String label;
  final LenzPillVariant variant;

  /// Name of a [LenzIcon].
  final String? icon;
  final double iconSize;
  final double iconStrokeWidth;

  /// Overrides the variant's fill / text colours.
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, gradient) = switch (variant) {
      LenzPillVariant.auth => (LenzColors.okSoft, LenzColors.ok, null),
      LenzPillVariant.fake => (LenzColors.badSoft, LenzColors.bad, null),
      LenzPillVariant.unsure => (LenzColors.warnSoft, LenzColors.warn, null),
      LenzPillVariant.mint => (LenzColors.mint, LenzColors.forest, null),
      LenzPillVariant.gold => (
          LenzColors.gold,
          LenzColors.goldInk,
          LenzGradients.gold,
        ),
    };
    final color = foreground ?? fg;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background ?? (gradient == null ? bg : null),
        gradient: background == null ? gradient : null,
        borderRadius: BorderRadius.circular(LenzRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            LenzIcon(
              icon!,
              size: iconSize,
              strokeWidth: iconStrokeWidth,
              color: color,
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LenzText.pill.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
