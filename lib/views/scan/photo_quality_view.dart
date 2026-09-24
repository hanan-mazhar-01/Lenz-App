import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/evidence.dart';
import '../../models/evidence_validation.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/common/app_image.dart';

/// Review screen shown after every submitted photo.
///
/// Presents photo quality and authentication usefulness as separate numbers,
/// and refuses a photo that does not show the requested area (§10-14).
class PhotoQualityView extends StatelessWidget {
  final EvidenceItem item;
  final String? photoPath;
  final EvidenceValidationResult validation;

  /// Accept the photo as evidence for this item.
  final VoidCallback onKeep;

  /// Keep a photo the app flagged as low quality. Null when not permitted.
  final VoidCallback? onKeepAnyway;

  final VoidCallback onRetake;
  final VoidCallback onChooseAnother;

  const PhotoQualityView({
    super.key,
    required this.item,
    required this.validation,
    required this.onKeep,
    required this.onRetake,
    required this.onChooseAnother,
    this.photoPath,
    this.onKeepAnyway,
  });

  Color _scoreColor(int score) {
    if (score >= 85) return AppColors.success;
    if (score >= 70) return AppColors.accent;
    if (score >= 45) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final verdict = validation.verdict;
    final quality = validation.quality;
    final isWrongEvidence = verdict == EvidenceVerdict.rejectedWrongEvidence;
    final isRejected = verdict != EvidenceVerdict.accepted;

    // One consistent plain-English line, plus short fix-it hints (§22, §23).
    final note = validation.usefulnessExplanation;
    final tips = {
      if (quality.firstFix != null) quality.firstFix!,
      ...validation.issues.where((i) => i.length < 60),
    }.toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back),
          onPressed: onRetake,
        ),
        title: Text(item.title),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            // ---------------------------------------------------- headline
            FadeSlideTransition(
              delay: const Duration(milliseconds: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    validation.headline,
                    style: AppTypography.titleLarge.copyWith(
                      color: isRejected ? AppColors.danger : AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    validation.guidance,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  if (isRejected) ...[
                    const SizedBox(height: 6),
                    Text(
                      validation.callToAction,
                      style: AppTypography.captionMedium.copyWith(color: AppColors.danger),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ------------------------------------------------ the photo
            FadeSlideTransition(
              delay: const Duration(milliseconds: 70),
              child: GlassCard(
                padding: const EdgeInsets.all(10),
                child: Stack(
                  children: [
                    AppImage(
                      imagePath: photoPath ?? '',
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    if (isWrongEvidence)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Looks like: ${validation.evidenceTypeDetected}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ------------------------- the three independent measurements
            FadeSlideTransition(
              delay: const Duration(milliseconds: 100),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  children: [
                    _metricRow(
                      context,
                      label: 'Photo Quality',
                      value: quality.qualityScore,
                      caption: quality.simpleSummary,
                    ),
                    const Divider(height: 20),
                    _metricRow(
                      context,
                      label: 'Right Part',
                      value: validation.matchConfidence,
                      caption: validation.matchToRequestedEvidence
                          ? 'Shows the ${item.title.toLowerCase()}'
                          : "Doesn't show the ${item.title.toLowerCase()}",
                    ),
                    const Divider(height: 20),
                    _metricRow(
                      context,
                      label: 'Check Usefulness',
                      value: validation.authenticationUsefulness,
                      caption: validation.usefulnessLabel,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // -------------------------------------- quality sub-breakdown
            if (quality.sharpness + quality.lighting + quality.framing + quality.detail > 0)
              FadeSlideTransition(
                delay: const Duration(milliseconds: 130),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PHOTO DETAILS',
                        style: AppTypography.captionMedium.copyWith(
                          letterSpacing: 0.8,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _bar(context, 'Sharpness', quality.sharpness),
                      _bar(context, 'Lighting', quality.lighting),
                      _bar(context, 'Framing', quality.framing),
                      _bar(context, 'Close-up', quality.detail),
                    ],
                  ),
                ),
              ),

            if (note.isNotEmpty) ...[
              const SizedBox(height: 12),
              FadeSlideTransition(
                delay: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isRejected ? AppColors.dangerBg : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isRejected
                            ? CupertinoIcons.exclamationmark_triangle_fill
                            : CupertinoIcons.checkmark_seal_fill,
                        size: 16,
                        color: isRejected ? AppColors.danger : AppColors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          note,
                          style: AppTypography.captionMedium.copyWith(
                            color: isRejected ? AppColors.danger : AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (tips.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...tips.map(
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5, right: 8),
                        child: Icon(CupertinoIcons.circle_fill, size: 5, color: AppColors.textTertiary),
                      ),
                      Expanded(child: Text(i, style: AppTypography.caption)),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 22),

            // ---------------------------------------------------- actions
            FadeSlideTransition(
              delay: const Duration(milliseconds: 180),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _secondaryButton(context, 'Retake', onRetake),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _secondaryButton(context, 'Choose Another Photo', onChooseAnother),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!isRejected)
                    _primaryButton('Use this photo', onKeep)
                  else if (validation.isOverridable && onKeepAnyway != null)
                    _outlineButton(context, 'Use it anyway', onKeepAnyway!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(
    BuildContext context, {
    required String label,
    required int value,
    required String caption,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.titleMedium.copyWith(
                  fontSize: 14,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(caption, style: AppTypography.caption.copyWith(fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$value%',
          style: AppTypography.titleLarge.copyWith(
            fontSize: 22,
            color: _scoreColor(value),
          ),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(label, style: AppTypography.caption.copyWith(fontSize: 11.5)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (value / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.neutralPill,
                valueColor: AlwaysStoppedAnimation(_scoreColor(value)),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: AppTypography.captionMedium.copyWith(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton(String text, VoidCallback onTap) {
    return BounceButton(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.buttonDark,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }

  Widget _secondaryButton(BuildContext context, String text, VoidCallback onTap) {
    return BounceButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.neutralPillOf(context),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimaryOf(context),
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _outlineButton(BuildContext context, String text, VoidCallback onTap) {
    return BounceButton(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.warning, width: 1.4),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.warning,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
