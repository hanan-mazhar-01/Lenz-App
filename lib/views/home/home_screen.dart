import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../models/authentication_result.dart';
import '../../models/category_item.dart';
import '../../repositories/history_repository.dart';
import '../../services/auth_service.dart';
import '../../services/haptics.dart';
import '../../viewmodels/home_viewmodel.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/cards/category_chip.dart';
import '../../widgets/cards/report_list_tile.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/common/guest_session.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/tour/home_tour_card.dart';
import '../../widgets/ui/ui.dart';
import '../paywall/guest_paywall_screen.dart';

/// Home tab (prototype `SCREENS.home`): greeting + avatar + tour button, the
/// dark hero card with Lenz, three live stats, the Pro / guest promo, the
/// category carousel and the user's recent checks.
class HomeScreen extends StatefulWidget {
  final VoidCallback onStartScan;
  final ValueChanged<AuthenticationReport> onOpenReport;
  final ValueChanged<CategoryItem> onOpenCategory;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenSettings;
  final VoidCallback onOpenHistory;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenPremium;

  /// Home-tour coach-mark targets, in step order. Owned by
  /// `MainNavigationShell` (which also registers the `ShowcaseView` and
  /// drives the account-scoped first-time auto-show) so they stay stable
  /// across this screen's rebuilds; see home_tour_service.dart.
  final GlobalKey tourHeroKey;
  final GlobalKey tourBrowseKey;
  final GlobalKey tourRecentKey;
  final GlobalKey tourProfileKey;
  final GlobalKey tourNavKey;

  /// The tour target currently in the spotlight (drives the white ring
  /// around the hole). Optional; provided by `MainNavigationShell`.
  final ValueListenable<GlobalKey?>? activeTourTarget;

  const HomeScreen({
    super.key,
    required this.onStartScan,
    required this.onOpenReport,
    required this.onOpenCategory,
    required this.onOpenProfile,
    this.onOpenSettings,
    required this.onOpenHistory,
    this.onOpenNotifications,
    this.onOpenPremium,
    required this.tourHeroKey,
    required this.tourBrowseKey,
    required this.tourRecentKey,
    required this.tourProfileKey,
    required this.tourNavKey,
    this.activeTourTarget,
  });

  /// Step order and copy for the Home tour - kept next to the screen it
  /// describes rather than in the controller, since it's just static content.
  static const List<({String title, String description})> tourSteps = [
    (title: 'Scan anything', description: 'Start here to check whether an item looks authentic.'),
    (
      title: 'Browse your items',
      description: 'Jump straight into a category to find what you want to check.',
    ),
    (title: 'Recent checks', description: 'Your previous reports appear here for easy access.'),
    (
      title: 'Your profile',
      description: 'Manage your account, scan credits and app settings from here.',
    ),
    (
      title: 'Quick navigation',
      description:
          'Hop between Home, History, Favorites and your Profile, or tap the camera to scan.',
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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _mood = Color(0xFFD9ECDF);
  static const _heroLines = [
    'Tap Scan to begin!',
    'I never blink at fakes.',
    'Show me something shiny.',
    'Detective Lenz at your service.',
  ];

  final math.Random _rng = math.Random();
  String _heroBubble = 'Spot fakes before you spend.';

  /// First word of a full name ("Malik Haider" -> "Malik"), so the greeting
  /// stays short. Only applied to real names, not fallbacks like 'Apple User'.
  static String _firstName(String fullName) {
    final trimmed = fullName.trim();
    return trimmed.isEmpty ? trimmed : trimmed.split(RegExp(r'\s+')).first;
  }

  String _displayName(ProfileViewModel profileVm, AuthService authService) {
    final isGuest = authService.isAnonymous;
    final user = profileVm.user;
    final email = authService.currentUser?.email ?? user.email;
    final isPrivateRelay = email.toLowerCase().contains('privaterelay.appleid.com');
    final emailPrefix = email.contains('@') ? email.split('@').first.trim().toLowerCase() : '';

    if (isGuest) {
      return (user.name.isNotEmpty && user.name != 'Collector' && user.name != 'Guest Collector')
          ? _firstName(user.name)
          : 'Guest';
    }
    if (user.name.isNotEmpty &&
        user.name != 'Collector' &&
        user.name != 'Guest Collector' &&
        (!isPrivateRelay || user.name.toLowerCase() != emailPrefix)) {
      return _firstName(user.name);
    }
    final authName = authService.currentUser?.displayName;
    if (authName != null &&
        authName.isNotEmpty &&
        authName != 'Collector' &&
        authName != 'Guest Collector' &&
        (!isPrivateRelay || authName.toLowerCase() != emailPrefix)) {
      return _firstName(authName);
    }
    if (authService.currentUser?.email?.contains('@') == true && !isPrivateRelay) {
      final prefix = authService.currentUser!.email!.split('@').first.trim();
      return prefix.isNotEmpty ? (prefix[0].toUpperCase() + prefix.substring(1)) : 'Collector';
    }
    final isApple =
        authService.currentUser?.providerData.any((p) => p.providerId == 'apple.com') == true;
    return isApple ? 'Apple User' : 'Collector';
  }

  void _startTour() {
    Haptics.lightImpact();
    ShowcaseView.get().startShowCase(widget.tourKeysInOrder);
  }

  Showcase _tourStep(
    int i,
    GlobalKey key,
    Widget child, {
    bool circle = false,
    double radius = 26,
  }) {
    return Showcase.withWidget(
      key: key,
      container: HomeTourCard(
        title: HomeScreen.tourSteps[i].title,
        description: HomeScreen.tourSteps[i].description,
        stepIndex: i,
        totalSteps: HomeScreen.tourSteps.length,
      ),
      targetShapeBorder: circle ? const CircleBorder() : const RoundedRectangleBorder(),
      targetBorderRadius: circle ? null : BorderRadius.circular(radius),
      targetPadding: HomeTourStyle.holePadding,
      overlayColor: HomeTourStyle.overlayColor,
      overlayOpacity: HomeTourStyle.overlayOpacity,
      onBarrierClick: () => ShowcaseView.get().dismiss(),
      disableDefaultTargetGestures: true,
      disableMovingAnimation: true,
      child: HomeTourRing(
        target: key,
        active: widget.activeTourTarget,
        radius: radius,
        circle: circle,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final homeVm = context.watch<HomeViewModel>();
    final profileVm = context.watch<ProfileViewModel>();
    final authService = context.watch<AuthService>();
    final historyRepo = context.watch<HistoryRepository>();

    final isGuest = authService.isAnonymous;
    final isPremium = profileVm.user.isPremium;
    final all = historyRepo.allReports;
    final recent = homeVm.filteredReports;
    final topPad = MediaQuery.paddingOf(context).top + 14;

    var i = 0;
    Widget rise(Widget child) => LenzRise(index: i++, child: child);
    const side = EdgeInsets.symmetric(horizontal: 20);

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: LenzMoodBackground(
        mood: _mood,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(top: topPad, bottom: LenzTabBar.contentPadding(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              rise(Padding(padding: side, child: _greeting(profileVm, authService))),
              const SizedBox(height: 18),
              rise(
                Padding(
                  padding: side,
                  child: _tourStep(0, widget.tourHeroKey, _hero(), radius: 34),
                ),
              ),
              const SizedBox(height: 14),
              rise(
                Padding(
                  padding: side,
                  child: _stats(
                    isPremium: isPremium,
                    scansLeft: profileVm.user.scansRemaining,
                    checks: all.length,
                    authentic: all.where((r) => r.verdict == Verdict.likelyAuthentic).length,
                  ),
                ),
              ),
              // Guests never see Pro: they get the create-account promo.
              // Premium users see neither.
              if (isGuest)
                rise(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: _Promo(
                      icon: LenzIcons.gift,
                      title: 'Create an account',
                      text: 'Save your scans and get your account\'s free scans',
                      onTap: () => GuestPaywallScreen.show(context),
                    ),
                  ),
                )
              else if (!isPremium)
                rise(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: _Promo(
                      icon: LenzIcons.crown,
                      title: 'Upgrade to Lenz Pro',
                      text: 'Unlimited scans and saved reports',
                      pro: true,
                      onTap: () {
                        Haptics.mediumImpact();
                        widget.onOpenPremium?.call();
                      },
                    ),
                  ),
                ),
              rise(_tourStep(1, widget.tourBrowseKey, _browse(homeVm, historyRepo))),
              rise(
                Padding(
                  padding: side,
                  child: _tourStep(2, widget.tourRecentKey, _recent(homeVm, recent)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- greeting

  Widget _greeting(ProfileViewModel profileVm, AuthService authService) {
    final isGuest = authService.isAnonymous;
    final name = _displayName(profileVm, authService);
    final avatarPath = profileVm.user.avatarPath;
    final hasAvatar = avatarPath != null && avatarPath.isNotEmpty;

    final lenzPeek = OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 66,
      maxWidth: 66,
      maxHeight: 80,
      child: Transform.translate(
        offset: const Offset(-7, -4),
        child: const SizedBox(
          width: 66,
          child: LenzCharacter(view: LenzView.peek, fx: false, interactive: false, wake: false),
        ),
      ),
    );

    final avatar = Semantics(
      button: true,
      label: 'Profile',
      child: LenzPressable(
        onTap: () {
          Haptics.lightImpact();
          widget.onOpenProfile();
        },
        pressedScale: .92,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: LenzColors.mint,
            border: Border.all(color: LenzColors.paper, width: 3),
            boxShadow: LenzShadows.sh1,
          ),
          child: ClipOval(
            child: hasAvatar
                ? AppImage(imagePath: avatarPath, fit: BoxFit.cover, placeholder: lenzPeek)
                : lenzPeek,
          ),
        ),
      ),
    );

    return Row(
      children: [
        _tourStep(3, widget.tourProfileKey, avatar, circle: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isGuest ? 'Guest mode' : 'Welcome back',
                style: LenzText.cap.copyWith(fontSize: 13),
              ),
              Text(
                'Hi, $name 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LenzText.title.copyWith(fontSize: 25),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: 'Show tour',
          child: LenzIconButton(
            icon: LenzIcons.help,
            iconSize: 21,
            semanticLabel: 'Show home tour',
            onTap: _startTour,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- hero

  Widget _hero() {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final narrow = w < 330;
        final lenzW = math.min(210.0, w * .6);
        final bubbleW = narrow ? 96.0 : 124.0;
        final headW = math.min(190.0, w - 40 - bubbleW - 6);
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 236),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LenzRadii.hero),
            gradient: LenzGradients.hero,
            boxShadow: LenzShadows.hero,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              const Positioned.fill(child: _HeroHatch()),
              Positioned(
                right: -26,
                bottom: -34,
                width: lenzW,
                child: LenzCharacter(
                  view: LenzView.bust,
                  onTap: () => setState(() {
                    var next = _heroBubble;
                    while (next == _heroBubble) {
                      next = _heroLines[_rng.nextInt(_heroLines.length)];
                    }
                    _heroBubble = next;
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: headW,
                      child: MediaQuery.withClampedTextScaling(
                        // Decorative headline next to the bubble: keep it
                        // from breaking mid-word on small phones.
                        maxScaleFactor: narrow ? 1.0 : 1.15,
                        child: Text(
                          'Need me to check something?',
                          style: LenzText.hero.copyWith(
                            color: Colors.white,
                            fontSize: narrow ? 20 : 25,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: math.min(165.0, w - 40),
                      child: const Text(
                        'Show me the item and I will look for the details that matter.',
                        style: LenzText.heroSub,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _HeroButton(onTap: widget.onStartScan),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: IgnorePointer(
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: narrow ? 1.0 : 1.15,
                    child: LenzBubble(
                      text: _heroBubble,
                      maxWidth: bubbleW,
                      style: LenzText.bubble.copyWith(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------- stats

  Widget _stats({
    required bool isPremium,
    required int scansLeft,
    required int checks,
    required int authentic,
  }) {
    Widget stat(Widget value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          color: LenzColors.paper,
          borderRadius: BorderRadius.circular(LenzRadii.stat),
          border: Border.all(color: LenzColors.line),
          boxShadow: LenzShadows.sh1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label, maxLines: 1, style: LenzText.statLabel),
            ),
          ],
        ),
      ),
    );
    Widget count(int n) => AnimatedCount(
      to: n,
      delay: const Duration(milliseconds: 500),
      duration: const Duration(milliseconds: 1100),
      style: LenzText.stat,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          isPremium
              ? stat(const _InfinityGlyph(), 'Unlimited')
              : stat(count(math.max(0, scansLeft)), 'Scans left'),
          const SizedBox(width: 10),
          stat(count(checks), 'Checks run'),
          const SizedBox(width: 10),
          stat(count(authentic), 'Authentic'),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ browse

  Widget _browse(HomeViewModel homeVm, HistoryRepository historyRepo) {
    final categories = homeVm.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LenzSectionHeader('Browse your items'),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final cat in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: CategoryBrowseCard.fromItem(
                    category: cat,
                    caption: _checks(historyRepo.getByCategoryItem(cat).length),
                    onTap: () {
                      Haptics.selectionClick();
                      widget.onOpenCategory(cat);
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _checks(int n) => '$n ${n == 1 ? 'check' : 'checks'}';

  // ------------------------------------------------------------------ recent

  Widget _recent(HomeViewModel homeVm, List<AuthenticationReport> recent) {
    final selected = homeVm.selectedCategoryItem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LenzSectionHeader(
          selected != null ? '${selected.label} checks' : 'Your recent checks',
          actionLabel: 'See all',
          onAction: widget.onOpenHistory,
          margin: const EdgeInsets.fromLTRB(2, 6, 2, 12),
        ),
        if (recent.isNotEmpty)
          for (final r in recent)
            LenzReportTile(
              report: r,
              subtitle: '${r.product.brand} · ${r.product.categoryLabel}',
              onTap: () => widget.onOpenReport(r),
            )
        else
          _emptyRecent(selected?.label),
      ],
    );
  }

  Widget _emptyRecent(String? categoryLabel) {
    final guest = isGuestSession(context);
    return LenzCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      child: Column(
        children: [
          Transform.translate(
            offset: const Offset(0, -6),
            child: const SizedBox(
              width: 160,
              child: LenzCharacter(mood: LenzMood.unsure, view: LenzView.bust),
            ),
          ),
          Text(
            guest
                ? 'Guest scans are not saved'
                : categoryLabel != null
                ? 'No $categoryLabel scans yet'
                : 'No checks yet',
            textAlign: TextAlign.center,
            style: LenzText.title.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            guest
                ? 'Create an account to keep your scans and favorites here.'
                : categoryLabel != null
                ? 'Scan a ${categoryLabel.toLowerCase()} item and Lenz will check its details.'
                : 'Tap Scan an item to run your first inspection with Lenz.',
            textAlign: TextAlign.center,
            style: LenzText.sub,
          ),
          const SizedBox(height: 16),
          IntrinsicWidth(
            child: LenzButton(
              label: guest ? 'Create account' : 'Start first scan',
              icon: guest ? LenzIcons.user : LenzIcons.camera,
              iconSize: 18,
              size: LenzButtonSize.sm,
              expand: false,
              onPressed: guest ? () => GuestPaywallScreen.show(context) : widget.onStartScan,
            ),
          ),
        ],
      ),
    );
  }
}

/// White "Scan an item" button of the hero (`.hero .btn`): h48, light
/// gradient, deep drop shadow.
class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: onTap,
      semanticLabel: 'Scan an item',
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: LenzGradients.light,
          borderRadius: BorderRadius.circular(LenzRadii.button),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              offset: Offset(0, 12),
              blurRadius: 22,
              spreadRadius: -10,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LenzIcon(LenzIcons.camera, size: 20, color: LenzColors.forest),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Scan an item',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LenzText.button.copyWith(fontSize: 15, color: LenzColors.forest),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.hero::before`: two faint diagonal hatches, masked to fade out towards
/// the bottom-right (`mask-image: linear-gradient(120deg,#000,transparent 70%)`).
class _HeroHatch extends StatelessWidget {
  const _HeroHatch();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LenzGradients.css(
          120,
          const [Color(0xFF000000), Color(0x00000000)],
          const [0, .7],
        ).createShader(rect),
        child: const CustomPaint(painter: _HatchPainter(), size: Size.infinite),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, .035)
      ..strokeWidth = 2;
    // Stripes every 22px measured perpendicular to the 45deg direction.
    const step = 22 * math.sqrt2;
    final span = size.width + size.height;
    for (var d = -span; d < span; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), p);
      canvas.drawLine(Offset(d + size.height, 0), Offset(d, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _HatchPainter oldDelegate) => false;
}

/// `.promo`: dark green strip with a gold hairline and a looping gold
/// shimmer sweep (3.2s). [pro] adds the gold "PRO" pill, otherwise a chevron.
class _Promo extends StatefulWidget {
  const _Promo({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    this.pro = false,
  });

  final String icon;
  final String title;
  final String text;
  final VoidCallback onTap;
  final bool pro;

  @override
  State<_Promo> createState() => _PromoState();
}

class _PromoState extends State<_Promo> with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (LenzMotion.reduced(context)) {
      _shine.stop();
      _shine.value = .5;
    } else if (!_shine.isAnimating) {
      _shine.repeat();
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: widget.onTap,
      semanticLabel: widget.title,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LenzRadii.card),
          gradient: LenzGradients.promo,
          border: Border.all(color: const Color.fromRGBO(212, 175, 55, .45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _shine,
                  builder: (context, _) => CustomPaint(painter: _ShinePainter(_shine.value)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.fromRGBO(244, 217, 123, .2),
                    ),
                    alignment: Alignment.center,
                    child: LenzIcon(widget.icon, size: 22, color: LenzColors.gold2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: LenzText.item.copyWith(color: Colors.white)),
                        Text(
                          widget.text,
                          style: LenzText.itemSub.copyWith(color: const Color(0xFFBCD0C4)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (widget.pro)
                    Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: LenzGradients.gold,
                        borderRadius: BorderRadius.circular(LenzRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('PRO', style: LenzText.pill.copyWith(color: LenzColors.goldInk)),
                          const SizedBox(width: 5),
                          const LenzIcon(
                            LenzIcons.chevR,
                            size: 12,
                            strokeWidth: 3,
                            color: LenzColors.goldInk,
                          ),
                        ],
                      ),
                    )
                  else
                    const LenzIcon(LenzIcons.chevR, size: 18, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `linear-gradient(110deg, transparent 30%, rgba(244,217,123,.28) 50%,
/// transparent 70%)` at `background-size: 200%`, swept from -200% to 200%.
class _ShinePainter extends CustomPainter {
  _ShinePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 2; // background-size 200%
    // background-position -200%..200% of (container - bg) = -w..w offset.
    final dx = -size.width * 2 + t * size.width * 4;
    final rect = Rect.fromLTWH(dx - (w - size.width) / 2, 0, w, size.height);
    final shader = LenzGradients.css(
      110,
      const [Color(0x00F4D97B), Color(0x47F4D97B), Color(0x00F4D97B)],
      const [.3, .5, .7],
    ).createShader(rect);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _ShinePainter old) => old.t != t;
}

/// "Unlimited" mark for Pro users' scan stat, drawn so it never depends on
/// the font having a U+221E glyph (Nunito does not).
class _InfinityGlyph extends StatelessWidget {
  const _InfinityGlyph();

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.textScalerOf(context).scale(26);
    return Semantics(
      label: 'Unlimited',
      child: SizedBox(
        width: h * 1.5,
        height: h,
        child: const CustomPaint(painter: _InfinityPainter()),
      ),
    );
  }
}

class _InfinityPainter extends CustomPainter {
  const _InfinityPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cy = h * .55, r = h * .28;
    final p = Paint()
      ..color = LenzColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * .13
      ..strokeCap = StrokeCap.round;
    final left = w * .28, right = w * .72;
    final path = Path()
      ..moveTo(w / 2, cy)
      ..cubicTo(right - r * .2, cy - r * 1.4, right + r * 1.6, cy - r * 1.2, right + r * 1.0, cy)
      ..cubicTo(right + r * 1.6, cy + r * 1.2, right - r * .2, cy + r * 1.4, w / 2, cy)
      ..cubicTo(left + r * .2, cy - r * 1.4, left - r * 1.6, cy - r * 1.2, left - r * 1.0, cy)
      ..cubicTo(left - r * 1.6, cy + r * 1.2, left + r * .2, cy + r * 1.4, w / 2, cy);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _InfinityPainter oldDelegate) => false;
}
