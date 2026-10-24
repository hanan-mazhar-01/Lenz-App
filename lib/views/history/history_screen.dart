import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/authentication_result.dart';
import '../../models/product.dart';
import '../../repositories/authentication_repository.dart';
import '../../repositories/history_repository.dart';
import '../../viewmodels/history_viewmodel.dart';
import '../../widgets/cards/category_chip.dart';
import '../../widgets/cards/report_list_tile.dart';
import '../../widgets/cards/tab_title.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/guest_session.dart';
import '../paywall/guest_paywall_screen.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// History tab (prototype `SCREENS.history`): title + Lenz peek, search,
/// category filter chips and the swipe-to-delete list of the user's checks.
class HistoryScreen extends StatefulWidget {
  final ValueChanged<AuthenticationReport> onOpenReport;
  final VoidCallback? onStartScan;

  const HistoryScreen({super.key, required this.onOpenReport, this.onStartScan});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const Color _mood = Color(0xFFE4E0F4);
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    // Created up front (not lazily): the search field is hidden for guests, and
    // a controller first touched in dispose() would read a dead context.
    _search = TextEditingController(text: context.read<HistoryViewModel>().searchQuery);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyVm = context.watch<HistoryViewModel>();
    final isGuest = isGuestSession(context);
    final reports = historyVm.filteredReports;
    final categories = ProductCategory.values
        .where((c) => historyVm.allReports.any((r) => r.product.category == c))
        .toList();
    final topPad = MediaQuery.paddingOf(context).top + 14;
    final bottomPad = LenzTabBar.contentPadding(context);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 6, 20, 0),
      child: LenzStagger(
        children: [
          LenzTabTitle(
            title: 'History',
            subtitle: 'Every check you ran, in one place.',
            mood: LenzMood.idle,
          ),
          if (!(isGuest && reports.isEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _SearchField(
                controller: _search,
                onChanged: historyVm.setSearchQuery,
                onClear: historyVm.searchQuery.isEmpty
                    ? null
                    : () {
                        _search.clear();
                        historyVm.setSearchQuery('');
                      },
              ),
            ),
        ],
      ),
    );

    final chips = SizedBox(
      height: 34 + 18,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        children: [
          CategoryFilterChip(
            label: 'All',
            isSelected: historyVm.selectedCategory == null,
            onTap: () => historyVm.selectCategory(null),
          ),
          for (final cat in categories) ...[
            const SizedBox(width: 8),
            CategoryFilterChip(
              label: cat.label,
              isSelected: historyVm.selectedCategory == cat,
              onTap: () => historyVm.selectCategory(cat),
            ),
          ],
        ],
      ),
    );

    Widget body;
    if (reports.isEmpty) {
      body = isGuest
          ? EmptyState(
              title: 'Create an account to save scans',
              message: 'Guest scans are not saved. Create an account or sign in and every check you run is kept here with its photos and findings.',
              actionLabel: 'Create account',
              actionIcon: LenzIcons.user,
              onAction: () => GuestPaywallScreen.show(context),
              mood: LenzMood.hello,
              characterWidth: 200,
            )
          : historyVm.hasAnyScans
          ? const EmptyState(
              title: 'No matches',
              message: 'No checks match your search or filter. Try clearing them.',
              mood: LenzMood.sorry,
              characterWidth: 200,
            )
          : EmptyState(
              title: 'No scans yet',
              message: 'Every check you run appears here with its photos and findings.',
              actionLabel: widget.onStartScan != null ? 'Scan an item' : null,
              onAction: widget.onStartScan,
              mood: LenzMood.unsure,
              characterWidth: 200,
            );
      body = Padding(
        padding: EdgeInsets.only(bottom: bottomPad - 40),
        child: body,
      );
    } else {
      body = ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 6, 20, bottomPad),
        itemCount: reports.length,
        itemBuilder: (context, i) {
          final report = reports[i];
          return LenzRise(
            key: ValueKey(report.id),
            index: i,
            step: const Duration(milliseconds: 45),
            delay: Duration.zero,
            duration: const Duration(milliseconds: 600),
            child: Dismissible(
              key: Key(report.id),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 10),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(
                  color: LenzColors.badSoft,
                  borderRadius: BorderRadius.circular(LenzRadii.item),
                ),
                child: const LenzIcon(LenzIcons.trash, size: 22, color: LenzColors.bad),
              ),
              onDismissed: (_) {
                final orphaned = context.read<HistoryRepository>().deleteReport(report.id);
                context.read<AuthenticationRepository>().deleteStoredImages(orphaned);
              },
              child: LenzReportTile(
                report: report,
                subtitle: '${report.product.brand} · ${LenzReportTile.when(report.timestamp)}',
                onTap: () => widget.onOpenReport(report),
              ),
            ),
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
            header,
            // Filters only make sense once there is something to filter.
            if (historyVm.hasAnyScans) chips else const SizedBox(height: 12),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// The prototype's 52px search `.field` (focus ring like `LenzField`).
class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.onChanged, this.onClear});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final FocusNode _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasFocus;
    return AnimatedContainer(
      duration: LenzMotion.field,
      curve: Curves.ease,
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.only(left: 16, right: widget.onClear != null ? 6 : 16),
      decoration: BoxDecoration(
        color: LenzColors.paper,
        borderRadius: BorderRadius.circular(LenzRadii.field),
        border: Border.all(color: focused ? LenzColors.forest2 : LenzColors.line, width: 1.5),
        boxShadow: focused
            ? const [BoxShadow(color: LenzColors.focusRing, spreadRadius: 5)]
            : LenzShadows.sh1,
      ),
      child: Row(
        children: [
          const LenzIcon(LenzIcons.search, size: 20, color: LenzColors.subtle),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              maxLines: 1,
              style: LenzText.field,
              cursorColor: LenzColors.forest2,
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search your checks…',
                hintStyle: LenzText.placeholder,
              ),
            ),
          ),
          if (widget.onClear != null)
            LenzPressable(
              onTap: widget.onClear!,
              semanticLabel: 'Clear search',
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Center(child: LenzIcon(LenzIcons.x, size: 18, color: LenzColors.subtle)),
              ),
            ),
        ],
      ),
    );
  }
}
