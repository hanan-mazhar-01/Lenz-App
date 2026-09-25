import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/authentication_result.dart';
import '../../models/product.dart';
import '../../repositories/authentication_repository.dart';
import '../../repositories/history_repository.dart';
import '../../viewmodels/history_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/category_chip.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/cards/verdict_badge.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/common/empty_state.dart';

class HistoryScreen extends StatelessWidget {
  final ValueChanged<AuthenticationReport> onOpenReport;
  final VoidCallback? onStartScan;

  const HistoryScreen({super.key, required this.onOpenReport, this.onStartScan});

  @override
  Widget build(BuildContext context) {
    final historyVm = context.watch<HistoryViewModel>();
    final reports = historyVm.filteredReports;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text('History', style: AppTypography.displayMedium),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.search, size: 18, color: AppColors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: historyVm.setSearchQuery,
                        decoration: InputDecoration(
                          hintText: 'Search your checks...',
                          hintStyle: AppTypography.callout,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    if (historyVm.searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () => historyVm.setSearchQuery(''),
                        child: const Icon(CupertinoIcons.clear_circled_solid, size: 16, color: AppColors.textTertiary),
                      ),
                  ],
                ),
              ),
            ),

            // Category Filter Chips
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    CategoryFilterChip(
                      label: 'All',
                      isSelected: historyVm.selectedCategory == null,
                      onTap: () => historyVm.selectCategory(null),
                    ),
                    const SizedBox(width: 8),
                    ...ProductCategory.values
                        .where((c) => historyVm.allReports.any((r) => r.product.category == c))
                        .map((cat) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: CategoryFilterChip(
                          label: cat.label,
                          isSelected: historyVm.selectedCategory == cat,
                          onTap: () => historyVm.selectCategory(cat),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // History List
            Expanded(
              child: reports.isEmpty
                  ? (historyVm.hasAnyScans
                      ? const EmptyState(
                          title: 'No matches',
                          message: 'No checks match your search or filter. Try clearing them.',
                          mascotSize: 76,
                        )
                      : EmptyState(
                          title: 'No scans yet',
                          message:
                              'Every check you run appears here with its photos, findings and result.',
                          actionLabel: onStartScan != null ? 'Scan an Item' : null,
                          onAction: onStartScan,
                          mascotSize: 86,
                        ))
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
                      itemCount: reports.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final report = reports[i];
                        final dateStr =
                            '${_monthName(report.timestamp.month)} ${report.timestamp.day}, ${report.timestamp.year}';

                        return FadeSlideTransition(
                          delay: Duration(milliseconds: 60 + (i * 35)),
                          child: Dismissible(
                            key: Key(report.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: AppColors.dangerBg,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(CupertinoIcons.trash, color: AppColors.danger),
                            ),
                            onDismissed: (_) {
                              final orphaned =
                                  context.read<HistoryRepository>().deleteReport(report.id);
                              context.read<AuthenticationRepository>().deleteStoredImages(orphaned);
                            },
                            child: BounceButton(
                              onTap: () => onOpenReport(report),
                              child: GlassCard(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                borderRadius: 18,
                                child: Row(
                                  children: [
                                    AppImage(
                                      imagePath: report.product.imageAsset,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            report.product.name,
                                            style: AppTypography.titleMedium.copyWith(fontSize: 15),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${report.product.subtitle} · $dateStr',
                                            style: AppTypography.caption,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        VerdictBadge(verdict: report.verdict, isSmall: true),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${report.overallScore}%',
                                          style: AppTypography.captionMedium.copyWith(
                                            color: report.verdict == Verdict.likelyAuthentic
                                                ? AppColors.accent
                                                : report.verdict == Verdict.inconclusive
                                                    ? AppColors.warning
                                                    : AppColors.danger,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[(month - 1).clamp(0, 11)];
  }
}
