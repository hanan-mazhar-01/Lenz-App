import 'package:flutter/widgets.dart';

import '../lenz/lenz.dart';
import '../ui/ui.dart';

/// Tab header of the prototype's History / Favorites screens: `display`
/// title, muted line, and Lenz peeking in on the right (78px, raised 14px).
class LenzTabTitle extends StatelessWidget {
  const LenzTabTitle({super.key, required this.title, required this.subtitle, required this.mood});

  final String title;
  final String subtitle;
  final LenzMood mood;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final w = narrow ? 64.0 : 78.0;
    final h = w / LenzView.peek.aspectRatio;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: LenzText.display),
              const SizedBox(height: 4),
              Text(subtitle, style: LenzText.sub),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // `margin-top:-14px`: Lenz pokes 14px above the row without adding
        // to its height.
        SizedBox(
          width: w,
          height: h - 14,
          child: OverflowBox(
            alignment: Alignment.bottomCenter,
            maxHeight: h,
            child: LenzCharacter(mood: mood, view: LenzView.peek, fx: false),
          ),
        ),
      ],
    );
  }
}
