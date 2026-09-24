import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/evidence.dart';
import '../../widgets/animations/circular_mascot_loader.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';

/// Shown while a submitted photo is being checked against the requested angle.
class ValidatingPhotoView extends StatelessWidget {
  final EvidenceItem? item;

  const ValidatingPhotoView({super.key, this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Checking your photo',
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  item != null
                      ? 'Confirming this shows the ${item!.title.toLowerCase()} clearly enough to inspect.'
                      : 'Confirming this shows the requested detail.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondaryOf(context),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 38),
                const CircularMascotLoader(
                  size: 165,
                  child: DetectiveMascotWidget(
                    size: 110,
                    state: MascotState.inspecting,
                    showHalo: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
