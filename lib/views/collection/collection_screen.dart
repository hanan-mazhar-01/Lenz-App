import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/authentication_result.dart';
import '../../models/collection_item.dart';
import '../../models/product.dart';
import '../../repositories/collection_repository.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/cards/category_chip.dart';
import '../../widgets/cards/verdict_badge.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';

/// Items the user saved from their own reports. Starts empty (§30).
class CollectionScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onScanItem;

  const CollectionScreen({
    super.key,
    required this.onBack,
    required this.onScanItem,
  });

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  ProductCategory? _selectedCategory;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _showItemDetails(BuildContext context, CollectionItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        decoration: BoxDecoration(
          color: AppColors.backgroundOf(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.neutralPillOf(ctx),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppImage(
                    imagePath: item.imageAsset,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VerdictBadge(verdict: item.verdict, isSmall: true),
                        const SizedBox(height: 6),
                        Text(
                          item.name,
                          style: AppTypography.titleLarge.copyWith(
                            color: AppColors.textPrimaryOf(ctx),
                          ),
                        ),
                        Text(
                          '${item.category.label} · ${item.brand}',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 10),
              _detailRow(ctx, 'Result', item.verdict.label),
              const SizedBox(height: 8),
              _detailRow(ctx, 'Authentication Confidence', '${item.authenticationConfidence}%'),
              if (item.evidenceCoverageText.isNotEmpty) ...[
                const SizedBox(height: 8),
                _detailRow(ctx, 'Evidence Coverage', item.evidenceCoverageText),
              ],
              if (item.model.isNotEmpty) ...[
                const SizedBox(height: 8),
                _detailRow(ctx, 'Model', item.model),
              ],
              const SizedBox(height: 8),
              _detailRow(ctx, 'Scanned', _formatDate(item.scannedDate)),
              const SizedBox(height: 8),
              _detailRow(ctx, 'Saved', _formatDate(item.savedDate)),
              if (item.notes != null && item.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'ASSESSMENT',
                  style: AppTypography.captionMedium.copyWith(
                    letterSpacing: 0.8,
                    color: AppColors.textSecondaryOf(ctx),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.notes!,
                  style: AppTypography.bodyMedium.copyWith(fontSize: 13, height: 1.45),
                ),
              ],
              const SizedBox(height: 20),
              BounceButton(
                onTap: () {
                  context.read<CollectionRepository>().removeItem(item.id);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Text(
                    'Remove from Collection',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(label, style: AppTypography.caption),
        ),
        Expanded(
          flex: 5,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTypography.captionMedium.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ),
      ],
    );
  }

  Color _verdictColor(Verdict v) {
    switch (v) {
      case Verdict.likelyAuthentic:
        return AppColors.accent;
      case Verdict.likelyReplica:
        return AppColors.danger;
      case Verdict.inconclusive:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CollectionRepository>();
    final items = repo.getByCategory(_selectedCategory);
    final verifiedCount = repo.allItems.where((i) => i.verdict == Verdict.likelyAuthentic).length;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back),
          onPressed: widget.onBack,
        ),
        title: const Text('My Collection'),
      ),
      body: SafeArea(
        child: repo.allItems.isEmpty
            ? EmptyState(
                title: 'Your collection is empty',
                message:
                    'Items you save from a report will appear here, with the result and evidence coverage from that scan.',
                actionLabel: 'Scan an Item',
                onAction: widget.onScanItem,
                mascotState: MascotState.curious,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---------------------------------------- summary
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: FadeSlideTransition(
                      child: GlassCard(
                        padding: const EdgeInsets.all(18),
                        borderRadius: 22,
                        child: Row(
                          children: [
                            _summaryStat(context, '${repo.totalCount}', 'Saved items'),
                            Container(
                              width: 1,
                              height: 34,
                              color: AppColors.borderOf(context),
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            _summaryStat(context, '$verifiedCount', 'Likely authentic'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---------------------------------------- filters
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        CategoryFilterChip(
                          label: 'All',
                          isSelected: _selectedCategory == null,
                          onTap: () => setState(() => _selectedCategory = null),
                        ),
                        const SizedBox(width: 8),
                        // Only categories the user actually has items in.
                        ...ProductCategory.values
                            .where((c) => repo.allItems.any((i) => i.category == c))
                            .map(
                              (cat) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: CategoryFilterChip(
                                  label: cat.label,
                                  isSelected: _selectedCategory == cat,
                                  onTap: () => setState(() => _selectedCategory = cat),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ---------------------------------------- grid
                  Expanded(
                    child: items.isEmpty
                        ? EmptyState(
                            title: 'Nothing saved here yet',
                            message:
                                'You have no ${_selectedCategory?.label.toLowerCase()} saved to your collection.',
                            mascotSize: 76,
                          )
                        : GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.78,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, i) {
                              final item = items[i];
                              return FadeSlideTransition(
                                delay: Duration(milliseconds: 60 + (i * 40)),
                                child: BounceButton(
                                  onTap: () => _showItemDetails(context, item),
                                  child: GlassCard(
                                    padding: const EdgeInsets.all(11),
                                    borderRadius: 20,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _verdictColor(item.verdict)
                                                    .withValues(alpha: 0.14),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '${item.authenticationConfidence}%',
                                                style: TextStyle(
                                                  color: _verdictColor(item.verdict),
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _formatDate(item.scannedDate),
                                              style: AppTypography.caption.copyWith(fontSize: 9.5),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Expanded(
                                          child: Center(
                                            child: AppImage(
                                              imagePath: item.imageAsset,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.titleMedium.copyWith(
                                            fontSize: 13,
                                            color: AppColors.textPrimaryOf(context),
                                          ),
                                        ),
                                        Text(
                                          item.verdict.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.caption.copyWith(
                                            fontSize: 10.5,
                                            color: _verdictColor(item.verdict),
                                          ),
                                        ),
                                      ],
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

  Widget _summaryStat(BuildContext context, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTypography.scoreNumber.copyWith(
            fontSize: 26,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        Text(label, style: AppTypography.caption.copyWith(fontSize: 11.5)),
      ],
    );
  }
}
