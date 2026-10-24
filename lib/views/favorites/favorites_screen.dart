import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/authentication_result.dart';
import '../../models/product.dart';
import '../../viewmodels/favorites_viewmodel.dart';
import '../../widgets/cards/animated_favorite_button.dart';
import '../../widgets/cards/category_chip.dart';
import '../../widgets/cards/report_list_tile.dart';
import '../../widgets/cards/tab_title.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/guest_session.dart';
import '../paywall/guest_paywall_screen.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// Favorites ("Saved") tab (prototype `SCREENS.favorites`): two-column cards
/// of the reports the user hearted. Only the user's own reports appear.
class FavoritesScreen extends StatelessWidget {
  final ValueChanged<AuthenticationReport> onOpenReport;

  const FavoritesScreen({super.key, required this.onOpenReport});

  static const Color _mood = Color(0xFFF5D9DE);

  @override
  Widget build(BuildContext context) {
    final favoritesVm = context.watch<FavoritesViewModel>();
    final items = favoritesVm.favoriteReports;
    final categories = ProductCategory.values
        .where((c) => favoritesVm.allFavorites.any((r) => r.product.category == c))
        .toList();
    final topPad = MediaQuery.paddingOf(context).top + 14;
    final bottomPad = LenzTabBar.contentPadding(context);
    final selected = favoritesVm.selectedCategory;
    final isGuest = isGuestSession(context);

    final children = <Widget>[
      Padding(
        padding: EdgeInsets.fromLTRB(20, topPad + 6, 20, 0),
        child: const LenzRise(
          child: LenzTabTitle(
            title: 'Favorites',
            subtitle: 'Reports you want to keep close.',
            mood: LenzMood.joy,
          ),
        ),
      ),
      // Category filter (only categories the user has favourites in, §33).
      if (favoritesVm.allFavorites.isNotEmpty)
        SizedBox(
          height: 34 + 18,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            children: [
              CategoryFilterChip(
                label: 'All',
                isSelected: selected == null,
                onTap: () => favoritesVm.selectCategory(null),
              ),
              for (final cat in categories) ...[
                const SizedBox(width: 8),
                CategoryFilterChip(
                  label: cat.label,
                  isSelected: selected == cat,
                  onTap: () => favoritesVm.selectCategory(cat),
                ),
              ],
            ],
          ),
        ),
    ];

    final Widget body;
    if (items.isEmpty) {
      body = Padding(
        padding: EdgeInsets.only(bottom: bottomPad - 40),
        child: isGuest
            ? EmptyState(
                title: 'Create an account to save favorites',
                message: "Guests can't save favorites. Create an account or sign in to keep the reports you love.",
                actionLabel: 'Create account',
                actionIcon: LenzIcons.user,
                onAction: () => GuestPaywallScreen.show(context),
                mood: LenzMood.hello,
                view: LenzView.full,
                characterWidth: 220,
              )
            : EmptyState(
                title: selected == null
                    ? 'Nothing saved yet'
                    : 'No ${selected.label.toLowerCase()} saved yet',
                message: 'Tap the heart on any report to keep it here. Only reports from your own scans appear.',
                mood: LenzMood.unsure,
                view: LenzView.full,
                characterWidth: 220,
              ),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, c) {
          final rows = <Widget>[];
          for (var i = 0; i < items.length; i += 2) {
            rows.add(
              LenzRise(
                index: i ~/ 2,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _card(favoritesVm, items[i])),
                        const SizedBox(width: 12),
                        Expanded(
                          child: i + 1 < items.length
                              ? _card(favoritesVm, items[i + 1])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPad),
            children: rows,
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: LenzMoodBackground(
        mood: _mood,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...children,
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _card(FavoritesViewModel vm, AuthenticationReport report) {
    return _FavoriteCard(
      report: report,
      onTap: () => onOpenReport(report),
      onToggle: () => vm.toggleFavorite(report.id),
    );
  }
}

/// `.fav-card`: photo tile, name, brand, verdict pill, heart toggle.
class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.report, required this.onTap, required this.onToggle});
  final AuthenticationReport report;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: onTap,
      semanticLabel: '${report.product.name}, ${report.verdict.label}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: LenzColors.paper,
          borderRadius: BorderRadius.circular(LenzRadii.card),
          border: Border.all(color: LenzColors.line),
          boxShadow: LenzShadows.sh1,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LenzReportThumb(
                  report: report,
                  width: double.infinity,
                  height: 104,
                  radius: 20,
                  artSize: 62,
                ),
                const SizedBox(height: 10),
                Text(
                  report.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LenzText.item.copyWith(fontSize: 15),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: Text(
                    report.product.brand,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LenzText.cap,
                  ),
                ),
                const Spacer(),
                LenzPill.verdict(report.verdict),
              ],
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: LenzColors.paper,
                  shape: BoxShape.circle,
                  boxShadow: LenzShadows.sh1,
                ),
                alignment: Alignment.center,
                child: AnimatedFavoriteButton(
                  isFavorite: report.isFavorite,
                  onToggle: onToggle,
                  size: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
