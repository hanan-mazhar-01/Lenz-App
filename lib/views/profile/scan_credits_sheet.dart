import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/cards/glass_card.dart';

class ScanCreditsSheet extends StatelessWidget {
  final VoidCallback onOpenPremium;

  const ScanCreditsSheet({super.key, required this.onOpenPremium});

  @override
  Widget build(BuildContext context) {
    final profileVm = context.watch<ProfileViewModel>();
    final user = profileVm.user;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: AppColors.neutralPill,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scan Credits & Quota', style: AppTypography.titleLarge),
                  const SizedBox(height: 2),
                  Text(user.planName, style: AppTypography.caption),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: user.isPremium ? AppColors.accentSoft : AppColors.neutralPill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  user.isPremium ? 'UNLIMITED' : '${user.scansRemaining} LEFT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: user.isPremium ? AppColors.accent : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Quota Visual
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Monthly Allowance', style: AppTypography.titleMedium),
                    Text(
                      user.isPremium ? '∞ / ∞' : '${user.scansRemaining} / 10 used',
                      style: AppTypography.captionMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: user.isPremium ? 1.0 : (user.scansRemaining / 10).clamp(0.0, 1.0),
                    backgroundColor: AppColors.neutralPill,
                    color: AppColors.accent,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.isPremium
                      ? 'You have unlimited authentications active.'
                      : 'Free scans don\'t reset automatically - each one is used once.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // No purchasable refills/upgrade yet - there's no real payment
          // integration wired up. This used to show "+5 Scans $4.99" /
          // "Switch to Premium $19.99/mo" buttons that displayed a fake
          // success toast or a locally-flipped flag with zero real
          // transaction (a guaranteed App Store rejection).
          if (!user.isPremium)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'More scans and Premium plans are coming soon.',
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

