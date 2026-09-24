import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';

/// Premium is not purchasable yet - there is no real payment integration
/// wired up. This screen previously showed real prices next to a button
/// that just flipped a local flag with zero transaction, which is a
/// guaranteed App Store rejection (Guideline 3.1.1). Until a real purchase
/// flow (RevenueCat/StoreKit) is built, this is an honest "coming soon"
/// screen with no purchase action - see the audit notes in this repo for
/// what's required before re-introducing pricing here.
class PremiumScreen extends StatelessWidget {
  final VoidCallback onClose;

  const PremiumScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: onClose,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FadeSlideTransition(
                delay: const Duration(milliseconds: 40),
                child: Column(
                  children: [
                    const DetectiveMascotWidget(size: 100, state: MascotState.thinking),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'COMING SOON',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Premium isn\'t available yet.', style: AppTypography.displayMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    const Text(
                      'We\'re building unlimited authentications and more. '
                      'You\'ll be able to subscribe right here once it launches.',
                      style: AppTypography.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Planned benefits - no pricing attached since nothing is
              // purchasable yet.
              FadeSlideTransition(
                delay: const Duration(milliseconds: 90),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      _buildBenefit('Unlimited authenticity checks'),
                      const Divider(),
                      _buildBenefit('Advanced multi-photo evidence analysis'),
                      const Divider(),
                      _buildBenefit('Macro-level physical inspection guides'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              FadeSlideTransition(
                delay: const Duration(milliseconds: 140),
                child: BounceButton(
                  onTap: onClose,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefit(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(CupertinoIcons.checkmark_seal_fill, size: 18, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}
