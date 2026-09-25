import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/authentication_result.dart';
import '../../models/category_item.dart';
import '../../models/product.dart';
import '../../repositories/history_repository.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/verdict_badge.dart';
import '../../widgets/common/app_image.dart';
import '../../services/haptics.dart';

class CategoryBrowseScreen extends StatelessWidget {
  final CategoryItem category;
  final ValueChanged<AuthenticationReport> onOpenReport;
  final VoidCallback onBack;
  final VoidCallback? onStartScan;

  const CategoryBrowseScreen({
    super.key,
    required this.category,
    required this.onOpenReport,
    required this.onBack,
    this.onStartScan,
  });

  factory CategoryBrowseScreen.fromEnum({
    Key? key,
    required ProductCategory category,
    required ValueChanged<AuthenticationReport> onOpenReport,
    required VoidCallback onBack,
    VoidCallback? onStartScan,
  }) {
    return CategoryBrowseScreen(
      key: key,
      category: CategoryItem(
        id: category.name,
        label: category.label,
        icon: CategoryIconHelper.resolveIcon(category.label),
        svgAsset: CategoryIconHelper.resolveSvg(category.label),
        isCustom: false,
      ),
      onOpenReport: onOpenReport,
      onBack: onBack,
      onStartScan: onStartScan,
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final m = months[dt.month - 1];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $m · $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final historyRepo = context.watch<HistoryRepository>();
    final reports = historyRepo.getByCategoryItem(category);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.warmIvory,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Custom Top Bar matching VeriCheck luxury aesthetic
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Row(
                  children: [
                    // Circular Back Button
                    BounceButton(
                      onTap: () {
                        Haptics.lightImpact();
                        onBack();
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.veryLightWarmGray,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.nearBlack.withOpacity(0.08),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.nearBlack.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          CupertinoIcons.chevron_back,
                          size: 18,
                          color: AppColors.nearBlack,
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Title & Category Header
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.label,
                            style: const TextStyle(
                              color: AppColors.nearBlack,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            '${reports.length} ${reports.length == 1 ? 'verified item' : 'verified items'}',
                            style: const TextStyle(
                              color: AppColors.charcoalGray,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Category Icon Badge (Renders SVG if available, else IconData)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.deepForestGreen,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.deepForestGreen.withOpacity(0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: category.svgAsset != null
                            ? (category.svgAsset!.toLowerCase().endsWith('.png')
                                ? Image.asset(
                                    category.svgAsset!,
                                    width: 24,
                                    height: 24,
                                    fit: BoxFit.contain,
                                    color: Colors.white,
                                  )
                                : SvgPicture.asset(
                                    category.svgAsset!,
                                    width: 24,
                                    height: 24,
                                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                  ))
                            : Icon(
                                category.icon,
                                size: 20,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 0.8, color: Color(0xFFEBE6E2)),

              // 2. Body: Either Empty State or Scans List
              Expanded(
                child: reports.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                        itemCount: reports.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final r = reports[i];
                          return FadeSlideTransition(
                            delay: Duration(milliseconds: 60 + (i * 45)),
                            child: _buildReportCard(context, r),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon container matching rounded card style
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.veryLightWarmGray,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFFE8E2DD),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.nearBlack.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: category.svgAsset != null
                    ? (category.svgAsset!.toLowerCase().endsWith('.png')
                        ? Image.asset(
                            category.svgAsset!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.contain,
                            color: AppColors.deepForestGreen,
                          )
                        : SvgPicture.asset(
                            category.svgAsset!,
                            width: 44,
                            height: 44,
                            colorFilter: const ColorFilter.mode(
                              AppColors.deepForestGreen,
                              BlendMode.srcIn,
                            ),
                          ))
                    : Icon(
                        category.icon,
                        size: 38,
                        color: AppColors.deepForestGreen,
                      ),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'No ${category.label} Scans Yet',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.nearBlack,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Scan any ${category.label.toLowerCase()} item to inspect craftsmanship, materials, serials, and get an authentic report from Lenz.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.charcoalGray,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),

            const SizedBox(height: 28),

            if (onStartScan != null)
              BounceButton(
                onTap: () {
                  Haptics.mediumImpact();
                  onBack();
                  onStartScan!();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.deepForestGreen,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.deepForestGreen.withOpacity(0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.camera_fill,
                        color: Colors.white,
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Scan ${category.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(BuildContext context, AuthenticationReport r) {
    return BounceButton(
      onTap: () {
        Haptics.lightImpact();
        onOpenReport(r);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.veryLightWarmGray,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFE8E2DD),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.nearBlack.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail image or Icon fallback
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.veryLightWarmGray,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE8E2DD),
                  width: 0.8,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: r.product.imageAsset.isNotEmpty
                  ? AppImage(
                      imagePath: r.product.imageAsset,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                    )
                  : Center(
                      child: Icon(
                        category.icon,
                        size: 24,
                        color: AppColors.deepForestGreen,
                      ),
                    ),
            ),

            const SizedBox(width: 14),

            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.product.name,
                    style: const TextStyle(
                      color: AppColors.nearBlack,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${r.product.brand} · ${r.product.model}',
                    style: const TextStyle(
                      color: AppColors.charcoalGray,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.clock,
                        size: 11,
                        color: AppColors.softGray,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(r.timestamp),
                        style: const TextStyle(
                          color: AppColors.softGray,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Verdict Badge & Score
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                VerdictBadge(verdict: r.verdict, isSmall: true),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.veryLightWarmGray,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${r.overallScore}% match',
                    style: const TextStyle(
                      color: AppColors.nearBlack,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 6),

            const Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: AppColors.softGray,
            ),
          ],
        ),
      ),
    );
  }
}
