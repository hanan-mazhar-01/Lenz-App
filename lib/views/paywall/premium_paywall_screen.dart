import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/haptics.dart';
import '../../services/revenue_cat_service.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';
import '../profile/privacy_sheet.dart';
import '../profile/terms_sheet.dart';

class PremiumPaywallScreen extends StatefulWidget {
  final VoidCallback? onClose;

  const PremiumPaywallScreen({super.key, this.onClose});

  /// Opens the paywall as a fullscreen modal with Cupertino transition.
  static Future<bool?> show(BuildContext context) {
    Haptics.mediumImpact();
    return Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PremiumPaywallScreen(),
      ),
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
      final offerings = await RevenueCatService.getOfferings();
      final current = offerings?.current;
      final packages = current?.availablePackages ?? <Package>[];

      final eligibility = <String, bool>{};
      for (final pkg in packages) {
        eligibility[pkg.storeProduct.identifier] =
            await RevenueCatService.isEligibleForIntroOffer(pkg.storeProduct.identifier);
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
      if (kDebugMode) debugPrint('[PremiumPaywall] Error loading offerings: $e');
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
    if (_isProcessingPurchase || _isRestoring || _selectedPackage == null) return;

    setState(() => _isProcessingPurchase = true);
    Haptics.mediumImpact();

    try {
      final success = await RevenueCatService.purchasePackage(_selectedPackage!);
      if (!mounted) return;

      final isProNow = success || RevenueCatService.isPremiumNotifier.value;
      if (isProNow) {
        final chosenPlan = RevenueCatService.activePlanNotifier.value ??
            (_selectedPackage!.packageType == PackageType.annual ? 'Yearly Pro' : 'Monthly Pro');
        try {
          final profileVm = context.read<ProfileViewModel>();
          profileVm.setPremiumStatus(true, planName: chosenPlan);
        } catch (_) {}

        Haptics.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome to $chosenPlan! Unlimited authentications unlocked.'),
            backgroundColor: AppColors.deepForestGreen,
          ),
        );
        _dismiss(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(RevenueCatService.friendlyErrorMessage(e)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingPurchase = false);
    }
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
            backgroundColor: AppColors.deepForestGreen,
          ),
        );
        _dismiss(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active subscriptions found for this Apple ID.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(RevenueCatService.friendlyErrorMessage(e)),
            backgroundColor: Colors.redAccent,
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
      if (kDebugMode) debugPrint('[PremiumPaywall] Could not open manage subscription: $e');
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

  @override
  Widget build(BuildContext context) {
    final profileVm = context.watch<ProfileViewModel>();
    if (profileVm.isPremium) {
      // Never show the purchase flow to someone who already has an active
      // plan — that's how a tap on your own plan ends up offering to sell
      // it to you again. Show the current plan + a way to manage it instead.
      return _buildCurrentPlanView(profileVm);
    }

    final currentOffering = _offerings?.current;
    final availablePackages = currentOffering?.availablePackages ?? [];

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Dismiss (X) + Restore
            _buildTopBar(),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    // Character Mascot & Conversational Speech
                    _buildHeroHeader(),

                    const SizedBox(height: 12),
                    // Premium Feature Cards (Character Voiced)
                    _buildFeaturesList(),

                    const SizedBox(height: 14),
                    // Plan Selection Cards with 3-Day Free Trial
                    if (_isLoadingOfferings)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.deepForestGreen,
                          ),
                        ),
                      )
                    else if (availablePackages.isNotEmpty)
                      _buildDynamicPlanSelector(availablePackages)
                    else
                      _buildFallbackPlanSelector(),

                    const SizedBox(height: 14),
                    // Main CTA Button
                    _buildActionButton(),

                    const SizedBox(height: 12),
                    // Legal Disclaimer & Terms / Privacy Links
                    _buildLegalFooter(),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPlanView(ProfileViewModel profileVm) {
    final planName = profileVm.user.planName.isNotEmpty ? profileVm.user.planName : 'Lenz Pro';

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 20, color: AppColors.nearBlack),
                    ),
                    onPressed: () {
                      Haptics.lightImpact();
                      _dismiss(false);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.deepForestGreen.withOpacity(0.1),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: AppColors.deepForestGreen,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      planName,
                      style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Active • Unlimited scans unlocked',
                      style: AppTypography.bodyMedium.copyWith(color: AppColors.charcoalGray),
                    ),
                    const SizedBox(height: 28),
                    BounceButton(
                      onTap: _openManageSubscription,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: AppColors.deepForestGreen,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Center(
                          child: Text(
                            'Manage Subscription',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _isRestoring ? null : _handleRestore,
                      child: _isRestoring
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Restore Purchases',
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.nearBlack.withOpacity(0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    _buildLegalFooter(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 20, color: AppColors.nearBlack),
            ),
            onPressed: () {
              Haptics.lightImpact();
              _dismiss(false);
            },
          ),
          TextButton(
            onPressed: _isRestoring ? null : _handleRestore,
            child: _isRestoring
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack),
                  )
                : Text(
                    'Restore',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.nearBlack.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.nearBlack.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.nearBlack.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Detective Mascot
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.veryLightWarmGray,
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
              ),
              const DetectiveMascotWidget(
                size: 68,
                state: MascotState.curious,
                showHalo: true,
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Conversational speech by Detective Lenz
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Detective Lenz',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.deepForestGreen,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF14241B),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '"Don\'t let super-clones fool you! Hand me all your luxury items for unlimited authenticity checks so you always buy 100% genuine."',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.charcoalGray,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesList() {
    const features = [
      (
        CupertinoIcons.infinite,
        'Unlimited AI Authentications',
        'Bring me as many designer bags, sneakers, watches & apparel as you want.',
      ),
      (
        CupertinoIcons.shield_lefthalf_fill,
        'Instant Real vs. Fake Verdict',
        'I spot replica flaws, counterfeit stitching & fake hardware hallmarks in seconds.',
      ),
      (
        CupertinoIcons.square_stack_3d_up_fill,
        'Full Forensic Reports & Vault',
        'I\'ll save detailed flaw analysis, confidence scores & history to your collection.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.veryLightWarmGray.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Column(
        children: features.map((f) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.deepForestGreen.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(f.$1, size: 16, color: AppColors.deepForestGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.$2,
                        style: AppTypography.titleMedium.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.nearBlack,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      Text(
                        f.$3,
                        style: AppTypography.bodyMedium.copyWith(
                          fontSize: 11.5,
                          color: AppColors.charcoalGray,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDynamicPlanSelector(List<Package> packages) {
    return Column(
      children: packages.map((pkg) {
        final isSelected = _selectedPackage == pkg;
        final isAnnual = pkg.packageType == PackageType.annual;

        final title = isAnnual ? 'Yearly Membership' : 'Monthly Membership';
        final price = pkg.storeProduct.priceString;
        final period = isAnnual ? '/ year' : '/ month';
        final trialLabel = _trialLabelFor(pkg);
        final subtitle = trialLabel != null
            ? '$trialLabel Free Trial, then $price$period • Cancel anytime'
            : (isAnnual ? 'Best value • Cancel anytime' : 'Flexible • Cancel anytime');

        return _buildPlanCard(
          isSelected: isSelected,
          title: title,
          priceText: '$price $period',
          subtitle: subtitle,
          badgeText: trialLabel != null
              ? '$trialLabel FREE TRIAL'
              : (isAnnual ? 'BEST VALUE' : null),
          onTap: () {
            Haptics.lightImpact();
            setState(() => _selectedPackage = pkg);
          },
        );
      }).toList(),
    );
  }

  /// Shown only when offerings genuinely failed to load (e.g. no network) —
  /// never a guessed/hardcoded price, since that price could differ from
  /// what StoreKit actually charges (App Store Guideline 3.1.1).
  Widget _buildFallbackPlanSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.veryLightWarmGray.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 26,
            color: AppColors.charcoalGray.withOpacity(0.6),
          ),
          const SizedBox(height: 10),
          Text(
            "Couldn't load subscription plans",
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.nearBlack,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              fontSize: 12,
              color: AppColors.charcoalGray,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _loadOfferings,
            child: Text(
              'Retry',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.deepForestGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required bool isSelected,
    required String title,
    required String priceText,
    required String subtitle,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.pureWhite
                : AppColors.veryLightWarmGray.withOpacity(0.45),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isSelected
                  ? AppColors.deepForestGreen
                  : Colors.black.withOpacity(0.06),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.deepForestGreen.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              // Radio Indicator
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.deepForestGreen : Colors.grey.shade400,
                    width: 2,
                  ),
                  color: isSelected ? AppColors.deepForestGreen : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badgeText != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withOpacity(0.22),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          badgeText,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8A6D1F),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                    Text(
                      title,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.nearBlack,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodyMedium.copyWith(
                        fontSize: 11.5,
                        color: AppColors.charcoalGray,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Price
              Text(
                priceText,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: isSelected ? AppColors.deepForestGreen : AppColors.nearBlack,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final pkg = _selectedPackage;
    final isAnnual = pkg?.packageType == PackageType.annual;
    final trialLabel = pkg != null ? _trialLabelFor(pkg) : null;

    final buttonText = pkg == null
        ? 'Plans unavailable'
        : trialLabel != null
            ? 'Start $trialLabel Free Trial'
            : (isAnnual ? 'Continue with Yearly' : 'Continue with Monthly');
    final guaranteeText = pkg == null
        ? 'Reload the page and try again'
        : trialLabel != null
            ? '$trialLabel free • Then auto-renews • Cancel anytime in Settings'
            : 'Cancel anytime in App Store settings';

    return Column(
      children: [
        BounceButton(
          onTap: (_isProcessingPurchase || _isRestoring || pkg == null) ? null : _handlePurchase,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  AppColors.deepForestGreen,
                  Color(0xFF14241B),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: AppColors.deepForestGreen.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: _isProcessingPurchase
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      buttonText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          guaranteeText,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.charcoalGray.withOpacity(0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLegalFooter() {
    return Column(
      children: [
        Text(
          'Cancel anytime in App Store settings at least 24 hours before your renewal date. Subscriptions automatically renew.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.softGray.withOpacity(0.9),
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _openTermsSheet,
              child: Text(
                'Terms of Service',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.nearBlack.withOpacity(0.75),
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '•',
                style: TextStyle(color: AppColors.softGray.withOpacity(0.6)),
              ),
            ),
            GestureDetector(
              onTap: _openPrivacySheet,
              child: Text(
                'Privacy Policy',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.nearBlack.withOpacity(0.75),
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
