import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/authentication_rules.dart';
import '../../models/authentication_result.dart';
import '../../widgets/cards/glass_card.dart';

/// Physical checks the user can perform in person.
///
/// Content is product-specific: the model's own suggestions for this item
/// first, then the category rule set for this exact category. No generic
/// "check the stitching" filler (§36).
class PhysicalDetectionTipsView extends StatelessWidget {
  final AuthenticationReport report;
  final VoidCallback onBack;

  const PhysicalDetectionTipsView({
    super.key,
    required this.report,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final rules = AuthenticationRules.resolve(
      category: report.product.category,
      brand: report.product.brand,
      model: report.product.model,
    );

    // Where the evidence was inconclusive or suspicious, physical inspection
    // is most valuable — surface those areas first.
    final priorityAreas = report.evidenceItems
        .where((e) => e.inconsistentSignals.isNotEmpty || e.uncertainSignals.isNotEmpty)
        .map((e) => e.title)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back, color: AppColors.nearBlack, size: 24),
          onPressed: onBack,
        ),
        centerTitle: true,
        title: const Text(
          'Detect It Yourself',
          style: TextStyle(
            color: AppColors.nearBlack,
            fontSize: 18.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              'Checks for your ${report.product.name}',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Simple things you can check by hand, based on what your photos showed.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 16),

            if (priorityAreas.isNotEmpty) ...[
              GlassCard(
                padding: const EdgeInsets.all(14),
                borderRadius: 16,
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4), width: 1.3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                            size: 13, color: AppColors.warning),
                        const SizedBox(width: 7),
                        Text(
                          'START HERE',
                          style: AppTypography.captionMedium.copyWith(
                            letterSpacing: 0.8,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      priorityAreas.join(' · '),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (report.nextChecks.isNotEmpty) ...[
              _header(context, 'WHAT TO DO NEXT'),
              const SizedBox(height: 8),
              ...report.nextChecks.map((c) => _simpleTip(context, c)),
              const SizedBox(height: 16),
            ],

            if (report.physicalChecks.isNotEmpty) ...[
              _header(context, 'CHECKS FOR THIS ITEM'),
              const SizedBox(height: 8),
              ...report.physicalChecks.map(
                (c) => _tipCard(
                  context,
                  title: c.title,
                  description: c.description,
                  lookFor: c.whatToLookFor,
                ),
              ),
              const SizedBox(height: 16),
            ],

            _header(context, 'WHAT TO LOOK AT'),
            const SizedBox(height: 8),
            ...rules.inspectionRules.map(
              (r) => _tipCard(
                context,
                title: r.dimension.simpleLabel,
                description: r.simpleTip,
                lookFor: '',
              ),
            ),

            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.neutralPillOf(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'These point you at what to look at. On their own they prove nothing either '
                'way — a real item can be worn, and a good fake can pass any single check.',
                style: AppTypography.caption.copyWith(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: AppColors.textSecondaryOf(context),
        ),
      );

  Widget _simpleTip(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 9),
              child: Icon(CupertinoIcons.circle_fill, size: 5, color: AppColors.accent),
            ),
            Expanded(
              child: Text(
                text,
                style: AppTypography.bodyMedium.copyWith(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _tipCard(
    BuildContext context, {
    required String title,
    required String description,
    required String lookFor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.titleMedium.copyWith(
                fontSize: 14,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                description,
                style: AppTypography.bodyMedium.copyWith(fontSize: 12.5, height: 1.4),
              ),
            ],
            if (lookFor.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentSoftOf(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  lookFor,
                  style: AppTypography.caption.copyWith(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.accentOf(context),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
