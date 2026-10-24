import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_text.dart';
import 'lenz_icons.dart';
import 'lenz_pressable.dart';
import 'lenz_pulse_ring.dart';

enum LenzButtonVariant {
  /// Forest gradient (default).
  primary,

  /// White card-like button with a hairline border.
  ghost,

  /// Mint2 fill, forest label, no shadow.
  soft,

  /// Gold gradient for Pro.
  gold,

  /// Bad-soft fill, red label.
  danger,

  /// White -> mint gradient used on the dark home hero card.
  light,
}

enum LenzButtonSize {
  /// 58px / radius 20 / 16.5 type.
  md,

  /// 44px / radius 16 / 14.5 type.
  sm,
}

/// The prototype's `.btn`. Spring press (scale .96), optional pulse ring,
/// loading and disabled (.45 opacity) states.
class LenzButton extends StatelessWidget {
  const LenzButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = LenzButtonVariant.primary,
    this.size = LenzButtonSize.md,
    this.icon,
    this.iconSize,
    this.iconStrokeWidth = 2,
    this.leading,
    this.trailing,
    this.loading = false,
    this.pulse = false,
    this.expand = true,
    this.haptic = true,
    this.semanticLabel,
  });

  final String label;

  /// `null` disables the button (opacity .45).
  final VoidCallback? onPressed;
  final LenzButtonVariant variant;
  final LenzButtonSize size;

  /// Name of a [LenzIcon] shown before the label.
  final String? icon;
  final double? iconSize;
  final double iconStrokeWidth;

  /// Custom widget shown before the label (replaces [icon]).
  final Widget? leading;
  final Widget? trailing;

  /// Shows a spinner instead of the content and ignores taps.
  final bool loading;

  /// Adds the expanding green ring (`.btn.pulse`), e.g. for "Analyze now".
  final bool pulse;

  /// Full width (default, like `.btn{width:100%}`) or shrink-wrapped.
  final bool expand;
  final bool haptic;
  final String? semanticLabel;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final sm = size == LenzButtonSize.sm;
    final height = sm ? 44.0 : 58.0;
    final radius = sm ? LenzRadii.buttonSm : LenzRadii.button;
    final v = _style(variant);
    final textStyle =
        (sm ? LenzText.buttonSm : LenzText.button).copyWith(color: v.fg);
    final iSize = iconSize ?? (sm ? 18.0 : 20.0);

    final children = <Widget>[
      if (leading != null) ...[leading!, const SizedBox(width: 10)]
      else if (icon != null) ...[
        LenzIcon(icon!, size: iSize, strokeWidth: iconStrokeWidth, color: v.fg),
        const SizedBox(width: 10),
      ],
      Text(
        label,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        overflow: expand ? TextOverflow.visible : TextOverflow.ellipsis,
        style: textStyle,
      ),
      if (trailing != null) ...[const SizedBox(width: 10), trailing!],
    ];
    Widget row = Row(mainAxisSize: MainAxisSize.min, children: children);
    if (expand) row = FittedBox(fit: BoxFit.scaleDown, child: row);

    Widget content = loading
        ? Stack(
            alignment: Alignment.center,
            children: [
              Opacity(opacity: 0, child: row),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  valueColor: AlwaysStoppedAnimation(v.fg),
                ),
              ),
            ],
          )
        : row;

    final surface = CustomPaint(
      foregroundPainter: v.highlight == null
          ? null
          : _InsetHighlightPainter(radius, v.highlight!),
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: expand ? 14 : 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: v.gradient,
          color: v.color,
          borderRadius: BorderRadius.circular(radius),
          border: v.border ? Border.all(color: LenzColors.line) : null,
          boxShadow: v.shadow,
        ),
        child: content,
      ),
    );

    final body = pulse && _enabled
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              surface,
              LenzPulseRing(radius: radius + 5),
            ],
          )
        : surface;

    return LenzPressable(
      onTap: _enabled ? onPressed : null,
      haptic: haptic,
      semanticLabel: semanticLabel,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onPressed == null ? .45 : 1,
        child: body,
      ),
    );
  }

  static _ButtonStyle _style(LenzButtonVariant v) => switch (v) {
        LenzButtonVariant.primary => const _ButtonStyle(
            fg: Colors.white,
            gradient: LenzGradients.primary,
            shadow: LenzShadows.button,
            highlight: Color.fromRGBO(255, 255, 255, .18),
          ),
        LenzButtonVariant.ghost => const _ButtonStyle(
            fg: LenzColors.ink,
            color: LenzColors.paper,
            shadow: LenzShadows.sh1,
            border: true,
          ),
        LenzButtonVariant.soft => const _ButtonStyle(
            fg: LenzColors.forest,
            color: LenzColors.mint2,
          ),
        LenzButtonVariant.gold => const _ButtonStyle(
            fg: LenzColors.goldInk,
            gradient: LenzGradients.gold,
            shadow: LenzShadows.buttonGold,
            highlight: Color.fromRGBO(255, 255, 255, .5),
          ),
        LenzButtonVariant.danger => const _ButtonStyle(
            fg: LenzColors.bad,
            color: LenzColors.badSoft,
          ),
        LenzButtonVariant.light => const _ButtonStyle(
            fg: LenzColors.forest,
            gradient: LenzGradients.light,
            shadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, .5),
                offset: Offset(0, 12),
                blurRadius: 22,
                spreadRadius: -10,
              ),
            ],
          ),
      };
}

class _ButtonStyle {
  const _ButtonStyle({
    required this.fg,
    this.color,
    this.gradient,
    this.shadow,
    this.highlight,
    this.border = false,
  });
  final Color fg;
  final Color? color;
  final Gradient? gradient;
  final List<BoxShadow>? shadow;
  final Color? highlight;
  final bool border;
}

/// `box-shadow: inset 0 1px 0 <color>`: a 1px highlight along the top edge.
class _InsetHighlightPainter extends CustomPainter {
  const _InsetHighlightPainter(this.radius, this.color);
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rrect);
    final band = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect.inflate(4)),
      Path()..addRRect(rrect.shift(const Offset(0, 1))),
    );
    canvas.drawPath(band, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InsetHighlightPainter old) =>
      old.radius != radius || old.color != color;
}

/// The prototype's `.social` button (Apple / Google): 54px, radius 18, paper
/// with hairline border and `sh1`, 15.5/900 label, spring press (scale .95).
/// Use inside a `Row` with `Expanded` children (the CSS has `flex:1`).
class LenzSocialButton extends StatelessWidget {
  const LenzSocialButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconStrokeWidth = 2,
    this.leading,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Name of a [LenzIcon] (e.g. `LenzIcons.apple`, `LenzIcons.gicon`).
  final String? icon;
  final double iconStrokeWidth;

  /// Custom leading widget (e.g. the app's multi-colour `GoogleGIcon`).
  final Widget? leading;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: onPressed,
      pressedScale: .95,
      semanticLabel: semanticLabel,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onPressed == null ? .45 : 1,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LenzColors.paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: LenzColors.line),
            boxShadow: LenzShadows.sh1,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)]
                else if (icon != null) ...[
                  LenzIcon(
                    icon!,
                    size: 22,
                    strokeWidth: iconStrokeWidth,
                    color: LenzColors.ink,
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: LenzText.social,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
