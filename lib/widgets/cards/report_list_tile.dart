import 'package:flutter/material.dart';

import '../../models/authentication_result.dart';
import '../../models/category_item.dart';
import '../common/app_image.dart';
import '../ui/ui.dart';
import 'category_art.dart';

/// The prototype's report row (`.item` / `reportItem()` in screens1.js):
/// thumbnail, name, subtitle, verdict pill + evidence pill, chevron.
///
/// The thumbnail is the user's own photo of the item ([AppImage]) with the
/// category artwork as the fallback.
class LenzReportTile extends StatelessWidget {
  const LenzReportTile({
    super.key,
    required this.report,
    required this.subtitle,
    required this.onTap,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  final AuthenticationReport report;
  final String subtitle;
  final VoidCallback onTap;
  final EdgeInsetsGeometry margin;

  /// Second pill: the engine's qualitative evidence strength for v3+ reports
  /// ("Strong" / "Moderate" / "Limited"), or the stored percentage that older
  /// (v1/v2) reports really carry. Never an invented number.
  static String evidenceLabel(AuthenticationReport r) {
    if (!r.usesQualitativeStrength) return '${r.overallScore}%';
    final s = (r.evidenceStrength ?? 'limited').trim();
    if (s.isEmpty) return 'Limited';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  /// "Today, 9:41 AM" / "Yesterday" / "Oct 14" / "Oct 14, 2025".
  static String when(DateTime dt, {DateTime? now}) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      return 'Today, $h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
    }
    if (diff == 1) return 'Yesterday';
    final md = '${months[(dt.month - 1).clamp(0, 11)]} ${dt.day}';
    return dt.year == n.year ? md : '$md, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: LenzPressable(
        onTap: onTap,
        pressedScale: .97,
        semanticLabel: '${report.product.name}, ${report.verdict.label}',
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: LenzColors.paper,
            borderRadius: BorderRadius.circular(LenzRadii.item),
            border: Border.all(color: LenzColors.line),
            boxShadow: LenzShadows.sh1,
          ),
          child: Row(
            children: [
              LenzReportThumb(report: report),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LenzText.item,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 1, bottom: 6),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LenzText.itemSub,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        LenzPill.verdict(report.verdict),
                        LenzPill(
                          label: evidenceLabel(report),
                          background: LenzColors.mint2,
                          foreground: LenzColors.forest,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const LenzIcon(LenzIcons.chevR, size: 18, color: LenzColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// 58px rounded thumbnail: the user's photo, or the category art on mint.
class LenzReportThumb extends StatelessWidget {
  const LenzReportThumb({
    super.key,
    required this.report,
    this.size = 58,
    this.radius = 18,
    this.artSize = 46,
    this.width,
    this.height,
  });

  final AuthenticationReport report;
  final double size;

  /// Overrides [size] per axis (e.g. `double.infinity` to fill the width).
  final double? width;
  final double? height;
  final double radius;
  final double artSize;

  @override
  Widget build(BuildContext context) {
    final art = LenzCategoryArtImage(
      asset: LenzCategoryArt.forReport(report),
      fallbackIcon: CategoryIconHelper.resolveIcon(report.product.categoryLabel),
      size: artSize,
    );
    final path = report.product.imageAsset.trim();
    final w = width ?? size;
    final h = height ?? size;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: LenzColors.mint2,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: path.isEmpty
          ? art
          : AppImage(
              imagePath: path,
              width: w,
              height: h,
              fit: BoxFit.cover,
              placeholder: Center(child: art),
            ),
    );
  }
}
