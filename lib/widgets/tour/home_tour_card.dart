import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../core/theme/app_colors.dart';
import '../../services/haptics.dart';
import '../animations/bounce_button.dart';

/// The tooltip content shown by each step of the Home-screen coach-mark
/// tour. Matches the app's existing card language (rounded corners, warm
/// palette, `BounceButton` press feedback) instead of the package's default
/// Material tooltip styling.
class HomeTourCard extends StatelessWidget {
  final String title;
  final String description;
  final int stepIndex; // 0-based
  final int totalSteps;

  const HomeTourCard({
    super.key,
    required this.title,
    required this.description,
    required this.stepIndex,
    required this.totalSteps,
  });

  bool get _isLastStep => stepIndex == totalSteps - 1;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.nearBlack.withOpacity(0.06),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.nearBlack.withOpacity(0.16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.veryLightWarmGray,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${stepIndex + 1}/$totalSteps',
                  style: const TextStyle(
                    color: AppColors.charcoalGray,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Semantics(
                button: true,
                label: 'Skip tour',
                child: GestureDetector(
                  onTap: () {
                    Haptics.lightImpact();
                    ShowcaseView.get().dismiss();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: AppColors.softGray,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.nearBlack,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.charcoalGray,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: _isLastStep ? 'Done' : 'Next',
            child: BounceButton(
              onTap: () => ShowcaseView.get().next(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.deepForestGreen,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.deepForestGreen.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _isLastStep ? 'Done' : 'Next',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
