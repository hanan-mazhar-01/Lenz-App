import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/product.dart';
import '../../viewmodels/scan_flow_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/circular_mascot_loader.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';

/// Shows real request progress. The stages advance because the pipeline
/// advanced — there are no timed or decorative steps (§3).
class IdentifyingView extends StatelessWidget {
  final ScanLifecycleState scanState;
  final Product? product;
  final String? capturedImagePath;
  final int evidenceCount;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  const IdentifyingView({
    super.key,
    required this.scanState,
    required this.product,
    required this.onContinue,
    required this.onBack,
    this.capturedImagePath,
    this.evidenceCount = 0,
  });

  bool get _isIdentified => scanState == ScanLifecycleState.identified && product != null;

  @override
  Widget build(BuildContext context) {
    final stages = <_Stage>[
      _Stage(
        'Working out what this is',
        done: scanState != ScanLifecycleState.identifying,
        active: scanState == ScanLifecycleState.identifying,
      ),
      _Stage(
        'Working out which photos we need',
        done: _isIdentified,
        active: scanState == ScanLifecycleState.creatingEvidencePlan,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back),
          onPressed: onBack,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Text(
                _isIdentified ? 'Item identified' : 'Identifying your item',
                style: AppTypography.displayMedium.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _isIdentified
                    ? "Does this look right? Next we'll show you which photos to take."
                    : 'Looking at your photo...',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              if (_isIdentified)
                FadeSlideTransition(
                  child: GlassCard(
                    padding: const EdgeInsets.all(16),
                    borderRadius: 20,
                    child: Column(
                      children: [
                        if (capturedImagePath != null && capturedImagePath!.isNotEmpty)
                          AppImage(
                            imagePath: capturedImagePath!,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          product!.name,
                          style: AppTypography.titleLarge.copyWith(
                            color: AppColors.textPrimaryOf(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${product!.category.label} · ${product!.brand}'
                          '${product!.model.isNotEmpty ? ' · ${product!.model}' : ''}',
                          style: AppTypography.caption,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.neutralPillOf(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'We think this is a match: '
                            '${(product!.identificationConfidence * 100).round()}%',
                            style: AppTypography.captionMedium.copyWith(fontSize: 11),
                          ),
                        ),
                        if (product!.identificationConfidence < 0.5) ...[
                          const SizedBox(height: 10),
                          Text(
                            "We're not very sure what this is. You can carry on, "
                            "but we won't be able to say as much.",
                            style: AppTypography.caption.copyWith(color: AppColors.warning),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                const CircularMascotLoader(
                  size: 165,
                  child: DetectiveMascotWidget(
                    size: 110,
                    state: MascotState.inspecting,
                    showHalo: false,
                  ),
                ),

              const Spacer(),

              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Column(
                  children: stages
                      .map((s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                if (s.done)
                                  const Icon(CupertinoIcons.checkmark_circle_fill,
                                      size: 20, color: AppColors.success)
                                else if (s.active)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: AppColors.accent,
                                    ),
                                  )
                                else
                                  Icon(CupertinoIcons.circle,
                                      size: 20, color: AppColors.textTertiaryOf(context)),
                                const SizedBox(width: 14),
                                Text(
                                  s.label,
                                  style: AppTypography.bodyLarge.copyWith(
                                    color: s.done
                                        ? AppColors.textPrimaryOf(context)
                                        : s.active
                                            ? AppColors.accent
                                            : AppColors.textTertiaryOf(context),
                                    fontWeight:
                                        s.done || s.active ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),

              const SizedBox(height: 16),

              if (_isIdentified)
                BounceButton(
                  onTap: onContinue,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.buttonDark,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Text(
                      evidenceCount > 0
                          ? 'See the $evidenceCount photos we need →'
                          : 'Continue →',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stage {
  final String label;
  final bool done;
  final bool active;
  const _Stage(this.label, {required this.done, required this.active});
}
