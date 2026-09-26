import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/revenue_cat_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations/bounce_button.dart';

class TermsOfServiceSheet extends StatelessWidget {
  const TermsOfServiceSheet({super.key});

  Future<void> _openAppleEula() async {
    final uri = Uri.parse(RevenueCatConfig.termsOfServiceUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
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
            Text('Terms of Service', style: AppTypography.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Lenz Subscription & Usage Agreement',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 20),

            _buildSection(
              icon: CupertinoIcons.creditcard,
              title: 'Subscription & Auto-Renewal',
              description:
                  'Subscriptions automatically renew unless auto-renew is turned off at least 24 hours before the end of the current billing period. Payment will be charged to your Apple ID account at confirmation of purchase.',
            ),
            const SizedBox(height: 10),

            _buildSection(
              icon: CupertinoIcons.timer,
              title: '3-Day Free Trial',
              description:
                  'Any unused portion of a free trial period, if offered, will be forfeited when purchasing a subscription. You can cancel your free trial anytime in your Apple ID account settings without being charged.',
            ),
            const SizedBox(height: 10),

            _buildSection(
              icon: CupertinoIcons.arrow_counterclockwise,
              title: 'Cancellation & Refunds',
              description:
                  'You can manage or cancel your subscription anytime in your iPhone Settings > Apple ID > Subscriptions. All refunds are handled directly by Apple according to App Store policy.',
            ),
            const SizedBox(height: 10),

            _buildSection(
              icon: CupertinoIcons.shield_lefthalf_fill,
              title: 'Authentication Disclaimer',
              description:
                  'Lenz uses advanced AI computer-vision models to assess product authenticity. While our algorithms provide high-confidence insights, results are intended for advisory purposes and do not replace certified manufacturer appraisals.',
            ),
            const SizedBox(height: 20),

            // Button to open Apple Standard EULA
            GestureDetector(
              onTap: _openAppleEula,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.deepForestGreen.withOpacity(0.3)),
                  color: AppColors.deepForestGreen.withOpacity(0.05),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'View Apple Standard EULA',
                      style: TextStyle(
                        color: AppColors.deepForestGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      CupertinoIcons.arrow_up_right,
                      size: 14,
                      color: AppColors.deepForestGreen,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Done button
            BounceButton(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.deepForestGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.deepForestGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.deepForestGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
