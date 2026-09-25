import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/haptics.dart';
import '../../services/revenue_cat_service.dart';
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
  int _fallbackSelectedIndex = 1; // 0 = monthly, 1 = annual

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() => _isLoadingOfferings = true);
    try {
      final offerings = await RevenueCatService.getOfferings();
      if (mounted) {
        setState(() {
          _offerings = offerings;
          final current = offerings?.current;
          if (current != null) {
            _selectedPackage = current.annual ?? current.monthly ?? current.availablePackages.firstOrNull;
          }
          _isLoadingOfferings = false;
        });
      }
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
    if (_isProcessingPurchase || _isRestoring) return;

    if (_selectedPackage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offerings are loading or unavailable. Please try again in a moment.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isProcessingPurchase = true);
    Haptics.mediumImpact();

    try {
      final success = await RevenueCatService.purchasePackage(_selectedPackage!);
      if (!mounted) return;

      if (success) {
        Haptics.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Welcome to Lenz Premium! All scans unlocked.'),
            backgroundColor: AppColors.deepForestGreen,
          ),
        );
        _dismiss(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase could not be completed: $e'),
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

      if (restored) {
        Haptics.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchases restored successfully! Premium unlocked.'),
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
            content: Text('Restore error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
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
        final subtitle = isAnnual
            ? '3-Day Free Trial, then $price/yr • Cancel anytime'
            : 'Flexible • Cancel anytime';

        return _buildPlanCard(
          isSelected: isSelected,
          title: title,
          priceText: '$price $period',
          subtitle: subtitle,
          badgeText: isAnnual ? '3-DAY FREE TRIAL • BEST VALUE' : null,
          onTap: () {
            Haptics.lightImpact();
            setState(() => _selectedPackage = pkg);
          },
        );
      }).toList(),
    );
  }

  Widget _buildFallbackPlanSelector() {
    return Column(
      children: [
        _buildPlanCard(
          isSelected: _fallbackSelectedIndex == 1,
          title: 'Yearly Membership',
          priceText: r'$49.99 / year',
          subtitle: r'3-Day Free Trial, then $49.99/yr (~$4.16/mo)',
          badgeText: '3-DAY FREE TRIAL • BEST VALUE',
          onTap: () {
            Haptics.lightImpact();
            setState(() => _fallbackSelectedIndex = 1);
          },
        ),
        _buildPlanCard(
          isSelected: _fallbackSelectedIndex == 0,
          title: 'Monthly Membership',
          priceText: r'$9.99 / month',
          subtitle: 'Flexible • Cancel anytime',
          badgeText: null,
          onTap: () {
            Haptics.lightImpact();
            setState(() => _fallbackSelectedIndex = 0);
          },
        ),
      ],
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
    final isAnnual = _selectedPackage?.packageType == PackageType.annual ||
        (_selectedPackage == null && _fallbackSelectedIndex == 1);

    final buttonText = isAnnual ? 'Start 3-Day Free Trial' : 'Continue with Monthly';
    final guaranteeText = isAnnual
        ? '3 days free • Then auto-renews • Cancel anytime in Settings'
        : 'Flexible plan • Cancel anytime in App Store';

    return Column(
      children: [
        BounceButton(
          onTap: (_isProcessingPurchase || _isRestoring) ? null : _handlePurchase,
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
