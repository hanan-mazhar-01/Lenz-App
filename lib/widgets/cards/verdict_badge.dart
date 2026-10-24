import 'package:flutter/widgets.dart';

import '../../models/authentication_result.dart';
import '../ui/ui.dart';

/// Verdict pill in the Lenz style (`.pill.auth|fake|unsure`): soft verdict
/// colour, verdict icon and the full verdict label
/// (Appears Authentic / Likely Replica / Unable to Verify).
class VerdictBadge extends StatelessWidget {
  final Verdict verdict;
  final bool isSmall;

  const VerdictBadge({super.key, required this.verdict, this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    final v = LenzVerdictStyle.of(verdict);
    final fontSize = isSmall ? 11.0 : 12.0;
    return Container(
      height: isSmall ? 22 : 26,
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 10),
      decoration: BoxDecoration(color: v.soft, borderRadius: BorderRadius.circular(LenzRadii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LenzIcon(v.icon, size: isSmall ? 12 : 13, strokeWidth: 2.4, color: v.color),
          SizedBox(width: isSmall ? 4 : 5),
          Flexible(
            child: Text(
              v.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LenzText.pill.copyWith(color: v.color, fontSize: fontSize),
            ),
          ),
        ],
      ),
    );
  }
}
