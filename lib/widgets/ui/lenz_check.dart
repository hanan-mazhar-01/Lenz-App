import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../services/haptics.dart';
import 'lenz_icons.dart';

/// The prototype's `.check`: 26px rounded square, 2px border; checked state is
/// leaf green with a white tick that pops in with the spring.
class LenzCheck extends StatelessWidget {
  const LenzCheck({
    super.key,
    required this.value,
    this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final box = AnimatedContainer(
      duration: LenzMotion.check,
      curve: LenzMotion.reduced(context) ? Curves.easeOut : LenzMotion.spring,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: value ? LenzColors.leaf : Colors.transparent,
        borderRadius: BorderRadius.circular(LenzRadii.check),
        border: Border.all(
          color: value ? LenzColors.leaf : LenzColors.checkBorder,
          width: 2,
        ),
      ),
      child: Center(
        child: AnimatedScale(
          duration: LenzMotion.check,
          curve: LenzMotion.spring,
          scale: value ? 1 : .4,
          child: AnimatedOpacity(
            duration: LenzMotion.check,
            opacity: value ? 1 : 0,
            child: const LenzIcon(
              LenzIcons.check,
              size: 16,
              strokeWidth: 3,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      checked: value,
      label: semanticLabel,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: onChanged == null
          ? box
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.selectionClick();
                onChanged!(!value);
              },
              child: box,
            ),
    );
  }
}
