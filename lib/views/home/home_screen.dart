import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../core/theme/app_colors.dart';
import '../../models/authentication_result.dart';
import '../../models/category_item.dart';
import '../../services/auth_service.dart';
import '../../viewmodels/home_viewmodel.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/category_chip.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/tour/home_tour_card.dart';
import '../../services/haptics.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onStartScan;
  final ValueChanged<AuthenticationReport> onOpenReport;
  final ValueChanged<CategoryItem> onOpenCategory;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenSettings;
  final VoidCallback onOpenGuides;
  final VoidCallback onOpenHistory;
  final VoidCallback? onOpenNotifications;

  /// Home-tour coach-mark targets, in step order. Owned by
  /// `MainNavigationShell` (which also registers the `ShowcaseView` and
  /// drives the account-scoped first-time auto-show) so they stay stable
  /// across this screen's rebuilds; see home_tour_service.dart.
  final GlobalKey tourHeroKey;
  final GlobalKey tourBrowseKey;
  final GlobalKey tourRecentKey;
  final GlobalKey tourProfileKey;
  final GlobalKey tourNavKey;

  const HomeScreen({
    super.key,
    required this.onStartScan,
    required this.onOpenReport,
    required this.onOpenCategory,
    required this.onOpenProfile,
    this.onOpenSettings,
    required this.onOpenGuides,
    required this.onOpenHistory,
    this.onOpenNotifications,
    required this.tourHeroKey,
    required this.tourBrowseKey,
    required this.tourRecentKey,
    required this.tourProfileKey,
    required this.tourNavKey,
  });

  /// Step order and copy for the Home tour - kept next to the screen it
  /// describes rather than in the controller, since it's just static content.
  static const List<({String title, String description})> tourSteps = [
    (
      title: 'Scan Anything',
      description: 'Start here to check whether an item looks authentic. Upload the item and begin your authenticity check.',
    ),
    (
      title: 'Browse Your Items',
      description: 'Jump straight into a category to quickly find the type of item you want to check.',
    ),
    (
      title: 'Recent Checks',
      description: 'Your previous authenticity checks and reports will appear here for easy access.',
    ),
    (
      title: 'Your Profile',
      description:
          'Manage your account, scan credits, and app settings from here.',
    ),
    (
      title: 'Quick Navigation',
      description: 'Jump between Home, Scan, History, Favorites, and your Profile anytime from here.',
    ),
  ];

  /// Starts the Home tour from Step 1, ignoring whether this account has
  /// already seen it - used by both the automatic first-time trigger
  /// (MainNavigationShell) and this screen's manual "?" replay icon.
  List<GlobalKey> get tourKeysInOrder => [
    tourHeroKey,
    tourBrowseKey,
    tourRecentKey,
    tourProfileKey,
    tourNavKey,
  ];

  @override
  Widget build(BuildContext context) {
    final homeVm = context.watch<HomeViewModel>();
    final profileVm = context.watch<ProfileViewModel>();
    final authService = context.watch<AuthService>();
    final recent = homeVm.filteredReports;
    final hasFilteredReports = recent.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Greeting (Hello, {name} 👋) + Profile Button at top right
              _buildTopHeader(context, profileVm, authService),

              const SizedBox(height: 18),

              // Hero Banner Card: Lenz Mascot & Scan Anything CTA
              Showcase.withWidget(
                key: tourHeroKey,
                container: HomeTourCard(
                  title: tourSteps[0].title,
                  description: tourSteps[0].description,
                  stepIndex: 0,
                  totalSteps: tourSteps.length,
                ),
                targetBorderRadius: BorderRadius.circular(24),
                targetPadding: const EdgeInsets.all(4),
                onBarrierClick: () => ShowcaseView.get().dismiss(),
                disableDefaultTargetGestures: true,
                disableMovingAnimation: true,
                child: _buildHeroCard(context),
              ),

              const SizedBox(height: 22),

              // Browse Your Items Section (Dynamic Vector Category Icons)
              Showcase.withWidget(
                key: tourBrowseKey,
                container: HomeTourCard(
                  title: tourSteps[1].title,
                  description: tourSteps[1].description,
                  stepIndex: 1,
                  totalSteps: tourSteps.length,
                ),
                targetBorderRadius: BorderRadius.circular(16),
                targetPadding: const EdgeInsets.all(6),
                onBarrierClick: () => ShowcaseView.get().dismiss(),
                disableDefaultTargetGestures: true,
                disableMovingAnimation: true,
                child: _buildBrowseSection(context, homeVm),
              ),

              const SizedBox(height: 22),

              // Your Recent Checks Section (Zero Dummy Data, Real Scans or Clean Empty State)
              Showcase.withWidget(
                key: tourRecentKey,
                container: HomeTourCard(
                  title: tourSteps[2].title,
                  description: tourSteps[2].description,
                  stepIndex: 2,
                  totalSteps: tourSteps.length,
                ),
                targetBorderRadius: BorderRadius.circular(20),
                targetPadding: const EdgeInsets.all(6),
                onBarrierClick: () => ShowcaseView.get().dismiss(),
                disableDefaultTargetGestures: true,
                disableMovingAnimation: true,
                child: _buildRecentChecksSection(
                  context,
                  homeVm,
                  recent,
                  hasFilteredReports,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Top Bar: Greeting ("Hello, {name} 👋" & subtitle) + Profile button at top-right
  Widget _buildTopHeader(
    BuildContext context,
    ProfileViewModel profileVm,
    AuthService authService,
  ) {
    final isGuest = authService.isAnonymous;
    final user = profileVm.user;
    String displayName;
    if (isGuest) {
      displayName =
          (user.name.isNotEmpty &&
              user.name != 'Collector' &&
              user.name != 'Guest Collector')
          ? user.name
          : 'Guest';
    } else {
      if (user.name.isNotEmpty &&
          user.name != 'Collector' &&
          user.name != 'Guest Collector') {
        displayName = user.name;
      } else if (authService.currentUser?.displayName?.isNotEmpty == true &&
          authService.currentUser!.displayName != 'Collector' &&
          authService.currentUser!.displayName != 'Guest Collector') {
        displayName = authService.currentUser!.displayName!;
      } else if (authService.currentUser?.email?.contains('@') == true) {
        final prefix = authService.currentUser!.email!.split('@').first.trim();
        displayName = prefix.isNotEmpty
            ? (prefix[0].toUpperCase() + prefix.substring(1))
            : 'Collector';
      } else {
        displayName = 'Collector';
      }
    }

    return FadeSlideTransition(
      delay: const Duration(milliseconds: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting text: Hello, {name} 👋 & Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Hello, $displayName',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.nearBlack,
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('👋', style: TextStyle(fontSize: 25)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Let’s check something authentic today.',
                  style: TextStyle(
                    color: AppColors.charcoalGray,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Home-tour replay button: always restarts the full tour from Step
          // 1 regardless of the persisted "seen" flag (manual replay is
          // independent of the automatic first-time trigger).
          Semantics(
            label: 'Show home tour',
            button: true,
            child: BounceButton(
              onTap: () {
                Haptics.lightImpact();
                ShowcaseView.get().startShowCase(tourKeysInOrder);
              },
              child: Tooltip(
                message: 'Show tour',
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.veryLightWarmGray,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.nearBlack.withOpacity(0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.nearBlack.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.question_circle,
                    size: 19,
                    color: AppColors.charcoalGray,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Profile Button at top right (replaces previous settings icon)
          Showcase.withWidget(
            key: tourProfileKey,
            container: HomeTourCard(
              title: tourSteps[3].title,
              description: tourSteps[3].description,
              stepIndex: 3,
              totalSteps: tourSteps.length,
            ),
            targetShapeBorder: const CircleBorder(),
            targetPadding: const EdgeInsets.all(4),
            onBarrierClick: () => ShowcaseView.get().dismiss(),
            disableDefaultTargetGestures: true,
            disableMovingAnimation: true,
            child: BounceButton(
              onTap: () {
                Haptics.lightImpact();
                onOpenProfile();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.veryLightWarmGray,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.nearBlack.withOpacity(0.08),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.nearBlack.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child:
                      (user.avatarPath != null && user.avatarPath!.isNotEmpty)
                      ? AppImage(
                          imagePath: user.avatarPath!,
                          fit: BoxFit.cover,
                          placeholder: Image.asset(
                            'assets/images/mascot_home.png',
                            fit: BoxFit.cover,
                          ),
                        )
                      : Image.asset(
                          'assets/images/mascot_home.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              CupertinoIcons.person_fill,
                              size: 21,
                              color: AppColors.deepForestGreen,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. Hero Card: "Need me to check something?" with Lenz Mascot (User uploaded image)
  Widget _buildHeroCard(BuildContext context) {
    return FadeSlideTransition(
      delay: const Duration(milliseconds: 90),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.veryLightWarmGray,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.nearBlack.withOpacity(0.05),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.nearBlack.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top Section: Left Text/CTA + Right Mascot
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left Content
                  Expanded(
                    flex: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Lenz Pill Tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.veryLightWarmGray,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6.5,
                                height: 6.5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2EA44F),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'Lenz',
                                style: TextStyle(
                                  color: AppColors.nearBlack,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 7),
                              const Text(
                                '·||·',
                                style: TextStyle(
                                  color: AppColors.deepForestGreen,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Headline
                        const Text(
                          'Need me to check\nsomething?',
                          style: TextStyle(
                            color: AppColors.nearBlack,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.3,
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Description
                        const Text(
                          'Show me the item and I\'ll look for the details that matter.',
                          style: TextStyle(
                            color: AppColors.charcoalGray,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Pill Button: [Camera] Scan Anything ->
                        BounceButton(
                          onTap: onStartScan,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.deepForestGreen,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.deepForestGreen.withOpacity(
                                    0.25,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  CupertinoIcons.camera,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Scan Anything',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 5),
                                Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 4),

                  // Right: Mascot Lenz (Using User Uploaded Image with Transparent Background)
                  Expanded(
                    flex: 9,
                    child: Image.asset(
                      'assets/images/home_mascot_lenz_user.png',
                      height: 165,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),

            // Subtle divider line
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                height: 1,
                thickness: 0.8,
                color: AppColors.nearBlack.withOpacity(0.06),
              ),
            ),

            // Bottom status strip: 🛡️ 3K+ scans checked | ⏱️ Under 30 sec
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.shield,
                    size: 14,
                    color: AppColors.nearBlack,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Check up to 10K items',
                    style: TextStyle(
                      color: AppColors.charcoalGray,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 1,
                    height: 11,
                    color: AppColors.nearBlack.withOpacity(0.12),
                  ),
                  const Spacer(),
                  const Icon(
                    CupertinoIcons.clock,
                    size: 14,
                    color: AppColors.nearBlack,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Under 30 sec',
                    style: TextStyle(
                      color: AppColors.charcoalGray,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 5. "Browse your items" Section with dynamic vector icon cards
  Widget _buildBrowseSection(BuildContext context, HomeViewModel homeVm) {
    final categories = homeVm.categories;

    return FadeSlideTransition(
      delay: const Duration(milliseconds: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header (Without 'See all' as requested)
          const Text(
            'Browse your items',
            style: TextStyle(
              color: AppColors.nearBlack,
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 12),

          // Horizontal scrollable categories row with vector icons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: categories.map((cat) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: BounceButton(
                    onTap: () {
                      Haptics.selectionClick();
                      onOpenCategory(cat);
                    },
                    child: CategoryBrowseCard.fromItem(
                      category: cat,
                      isSelected: false,
                      onTap: () {
                        Haptics.selectionClick();
                        onOpenCategory(cat);
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 6. "Your recent checks" Section (ZERO DUMMY DATA)
  Widget _buildRecentChecksSection(
    BuildContext context,
    HomeViewModel homeVm,
    List<AuthenticationReport> recent,
    bool hasFilteredReports,
  ) {
    return FadeSlideTransition(
      delay: const Duration(milliseconds: 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                homeVm.selectedCategoryItem != null
                    ? '${homeVm.selectedCategoryItem!.label} checks'
                    : 'Your recent checks',
                style: const TextStyle(
                  color: AppColors.nearBlack,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              GestureDetector(
                onTap: onOpenHistory,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'See all',
                      style: TextStyle(
                        color: AppColors.charcoalGray,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward,
                      size: 13,
                      color: AppColors.charcoalGray,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // If there are real scans matching the filter, render them
          if (hasFilteredReports)
            ...recent.map(
              (report) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BounceButton(
                  onTap: () => onOpenReport(report),
                  child: _buildReportCard(context, report),
                ),
              ),
            )
          else
            // Clean empty state card (Zero fake dummy data)
            _buildEmptyRecentChecks(
              context,
              categoryLabel: homeVm.selectedCategoryItem?.label,
            ),
        ],
      ),
    );
  }

  /// Clean Empty State Card for Recent Checks (Zero dummy Rolex)
  Widget _buildEmptyRecentChecks(
    BuildContext context, {
    String? categoryLabel,
  }) {
    final title = categoryLabel != null
        ? 'No $categoryLabel scans yet'
        : 'No recent checks yet';
    final desc = categoryLabel != null
        ? 'Scan a $categoryLabel item and Lenz will verify its stitching, logos, and materials.'
        : 'Tap "Scan Anything" above to run your first forensic inspection with Lenz.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: AppColors.veryLightWarmGray,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.nearBlack.withOpacity(0.05),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.nearBlack.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: AppColors.veryLightWarmGray,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.doc_text_search,
              size: 24,
              color: AppColors.deepForestGreen,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.nearBlack,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.charcoalGray,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          BounceButton(
            onTap: onStartScan,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 9.5,
              ),
              decoration: BoxDecoration(
                color: AppColors.deepForestGreen,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepForestGreen.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(CupertinoIcons.camera, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Start First Scan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Dynamic Report Card when real scan exists
  Widget _buildReportCard(BuildContext context, AuthenticationReport report) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.veryLightWarmGray,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.nearBlack.withOpacity(0.05),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.nearBlack.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AppImage(
              imagePath: report.product.imageAsset,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.product.name,
                  style: const TextStyle(
                    color: AppColors.nearBlack,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  report.product.subtitle,
                  style: const TextStyle(
                    color: AppColors.softGray,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: report.verdict == Verdict.likelyAuthentic
                            ? const Color(0xFFE2EFE7)
                            : report.verdict == Verdict.inconclusive
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        report.verdict == Verdict.likelyAuthentic
                            ? 'Authentic'
                            : (report.verdict == Verdict.likelyReplica
                                  ? 'Replica'
                                  : 'Not Sure'),
                        style: TextStyle(
                          color: report.verdict == Verdict.likelyAuthentic
                              ? AppColors.deepForestGreen
                              : report.verdict == Verdict.inconclusive
                              ? AppColors.warning
                              : AppColors.danger,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.softWarmGray,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${report.overallScore}%',
                        style: const TextStyle(
                          color: AppColors.nearBlack,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.veryLightWarmGray,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.chevron_right,
              size: 13,
              color: AppColors.charcoalGray,
            ),
          ),
        ],
      ),
    );
  }
}
