import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_text.dart';
import 'lenz_icons.dart';

/// The prototype's `.group`: a paper card (radius 26, hairline border, `sh1`,
/// clipped) that stacks [LenzSettingRow]s separated by hairlines.
class LenzSettingGroup extends StatelessWidget {
  const LenzSettingGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: LenzColors.paper,
        borderRadius: LenzRadii.cardRadius,
        border: Border.all(color: LenzColors.line),
        boxShadow: LenzShadows.sh1,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const SizedBox(
                height: 1,
                child: ColoredBox(color: LenzColors.line),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The prototype's `.setting` row: 38px mint2 icon box (radius 13), title,
/// optional sub line, trailing widget (switch, pill...) or a chevron. Pressing
/// tints the row mint2.
class LenzSettingRow extends StatefulWidget {
  const LenzSettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron,
    this.destructive = false,
    this.iconColor,
    this.iconBackground,
  });

  final String title;
  final String? subtitle;

  /// Name of a [LenzIcon] placed in the 38px icon box.
  final String? icon;

  /// Custom content for the icon box (overrides [icon]).
  final Widget? leading;

  /// Replaces the chevron (e.g. a `LenzSwitch`).
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Defaults to true when [onTap] is set and there is no [trailing].
  final bool? showChevron;

  /// Red title + red-soft icon box (log out / delete account).
  final bool destructive;
  final Color? iconColor;
  final Color? iconBackground;

  @override
  State<LenzSettingRow> createState() => _LenzSettingRowState();
}

class _LenzSettingRowState extends State<LenzSettingRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.iconColor ??
        (widget.destructive ? LenzColors.bad : LenzColors.forest);
    final bg = widget.iconBackground ??
        (widget.destructive ? LenzColors.badSoft : LenzColors.mint2);
    final chevron = widget.showChevron ??
        (widget.onTap != null && widget.trailing == null);

    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: _down && widget.onTap != null
          ? LenzColors.mint2
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          if (widget.icon != null || widget.leading != null) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: widget.leading ??
                  LenzIcon(widget.icon!, size: 20, color: fg),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: LenzText.setting.copyWith(
                    color: widget.destructive ? LenzColors.bad : null,
                  ),
                ),
                if (widget.subtitle != null)
                  Text(widget.subtitle!, style: LenzText.settingSub),
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 12),
            widget.trailing!,
          ] else if (chevron) ...[
            const SizedBox(width: 12),
            const LenzIcon(LenzIcons.chevR, size: 18, color: LenzColors.ink),
          ],
        ],
      ),
    );

    if (widget.onTap == null) return row;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: row,
      ),
    );
  }
}

