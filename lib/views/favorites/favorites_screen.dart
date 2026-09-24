import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/authentication_result.dart';
import '../../models/product.dart';
import '../../viewmodels/favorites_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/animated_favorite_button.dart';
import '../../widgets/cards/category_chip.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';

class FavoritesScreen extends StatelessWidget {
  final ValueChanged<AuthenticationReport> onOpenReport;

  const FavoritesScreen({super.key, required this.onOpenReport});

  @override
  Widget build(BuildContext context) {
    final favoritesVm = context.watch<FavoritesViewModel>();
    final items = favoritesVm.favoriteReports;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Text('Favorites', style: AppTypography.displayMedium),
            ),

            // Category Filter Chips
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  CategoryFilterChip(
                    label: 'All',
                    isSelected: favoritesVm.selectedCategory == null,
                    onTap: () => favoritesVm.selectCategory(null),
                  ),
                  const SizedBox(width: 8),
                  // Only categories the user has favourites in (§33).
                  ...ProductCategory.values
                      .where((c) => favoritesVm.allFavorites.any((r) => r.product.category == c))
                      .map((cat) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: CategoryFilterChip(
                        label: cat.label,
                        isSelected: favoritesVm.selectedCategory == cat,
                        onTap: () => favoritesVm.selectCategory(cat),
                      ),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Favorites List or Empty State
            Expanded(
              child: items.isEmpty
                  ? EmptyState(
                      title: favoritesVm.selectedCategory == null
                          ? 'No favourites yet'
                          : 'No ${favoritesVm.selectedCategory!.label.toLowerCase()} favourites',
                      message:
                          'Tap the heart on any report you want to keep close. Only reports from your own scans appear here.',
                      mascotState: MascotState.idle,
                      mascotSize: 86,
                    )
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final report = items[i];
                        return FadeSlideTransition(
                          delay: Duration(milliseconds: 60 + (i * 35)),
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
                                    fit: BoxFit.contain,
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
                                          report.product.subtitle,
                                          style: AppTypography.caption,
                                        ),
                                      ],
                                    ),
                                  ),
                                  AnimatedFavoriteButton(
                                    isFavorite: report.isFavorite,
                                    onToggle: () => favoritesVm.toggleFavorite(report.id),
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
}
