import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';
import '../../services/haptics.dart';

class ScanErrorView extends StatelessWidget {
  final String errorMessage;
  final AppError? appError;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const ScanErrorView({
    super.key,
    required this.errorMessage,
    this.appError,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveError = appError ?? AppError.fromException(errorMessage);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    IconData errorIcon;
    Color iconColor;
    MascotState mascotState;

    switch (effectiveError.type) {
      case AppErrorType.noInternet:
        errorIcon = CupertinoIcons.wifi_exclamationmark;
        iconColor = AppColors.warning;
        mascotState = MascotState.curious;
        break;
      case AppErrorType.serviceUnreachable:
        errorIcon = CupertinoIcons.antenna_radiowaves_left_right;
        iconColor = AppColors.warning;
        mascotState = MascotState.thinking;
        break;
      case AppErrorType.timeout:
        errorIcon = CupertinoIcons.hourglass;
        iconColor = AppColors.warning;
        mascotState = MascotState.thinking;
        break;
      case AppErrorType.quotaLimit:
        errorIcon = CupertinoIcons.clock_fill;
        iconColor = AppColors.accent;
        mascotState = MascotState.inconclusive;
        break;
      case AppErrorType.apiUnauthorized:
        errorIcon = CupertinoIcons.lock_shield_fill;
        iconColor = AppColors.danger;
        mascotState = MascotState.suspicious;
        break;
      case AppErrorType.serverError:
        errorIcon = CupertinoIcons.cloud_bolt_rain_fill;
        iconColor = AppColors.danger;
        mascotState = MascotState.thinking;
        break;
      case AppErrorType.invalidResponse:
        errorIcon = CupertinoIcons.question_circle_fill;
        iconColor = AppColors.warning;
        mascotState = MascotState.inconclusive;
        break;
      case AppErrorType.cameraError:
        errorIcon = CupertinoIcons.camera;
        iconColor = AppColors.danger;
        mascotState = MascotState.curious;
        break;
      case AppErrorType.unknownError:
        errorIcon = CupertinoIcons.exclamationmark_triangle_fill;
        iconColor = AppColors.warning;
        mascotState = MascotState.suspicious;
        break;
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Detective mascot state illustration
              FadeSlideTransition(
                delay: const Duration(milliseconds: 60),
                child: DetectiveMascotWidget(
                  size: 130,
                  state: mascotState,
                  showHalo: true,
                ),
              ),
              const SizedBox(height: 16),

              // Title with icon badge
              FadeSlideTransition(
                delay: const Duration(milliseconds: 100),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(errorIcon, size: 22, color: iconColor),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        effectiveError.title,
                        style: AppTypography.displayLarge.copyWith(
                          fontSize: 22,
                          color: AppColors.textPrimaryOf(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Detail message card
              FadeSlideTransition(
                delay: const Duration(milliseconds: 140),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  backgroundColor: AppColors.cardSurfaceOf(context),
                  border: Border.all(color: AppColors.borderOf(context)),
                  child: Column(
                    children: [
                      Text(
                        effectiveError.message,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondaryOf(context),
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (effectiveError.recoveryAction != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(CupertinoIcons.lightbulb, size: 14, color: AppColors.accent),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  effectiveError.recoveryAction!,
                                  style: AppTypography.captionMedium.copyWith(
                                    color: AppColors.textPrimaryOf(context),
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Action buttons
              FadeSlideTransition(
                delay: const Duration(milliseconds: 180),
                child: Column(
                  children: [
                    BounceButton(
                      onTap: () {
                        Haptics.mediumImpact();
                        onRetry();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withOpacity(0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Try Again',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    BounceButton(
                      onTap: () {
                        Haptics.lightImpact();
                        onCancel();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        child: Text(
                          'Cancel & Return Home',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondaryOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
