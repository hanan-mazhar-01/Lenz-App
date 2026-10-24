import 'package:flutter/material.dart';

import '../lenz/lenz.dart';
import '../mascot/detective_mascot_widget.dart';
import '../ui/ui.dart';

/// Shown wherever the user has no data yet. The app never fills a screen with
/// sample content to look populated (§30, §31).
///
/// Lenz layout of the prototype's empty states: the character (bust or full
/// view, mood-matched), a title, a muted line and an optional button.
class EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Legacy mood selector, mapped onto a [LenzMood] when [mood] is not set.
  final MascotState mascotState;

  /// Legacy size; used as a hint for the character width when
  /// [characterWidth] is not set.
  final double mascotSize;

  final LenzMood? mood;
  final LenzView view;
  final double? characterWidth;
  final String? actionIcon;

  /// Wrap in a scroll view and centre vertically (for full-height slots).
  final bool center;

  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.mascotState = MascotState.curious,
    this.mascotSize = 96,
    this.mood,
    this.view = LenzView.bust,
    this.characterWidth,
    this.actionIcon,
    this.center = true,
  });

  static LenzMood moodFor(MascotState s) => switch (s) {
    MascotState.idle => LenzMood.idle,
    MascotState.curious => LenzMood.unsure,
    MascotState.scanning || MascotState.capturing => LenzMood.focus,
    MascotState.inspecting => LenzMood.inspect,
    MascotState.thinking => LenzMood.think,
    MascotState.discovering => LenzMood.shocked,
    MascotState.success => LenzMood.happy,
    MascotState.suspicious => LenzMood.sorry,
    MascotState.inconclusive => LenzMood.unsure,
    MascotState.teaching => LenzMood.hello,
  };

  @override
  Widget build(BuildContext context) {
    final width = characterWidth ?? (mascotSize * 2.2).clamp(140.0, 220.0);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          child: LenzCharacter(mood: mood ?? moodFor(mascotState), view: view),
        ),
        const SizedBox(height: 6),
        Text(title, textAlign: TextAlign.center, style: LenzText.title),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: Text(message, textAlign: TextAlign.center, style: LenzText.sub),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          // Hug the label (the kit's non-expanding button still fills a
          // bounded width because of its centring alignment).
          IntrinsicWidth(
            child: LenzButton(
              label: actionLabel!,
              onPressed: onAction,
              icon: actionIcon ?? LenzIcons.camera,
              size: LenzButtonSize.sm,
              expand: false,
            ),
          ),
        ],
      ],
    );
    if (!center) return content;
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: c.hasBoundedHeight ? (c.maxHeight - 32).clamp(0, double.infinity) : 0,
            minWidth: double.infinity,
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}
