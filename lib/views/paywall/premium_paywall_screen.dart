import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/haptics.dart';
import '../../services/revenue_cat_service.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';
import '../profile/privacy_sheet.dart';
import '../profile/terms_sheet.dart';

class PremiumPaywallScreen extends StatefulWidget {
  final VoidCallback? onClose;

  /// Test seam: replaces `RevenueCatService.getOfferings` (null in
  /// production, so the real RevenueCat offerings are always used).
  @visibleForTesting
  final Future<Offerings?> Function()? offeringsLoader;

  /// Test seam: replaces `RevenueCatService.isEligibleForIntroOffer` (null in
  /// production).
  @visibleForTesting
  final Future<bool> Function(String productId)? introEligibilityChecker;

  const PremiumPaywallScreen({
    super.key,
    this.onClose,
    this.offeringsLoader,
    this.introEligibilityChecker,
  });

  /// Opens the paywall as a fullscreen modal with Cupertino transition.
  static Future<bool?> show(BuildContext context) {
    Haptics.mediumImpact();
    return Navigator.of(context).push<bool>(
      CupertinoPageRoute(fullscreenDialog: true, builder: (_) => const PremiumPaywallScreen()),
    );
  }

  @override
  State<PremiumPaywallScreen> createState() => _PremiumPaywallScreenState();
}

class _PremiumPaywallScreenState extends State<PremiumPaywallScreen> {
  bool _isLoadingOfferings = true;
  bool _isProcessingPurchase = false;
  bool _isRestoring = false;

  Offerings? _offerings;
  Package? _selectedPackage;

  /// Per-product-id real introductory-offer eligibility, fetched live from
  /// StoreKit/RevenueCat — never assumed. Only a product this map marks
  /// `true` for (and that actually has an `introductoryPrice`) shows trial
  /// copy anywhere on this screen.
  Map<String, bool> _introEligibility = {};

  final LenzController _lenz = LenzController();

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  /// Returns e.g. "3-Day" when [pkg] genuinely has a free introductory offer
  /// this Apple ID is still eligible for — read from the real StoreProduct
  /// plus a live `checkTrialOrIntroductoryPriceEligibility` call, so trial
  /// copy always matches whatever is actually configured in App Store
  /// Connect (and only ever on the product it's configured for).
  String? _trialLabelFor(Package pkg) {
    final intro = pkg.storeProduct.introductoryPrice;
    if (intro == null || intro.price > 0) return null;
    if (_introEligibility[pkg.storeProduct.identifier] != true) return null;
    final n = intro.periodNumberOfUnits;
    final unit = switch (intro.periodUnit) {
      PeriodUnit.day => n == 1 ? 'Day' : 'Days',
      PeriodUnit.week => n == 1 ? 'Week' : 'Weeks',
      PeriodUnit.month => n == 1 ? 'Month' : 'Months',
      PeriodUnit.year => n == 1 ? 'Year' : 'Years',
      PeriodUnit.unknown => null,
    };
    if (unit == null) return null;
    return '$n-$unit';
  }

  Future<void> _loadOfferings() async {
    setState(() => _isLoadingOfferings = true);
    try {
      final offerings = await (widget.offeringsLoader ?? RevenueCatService.getOfferings)();
      final current = offerings?.current;
      final packages = current?.availablePackages ?? <Package>[];

      final eligibility = <String, bool>{};
      for (final pkg in packages) {
        eligibility[pkg.storeProduct.identifier] =
            await (widget.introEligibilityChecker ?? RevenueCatService.isEligibleForIntroOffer)(
              pkg.storeProduct.identifier,
            );
      }

      if (!mounted) return;
      setState(() {
        _offerings = offerings;
        _introEligibility = eligibility;
        // Prefer whichever package actually has an eligible free trial
        // right now; otherwise fall back to monthly, then annual.
        _selectedPackage = packages.isEmpty
            ? null
            : packages.firstWhere(
                (p) => _trialLabelFor(p) != null,
                orElse: () => current?.monthly ?? current?.annual ?? packages.first,
              );
        _isLoadingOfferings = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PremiumPaywall] Error loading offerings: $e');
      }
      if (mounted) setState(() => _isLoadingOfferings = false);
    }
  }

  void _dismiss(bool result) {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _handlePurchase() async {
    if (_isProcessingPurchase || _isRestoring || _selectedPackage == null) {
      return;
    }

    setState(() => _isProcessingPurchase = true);
    Haptics.mediumImpact();

    try {
      final success = await RevenueCatService.purchasePackage(_selectedPackage!);
      if (!mounted) return;

      final isProNow = success || RevenueCatService.isPremiumNotifier.value;
      if (isProNow) {
        final chosenPlan =
            RevenueCatService.activePlanNotifier.value ??
            (_selectedPackage!.packageType == PackageType.annual ? 'Yearly Pro' : 'Monthly Pro');
        try {
          final profileVm = context.read<ProfileViewModel>();
          profileVm.setPremiumStatus(true, planName: chosenPlan);
        } catch (_) {}

        Haptics.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome to $chosenPlan! Unlimited authentications unlocked.'),
            backgroundColor: LenzColors.forest,
          ),
        );
        _dismiss(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(RevenueCatService.friendlyErrorMessage(e)),
            backgroundColor: LenzColors.bad,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingPurchase = false);
    }
  }

  /// The annual package of the current offering, if the store offers one.
  Package? get _annualPackage {
    final current = _offerings?.current;
    if (current == null) return null;
    if (current.annual != null) return current.annual;
    for (final p in current.availablePackages) {
      if (p.packageType == PackageType.annual) return p;
    }
    return null;
  }

  /// A monthly subscriber moving to the yearly plan. Both plans are in one
  /// subscription group in the store, so the store treats this as an upgrade
  /// and replaces the monthly plan.
  Future<void> _handleSwitchToYearly() async {
    final annual = _annualPackage;
    if (annual == null || _isProcessingPurchase || _isRestoring) return;
    setState(() => _selectedPackage = annual);
    await _handlePurchase();
  }

  Future<void> _handleRestore() async {
    if (_isRestoring || _isProcessingPurchase) return;

    setState(() => _isRestoring = true);
    Haptics.lightImpact();

    try {
      final restored = await RevenueCatService.restorePurchases();
      if (!mounted) return;

      final isProNow = restored || RevenueCatService.isPremiumNotifier.value;

      if (isProNow) {
        final chosenPlan = RevenueCatService.activePlanNotifier.value ?? 'Monthly Pro';
        try {
          final profileVm = context.read<ProfileViewModel>();
          profileVm.setPremiumStatus(true, planName: chosenPlan);
        } catch (_) {}

        Haptics.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchases restored successfully! $chosenPlan active.'),
            backgroundColor: LenzColors.forest,
          ),
        );
        _dismiss(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active subscriptions found for this Apple ID.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(RevenueCatService.friendlyErrorMessage(e)),
            backgroundColor: LenzColors.bad,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _openManageSubscription() async {
    Haptics.lightImpact();
    final url = await RevenueCatService.getManagementUrl();
    final uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PremiumPaywall] Could not open manage subscription: $e');
      }
    }
  }

  void _openTermsSheet() {
    Haptics.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const TermsOfServiceSheet(),
    );
  }

  void _openPrivacySheet() {
    Haptics.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const PrivacySecuritySheet(),
    );
  }

  void _openBillingDetails() {
    Haptics.lightImpact();
    showLenzSheet<void>(
      context,
      builder: (sheetContext) {
        const body = TextStyle(
          fontFamily: LenzText.family,
          color: Color(0xFF46544C),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.5,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Billing details',
              style: TextStyle(
                fontFamily: LenzText.family,
                color: LenzColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cancel anytime in App Store settings at least 24 hours before '
              'your renewal date. Subscriptions automatically renew.',
              style: body,
            ),
            const SizedBox(height: 9),
            const Text(
              'Any unused portion of a free trial is forfeited when you '
              'purchase a subscription.',
              style: body,
            ),
            const SizedBox(height: 9),
            const Text('Questions? support@veradostudio.com', style: body),
            const SizedBox(height: 14),
            LenzButton(label: 'Got it', onPressed: () => Navigator.of(sheetContext).pop()),
          ],
        );
      },
    );
  }

  /// Display form of a [_trialLabelFor] label: "3-Days" reads as "3-Day"
  /// when used as an adjective ("3-Day Free Trial"). Copy only.
  static String? _trialCopy(String? label) => label?.replaceFirstMapped(
    RegExp(r'^(\d+)-(Day|Week|Month|Year)s$'),
    (m) => '${m[1]}-${m[2]}',
  );

  static (String, String) _titleAndPeriod(Package pkg) => switch (pkg.packageType) {
    PackageType.annual => ('Yearly', 'per year'),
    PackageType.weekly => ('Weekly', 'per week'),
    _ => ('Monthly', 'per month'),
  };

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final profileVm = context.watch<ProfileViewModel>();
    final isPro = profileVm.isPremium;
    final mq = MediaQuery.of(context);
    // The page never scrolls, so very large accessibility text sizes are
    // capped by how much room the phone has (the mascot shrinks first).
    final cap = mq.size.height < 640
        ? 1.0
        : mq.size.height < 760
        ? 1.1
        : 1.25;
    final userScale = mq.textScaler.scale(10) / 10;
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(userScale.clamp(1.0, cap))),
      child: _PaywallBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final d = _Dims(c.maxWidth, mq.size.height);
              return Padding(
                padding: EdgeInsets.fromLTRB(d.cqw(5.2), 4, d.cqw(5.2), math.max(8, d.cqh(1.6))),
                child: isPro ? _buildCurrentPlanView(d, profileVm) : _buildPurchaseView(d),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _closeButton(_Dims d) {
    return _GlassCircle(
      size: d.barHeight,
      onTap: () {
        Haptics.lightImpact();
        _dismiss(false);
      },
      child: const LenzIcon(LenzIcons.x, size: 18, strokeWidth: 2.4, color: Colors.white),
    );
  }

  Widget _buildHero(_Dims d, LenzMood mood) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: d.cqw(1)),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0, .82, 1],
          ).createShader(r),
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 300,
              child: LenzCharacter(
                mood: mood,
                view: LenzView.bust,
                fx: false,
                interactive: false,
                controller: _lenz,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _proBadge(_Dims d, String label) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          gradient: LenzGradients.gold,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LenzIcon(LenzIcons.crown, size: 13, strokeWidth: 2.4, color: LenzColors.goldInk),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(d.cl(10.5, d.cqw(3), 12), FontWeight.w900, LenzColors.goldInk),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(_Dims d, String text) {
    return Padding(
      padding: EdgeInsets.fromLTRB(0, d.cl(4, d.cqh(1.2), 12), 0, d.cl(6, d.cqh(1.5), 14)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: _t(
            d.cl(22, d.cqw(7.6), 32),
            FontWeight.w900,
            Colors.white,
            height: 1.04,
            spacing: -.035,
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseView(_Dims d) {
    final packages = _offerings?.current?.availablePackages ?? <Package>[];
    final pkg = _selectedPackage;
    final isAnnual = pkg?.packageType == PackageType.annual;
    final trialLabel = _trialCopy(pkg != null ? _trialLabelFor(pkg) : null);

    final (title, period) = pkg != null ? _titleAndPeriod(pkg) : ('', '');
    final buttonText = pkg == null
        ? (_isLoadingOfferings ? 'Loading plans…' : 'Plans unavailable')
        : trialLabel != null
        ? 'Start $trialLabel Free Trial'
        : (isAnnual ? 'Continue with Yearly' : 'Continue with $title');
    final fineText = pkg == null
        ? ' '
        : trialLabel != null
        ? '$trialLabel free, then ${pkg.storeProduct.priceString} $period. Renews automatically; cancel anytime.'
        : '${pkg.storeProduct.priceString} $period. Renews automatically; cancel anytime.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: math.max(0, d.cqh(1.2))),
        _buildTopBar(d),
        _buildHero(d, LenzMood.pleased),
        _proBadge(d, 'Lenz Pro'),
        _title(d, 'Check everything you own'),
        _buildBenefits(d),
        SizedBox(height: d.cl(8, d.cqh(1.8), 16)),
        if (_isLoadingOfferings)
          _buildLoadingPlans(d)
        else if (packages.isNotEmpty)
          _buildPlans(d, packages)
        else
          _buildFallbackPlans(d),
        _buildCta(d, buttonText, enabled: !(_isProcessingPurchase || _isRestoring || pkg == null)),
        _fine(d, fineText),
        _buildLinks(d, showRestore: true),
      ],
    );
  }

  Widget _buildTopBar(_Dims d) {
    return SizedBox(
      height: d.barHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _closeButton(d),
          LenzPressable(
            onTap: _isRestoring ? null : _handleRestore,
            semanticLabel: 'Restore',
            child: Container(
              height: d.barHeight,
              padding: EdgeInsets.symmetric(horizontal: d.cl(12, d.cqw(4), 16)),
              decoration: _glassDecoration(radius: 99),
              alignment: Alignment.center,
              child: _isRestoring
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Restore',
                      style: _t(d.cl(12, d.cqw(3.6), 14), FontWeight.w800, Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefits(_Dims d) {
    const items = [
      (LenzIcons.sparkles, 'Unlimited checks'),
      (LenzIcons.shieldOk, 'Clear verdicts'),
      (LenzIcons.layers, 'Saved vault'),
    ];
    final gap = d.cl(6, d.cqw(2), 10);
    final iconBox = d.cl(28, d.cqw(8.4), 34);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(vertical: d.cl(6, d.cqh(1.2), 12), horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, .08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color.fromRGBO(255, 255, 255, .1)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: iconBox,
                      height: iconBox,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(244, 217, 123, .16),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: LenzIcon(
                        items[i].$1,
                        size: 18,
                        strokeWidth: 2.2,
                        color: LenzColors.gold2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      items[i].$2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _t(
                        d.cl(11, d.cqw(3.2), 13),
                        FontWeight.w800,
                        Colors.white,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingPlans(_Dims d) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: d.cl(14, d.cqh(3), 28)),
      decoration: _glassDecoration(radius: 18),
      child: Column(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3, color: LenzColors.gold2),
          ),
          const SizedBox(height: 10),
          Text('Loading plans…', style: _t(13, FontWeight.w700, _muted)),
        ],
      ),
    );
  }

  /// Shown only when offerings genuinely failed to load (e.g. no network) —
  /// never a guessed/hardcoded price, since that price could differ from
  /// what StoreKit actually charges (App Store Guideline 3.1.1).
  Widget _buildFallbackPlans(_Dims d) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: d.cl(8, d.cqh(1.8), 14), horizontal: 14),
      decoration: _glassDecoration(radius: 18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const LenzIcon(LenzIcons.warn, size: 20, color: LenzColors.gold2),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "Couldn't load subscription plans",
                    maxLines: 1,
                    style: _t(15.5, FontWeight.w900, Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Check your connection and try again.',
              maxLines: 1,
              style: _t(12.5, FontWeight.w700, _muted),
            ),
          ),
          SizedBox(height: d.cl(6, d.cqh(1.4), 12)),
          _GlassButton(
            label: 'Retry',
            icon: LenzIcons.refresh,
            small: true,
            onPressed: _loadOfferings,
          ),
        ],
      ),
    );
  }

  Widget _buildPlans(_Dims d, List<Package> packages) {
    final annual = packages.where((p) => p.packageType == PackageType.annual).toList();
    final Package? wide = annual.isNotEmpty
        ? annual.first
        : (packages.length == 1 ? packages.first : null);
    final rest = packages.where((p) => p != wide).toList();
    final gap = d.cl(6, d.cqw(2), 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide != null) _buildPlanCard(d, wide, wide: true),
        if (wide != null && rest.isNotEmpty) SizedBox(height: gap + 2),
        if (rest.isNotEmpty)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rest.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(child: _buildPlanCard(d, rest[i], wide: false)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPlanCard(_Dims d, Package pkg, {required bool wide}) {
    final selected = _selectedPackage == pkg;
    final isAnnual = pkg.packageType == PackageType.annual;
    final (title, period) = _titleAndPeriod(pkg);
    final price = pkg.storeProduct.priceString;
    final trialLabel = _trialCopy(_trialLabelFor(pkg));
    final sub = trialLabel != null ? '$trialLabel free trial' : 'Cancel anytime';
    final reduced = LenzMotion.reduced(context);
    final dur = Duration(milliseconds: reduced ? 0 : 250);
    final nameStyle = _t(d.cl(14, d.cqw(4.2), 16), FontWeight.w900, Colors.white, height: 1.15);
    final priceStyle = _t(
      wide ? d.cl(17, d.cqw(5.2), 20) : d.cl(14, d.cqw(4.2), 16),
      FontWeight.w900,
      Colors.white,
      height: 1.15,
    );
    final perStyle = _t(d.cl(9.5, d.cqw(2.8), 12), FontWeight.w700, _muted);
    final subStyle = _t(d.cl(10.5, d.cqw(3), 12), FontWeight.w700, _muted, height: 1.2);

    final radio = AnimatedContainer(
      duration: dur,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? LenzColors.gold2 : Colors.transparent,
        border: Border.all(
          color: selected ? LenzColors.gold2 : const Color.fromRGBO(255, 255, 255, .4),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? const LenzIcon(LenzIcons.check, size: 12, strokeWidth: 3.4, color: LenzColors.goldInk)
          : null,
    );

    final Widget content = wide
        ? Row(
            children: [
              radio,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price, maxLines: 1, style: priceStyle),
                  Text(period, maxLines: 1, style: perStyle),
                ],
              ),
            ],
          )
        : Row(
            children: [
              radio,
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, style: nameStyle),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(price, maxLines: 1, style: priceStyle),
                          const SizedBox(width: 4),
                          Text(period, maxLines: 1, style: perStyle),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.lightImpact();
          if (!selected) _lenz.hop();
          setState(() => _selectedPackage = pkg);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: dur,
              curve: LenzMotion.ease,
              padding: EdgeInsets.symmetric(
                vertical: d.cl(8, d.cqh(1.4), 13),
                horizontal: d.cl(11, d.cqw(3.4), 14),
              ),
              decoration: BoxDecoration(
                color: selected
                    ? const Color.fromRGBO(244, 217, 123, .12)
                    : const Color.fromRGBO(255, 255, 255, .07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? LenzColors.gold2 : const Color.fromRGBO(255, 255, 255, .14),
                  width: 1.5,
                ),
                boxShadow: selected
                    ? const [BoxShadow(color: Color.fromRGBO(244, 217, 123, .14), spreadRadius: 3)]
                    : null,
              ),
              child: content,
            ),
            if (wide && isAnnual)
              Positioned(
                left: 44,
                top: -9,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LenzGradients.gold,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'BEST VALUE',
                    style: _t(10, FontWeight.w900, LenzColors.goldInk, spacing: .06),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCta(_Dims d, String label, {required bool enabled, VoidCallback? onTap}) {
    return Padding(
      padding: EdgeInsets.only(top: d.cl(10, d.cqh(2), 16)),
      child: Opacity(
        opacity: enabled || _isProcessingPurchase ? 1 : .45,
        child: LenzPressable(
          onTap: enabled ? (onTap ?? _handlePurchase) : null,
          semanticLabel: label,
          child: Container(
            height: d.cl(48, d.cqh(7), 58),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8E394), Color(0xFFD4AF37)],
              ),
              borderRadius: BorderRadius.circular(99),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(212, 175, 55, .5),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                  spreadRadius: -8,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: _isProcessingPurchase
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: LenzColors.goldInk),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: _t(d.cl(15.5, d.cqw(4.6), 18), FontWeight.w900, LenzColors.goldInk),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _fine(_Dims d, String text) {
    return Padding(
      padding: EdgeInsets.only(top: d.cl(6, d.cqh(1.2), 10)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: _t(
            d.cl(10.5, d.cqw(3), 12),
            FontWeight.w700,
            const Color.fromRGBO(255, 255, 255, .7),
            height: 1.25,
          ),
        ),
      ),
    );
  }

  Widget _buildLinks(_Dims d, {required bool showRestore}) {
    final style = _t(
      d.cl(10.5, d.cqw(3), 12),
      FontWeight.w800,
      const Color.fromRGBO(255, 255, 255, .62),
    );
    final gap = d.cl(8, d.cqw(3), 14);
    final items = <(String, VoidCallback?)>[
      if (showRestore) ('Restore', _isRestoring ? null : _handleRestore),
      ('Terms', _openTermsSheet),
      ('Privacy', _openPrivacySheet),
      ('Billing details', _openBillingDetails),
    ];
    return Padding(
      padding: EdgeInsets.only(top: d.cl(2, d.cqh(.6), 6)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Container(
                  width: 3,
                  height: 3,
                  margin: EdgeInsets.symmetric(horizontal: gap),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.fromRGBO(255, 255, 255, .35),
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: items[i].$2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: Text(
                    items[i].$1,
                    maxLines: 1,
                    style: style.copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: const Color.fromRGBO(255, 255, 255, .3),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPlanView(_Dims d, ProfileViewModel profileVm) {
    final planName = profileVm.user.planName.isNotEmpty ? profileVm.user.planName : 'Lenz Pro';
    // Monthly subscribers can move to the yearly plan from here; yearly
    // subscribers only manage or restore.
    final annual = _annualPackage;
    final canSwitch = annual != null && planName.toLowerCase().contains('monthly');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: math.max(0, d.cqh(1.2))),
        SizedBox(
          height: d.barHeight,
          child: Align(alignment: Alignment.centerRight, child: _closeButton(d)),
        ),
        _buildHero(d, LenzMood.joy),
        _proBadge(d, planName),
        _title(d, 'You are all set'),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Active • Unlimited scans unlocked',
            maxLines: 1,
            textAlign: TextAlign.center,
            style: _t(15, FontWeight.w700, const Color(0xFFB9D0C3)),
          ),
        ),
        SizedBox(height: d.cl(10, d.cqh(2.4), 22)),
        if (canSwitch) ...[
          _buildCta(
            d,
            'Switch to Yearly · ${annual.storeProduct.priceString}/year',
            enabled: !_isProcessingPurchase,
            onTap: _handleSwitchToYearly,
          ),
          const SizedBox(height: 10),
          _GlassButton(label: 'Manage Subscription', onPressed: _openManageSubscription),
        ] else
          _buildCta(d, 'Manage Subscription', enabled: true, onTap: _openManageSubscription),
        const SizedBox(height: 10),
        _GlassButton(
          label: 'Restore Purchases',
          loading: _isRestoring,
          onPressed: _isRestoring ? null : _handleRestore,
        ),
        _buildLinks(d, showRestore: false),
      ],
    );
  }
}

const Color _muted = Color.fromRGBO(255, 255, 255, .62);

TextStyle _t(double size, FontWeight weight, Color color, {double? height, double? spacing}) =>
    TextStyle(
      fontFamily: LenzText.family,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: spacing == null ? null : size * spacing,
    );

BoxDecoration _glassDecoration({required double radius}) => BoxDecoration(
  color: const Color.fromRGBO(255, 255, 255, .07),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: const Color.fromRGBO(255, 255, 255, .14), width: 1.5),
);

/// The phone's own size, used like the mock's `cqw` / `cqh` container units.
class _Dims {
  const _Dims(this.w, this.h);
  final double w;
  final double h;

  double cqw(double v) => w * v / 100;
  double cqh(double v) => h * v / 100;
  double cl(double lo, double v, double hi) => v.clamp(lo, hi).toDouble();
  double get barHeight => cl(36, cqh(5.2), 44);
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.size, required this.onTap, required this.child});

  final double size;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: onTap,
      semanticLabel: 'Close',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color.fromRGBO(255, 255, 255, .12),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, .2)),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Dark paywall surface (mock: linear #173F31 to #0B241A plus an elliptical
/// top glow `radial-gradient(120% 60% at 50% 0, #2A6A50, transparent 62%)`).
class _PaywallBackdrop extends StatelessWidget {
  const _PaywallBackdrop({required this.child});

  final Widget child;

  static const Color glow = Color(0xFF2A6A50);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B241A),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF173F31), Color(0xFF0B241A)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth, h = c.maxHeight;
                final rx = 1.2 * w, ry = .6 * h;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: rx / w.clamp(1, double.infinity),
                      colors: const [glow, Color(0x002A6A50)],
                      stops: const [0, .62],
                      transform: _EllipseY(ry / rx, Offset(w / 2, 0)),
                    ),
                  ),
                );
              },
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _EllipseY extends GradientTransform {
  const _EllipseY(this.scaleY, this.center);
  final double scaleY;
  final Offset center;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..scale(1.0, scaleY)
      ..translate(-center.dx, -center.dy);
  }
}

/// Translucent white button for the dark paywall (`rgba(255,255,255,.1)`).
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final style = small ? LenzText.buttonSm : LenzText.button;
    return LenzPressable(
      onTap: onPressed,
      semanticLabel: label,
      child: Container(
        height: small ? 38 : 50,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, .1),
          borderRadius: BorderRadius.circular(small ? LenzRadii.buttonSm : LenzRadii.button),
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    LenzIcon(icon!, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(label, style: style, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
      ),
    );
  }
}
