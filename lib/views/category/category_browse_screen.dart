import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/authentication_result.dart';
import '../../models/category_item.dart';
import '../../models/product.dart';
import '../../repositories/history_repository.dart';
import '../../services/haptics.dart';
import '../../widgets/cards/category_art.dart';
import '../../widgets/cards/report_list_tile.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// One category's checks (prototype `SCREENS.category`): top bar, category
/// header card, the user's reports in that category (or Lenz's empty state)
/// and the pulsing "Scan (category)" button.
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

  static const Color _mood = Color(0xFFD9ECDF);

  @override
  Widget build(BuildContext context) {
    final historyRepo = context.watch<HistoryRepository>();
    final reports = historyRepo.getByCategoryItem(category);
    final label = category.label;
    final topPad = MediaQuery.paddingOf(context).top + 14;
    final bottomPad = MediaQuery.paddingOf(context).bottom + 28;

    final children = <Widget>[
      LenzTopBar(
        title: label,
        onBack: () {
          Haptics.lightImpact();
          onBack();
        },
      ),
      _header(reports.length),
      const SizedBox(height: 16),
      if (reports.isNotEmpty)
        for (final r in reports)
          LenzReportTile(
            report: r,
            subtitle: '${r.product.brand} · ${LenzReportTile.when(r.timestamp)}',
            onTap: () {
              Haptics.lightImpact();
              onOpenReport(r);
            },
          )
      else
        _empty(),
      if (onStartScan != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: LenzButton(
            label: 'Scan ${label.toLowerCase()}',
            icon: LenzIcons.camera,
            pulse: true,
            onPressed: () {
              Haptics.mediumImpact();
              onBack();
              onStartScan!();
            },
          ),
        ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        backgroundColor: LenzColors.ivory,
        body: LenzMoodBackground(
          mood: _mood,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, topPad + 8, 20, bottomPad),
            children: [
              for (var i = 0; i < children.length; i++) LenzRise(index: i, child: children[i]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(int count) {
    final art = LenzCategoryArt.forItem(category);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LenzGradients.css(135, const [Color(0xFFFFFFFF), Color(0xFFE7F2EB)]),
        border: Border.all(color: LenzColors.line),
        boxShadow: LenzShadows.sh1,
      ),
      child: Row(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: LenzColors.paper,
              borderRadius: BorderRadius.circular(28),
              boxShadow: LenzShadows.sh1,
            ),
            alignment: Alignment.center,
            child: art != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(art, width: 62, height: 62, fit: BoxFit.cover),
                  )
                : Icon(category.icon, size: 34, color: LenzColors.forest2),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LenzText.display.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 2),
                Text('$count ${count == 1 ? 'check' : 'checks'} so far', style: LenzText.sub),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final label = category.label;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          const SizedBox(
            width: 210,
            child: LenzCharacter(mood: LenzMood.hello, view: LenzView.full),
          ),
          const SizedBox(height: 8),
          Text('No $label scans yet', textAlign: TextAlign.center, style: LenzText.title),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              'Scan any ${label.toLowerCase()} item to inspect craftsmanship, materials and details.',
              textAlign: TextAlign.center,
              style: LenzText.sub,
            ),
          ),
        ],
      ),
    );
  }
}
