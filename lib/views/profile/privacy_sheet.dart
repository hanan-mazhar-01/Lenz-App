import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations/bounce_button.dart';

class PrivacySecuritySheet extends StatelessWidget {
  const PrivacySecuritySheet({super.key});

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
            Text('Privacy & Security', style: AppTypography.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'How your scan data and photos are guarded.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 20),

            // What We Collect section
            Text(
              'WHAT WE COLLECT',
              style: AppTypography.captionMedium.copyWith(letterSpacing: 0.6),
            ),
            const SizedBox(height: 10),
            _buildInfoCard(
              icon: CupertinoIcons.photo,
              title: 'Product Photos & AI Analysis',
              description:
                  'Photos you submit are securely analyzed using Google Gemini AI models '
                  'to evaluate stitching, materials, hardware, and typography. '
                  'Photos are securely hosted so your reports remain accessible in your collection.',
            ),
            const SizedBox(height: 10),
            _buildInfoCard(
              icon: CupertinoIcons.shield_lefthalf_fill,
              title: 'Account & Scan Reports',
              description:
                  'Your authentication data, verification reports, and saved collection '
                  'are protected with Firebase Cloud Security. We never sell your personal '
                  'information to any third parties.',
            ),
            const SizedBox(height: 10),
            _buildInfoCard(
              icon: CupertinoIcons.lock,
              title: 'Data In Transit & Storage',
              description:
                  'All network communication between your device and our servers is '
                  'strictly encrypted via industry-standard TLS. Signing out clears '
                  'local device caches while preserving your cloud account data.',
            ),

            const SizedBox(height: 24),

            // Close button
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

  Widget _buildInfoCard({
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
              color: AppColors.accent.withValues(alpha: 0.08),
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
