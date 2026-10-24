import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../services/haptics.dart';

/// The prototype's `.switch`: 52x32 track, 26px white thumb that travels 20px
/// with the spring curve (350ms), track fades to leaf green.
class LenzSwitch extends StatelessWidget {
  const LenzSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduced = LenzMotion.reduced(context);
    return Semantics(
      toggled: value,
      label: semanticLabel,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null
            ? null
            : () {
                Haptics.selectionClick();
                onChanged!(!value);
              },
        child: AnimatedContainer(
          duration: LenzMotion.switchTrack,
          width: 52,
          height: 32,
          decoration: BoxDecoration(
            color: value ? LenzColors.leaf : LenzColors.switchOff,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                duration: LenzMotion.switchThumb,
                curve: reduced ? Curves.easeOut : LenzMotion.spring,
                left: value ? 23 : 3,
                top: 3,
                width: 26,
                height: 26,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: LenzShadows.thumb,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
