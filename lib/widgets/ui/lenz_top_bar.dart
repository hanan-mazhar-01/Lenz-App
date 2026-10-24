import 'package:flutter/material.dart';

import '../../core/theme/lenz_text.dart';
import 'lenz_icon_button.dart';
import 'lenz_icons.dart';

/// The prototype's `topbar()`: back button, centred title, right slot.
///
/// `margin-bottom: 14` is included; the prototype's 12px gaps between the
/// three zones are kept. [dark] switches to the glass button and white title.
class LenzTopBar extends StatelessWidget {
  const LenzTopBar({
    super.key,
    this.title,
    this.onBack,
    this.noBack = false,
    this.dark = false,
    this.leading,
    this.right,
    this.actions,
    this.margin = const EdgeInsets.only(bottom: 14),
    this.titleWidget,
  });

  final String? title;

  /// Defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// Hides the back button (keeps a 44px spacer so the title stays centred).
  final bool noBack;
  final bool dark;

  /// Replaces the back button (e.g. a close `x`).
  final Widget? leading;

  /// Right slot content (a single widget).
  final Widget? right;

  /// Right slot as a list of widgets spaced by 8px (shorthand for [right]).
  final List<Widget>? actions;
  final EdgeInsetsGeometry margin;

  /// Custom title content (e.g. title + subtitle column), overrides [title].
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    Widget lead;
    if (leading != null) {
      lead = leading!;
    } else if (noBack) {
      lead = const SizedBox(width: 44, height: 44);
    } else {
      lead = LenzIconButton(
        icon: LenzIcons.chevL,
        dark: dark,
        semanticLabel: 'Back',
        onTap: onBack ?? () => Navigator.of(context).maybePop(),
      );
    }

    Widget trail;
    if (right != null) {
      trail = right!;
    } else if (actions != null && actions!.isNotEmpty) {
      trail = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions!.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            actions![i],
          ],
        ],
      );
    } else {
      trail = const SizedBox(width: 44);
    }

    return Padding(
      padding: margin,
      child: Row(
        children: [
          lead,
          const SizedBox(width: 12),
          Expanded(
            child: titleWidget ??
                Text(
                  title ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LenzText.section.copyWith(
                    color: dark ? Colors.white : null,
                    letterSpacing: -.38,
                  ),
                ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: Align(
              alignment: Alignment.centerRight,
              widthFactor: 1,
              child: trail,
            ),
          ),
        ],
      ),
    );
  }
}
