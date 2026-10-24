import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../core/theme/lenz_text.dart';
import '../../services/haptics.dart';

/// The prototype's `.seg`: a pill track with a sliding white thumb that moves
/// with the spring curve (450ms). Works with two or more [labels]; the
/// prototype uses two ("Sign in" / "Create account").
class LenzSegmented extends StatelessWidget {
  const LenzSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  static const double _pad = 5;
  static const double _gap = 4;
  static const double _h = 42;

  @override
  Widget build(BuildContext context) {
    assert(labels.length >= 2, 'A segmented control needs at least two options');
    final n = labels.length;
    return Container(
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: LenzColors.segTrack,
        borderRadius: BorderRadius.circular(LenzRadii.segTrack),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final thumbW = (c.maxWidth - _gap * (n - 1)) / n;
          return SizedBox(
            height: _h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositioned(
                  duration: LenzMotion.segThumb,
                  curve: LenzMotion.reduced(context)
                      ? Curves.easeOut
                      : LenzMotion.spring,
                  left: index * (thumbW + _gap),
                  top: 0,
                  width: thumbW,
                  height: _h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(LenzRadii.segThumb),
                      boxShadow: LenzShadows.sh1,
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == index,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (i == index) return;
                              Haptics.selectionClick();
                              onChanged(i);
                            },
                            child: SizedBox(
                              height: _h,
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 300),
                                  style: LenzText.segment.copyWith(
                                    color: i == index
                                        ? LenzColors.forest
                                        : LenzColors.muted,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      labels[i],
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
