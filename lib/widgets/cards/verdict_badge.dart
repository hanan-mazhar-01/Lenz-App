import 'package:flutter/cupertino.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/authentication_result.dart';

class VerdictBadge extends StatelessWidget {
  final Verdict verdict;
  final bool isSmall;

  const VerdictBadge({
    super.key,
    required this.verdict,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    switch (verdict) {
      case Verdict.likelyAuthentic:
        bg = AppColors.successBg;
        fg = AppColors.success;
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case Verdict.likelyReplica:
        bg = AppColors.dangerBg;
        fg = AppColors.danger;
        icon = CupertinoIcons.exclamationmark_triangle_fill;
        break;
      case Verdict.inconclusive:
        bg = AppColors.neutralPill;
        fg = AppColors.textSecondary;
        icon = CupertinoIcons.question_circle_fill;
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 8 : 10,
        vertical: isSmall ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isSmall ? 11 : 13, color: fg),
          const SizedBox(width: 4),
          Text(
            verdict.label,
            style: AppTypography.badge.copyWith(
              color: fg,
              fontSize: isSmall ? 10.5 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

