import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/product_identification.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/common/app_image.dart';

class ScanValidationResultView extends StatelessWidget {
  final String? capturedImagePath;
  final IdentificationStatus status;
  final String reason;
  final String message;
  final List<String> missingEvidence;
  final VoidCallback onTryAgain;
  final VoidCallback onClose;

  const ScanValidationResultView({
    super.key,
    this.capturedImagePath,
    required this.status,
    required this.reason,
    required this.message,
    this.missingEvidence = const [],
    required this.onTryAgain,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // Title, badge, and icon based on validation outcome
    String title;
    String badgeLabel;
    IconData badgeIcon;
    Color badgeColor;
    String buttonText;

    if (reason == 'image_too_dark') {
      title = 'Too dark to analyze';
      badgeLabel = 'Too Dark';
      badgeIcon = CupertinoIcons.moon_fill;
      badgeColor = const Color(0xFFD97706);
      buttonText = 'Try Again';
    } else if (reason == 'no_visible_content') {
      title = 'No visible item detected';
      badgeLabel = 'No Object';
      badgeIcon = CupertinoIcons.eye_slash_fill;
      badgeColor = const Color(0xFFD97706);
      buttonText = 'Scan Again';
    } else if (reason == 'insufficient_visual_quality') {
      title = "Image isn't clear enough";
      badgeLabel = 'Blurry / Unclear';
      badgeIcon = CupertinoIcons.sparkles;
      badgeColor = const Color(0xFFD97706);
      buttonText = 'Retake Photo';
    } else if (reason == 'human_detected') {
      title = 'No supported luxury item detected';
      badgeLabel = 'Person Detected';
      badgeIcon = CupertinoIcons.person_crop_circle_badge_exclam;
      badgeColor = AppColors.charcoalGray;
      buttonText = 'Scan a Luxury Item';
    } else if (status == IdentificationStatus.insufficientEvidence || reason == 'partial_product_insufficient_evidence') {
      title = 'More details needed';
      badgeLabel = 'Incomplete View';
      badgeIcon = CupertinoIcons.info_circle_fill;
      badgeColor = const Color(0xFFD97706);
      buttonText = 'Retake Clearer Photo';
    } else {
      title = 'No supported luxury item detected';
      badgeLabel = 'Non-Luxury Object';
      badgeIcon = CupertinoIcons.question_circle_fill;
      badgeColor = AppColors.charcoalGray;
      buttonText = 'Scan a Supported Item';
    }

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.nearBlack),
          onPressed: onClose,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Captured Photo with Badge Overlay
              if (capturedImagePath != null && capturedImagePath!.isNotEmpty)
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 40),
                  child: Center(
                    child: Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: AppColors.nearBlack.withOpacity(0.08),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.nearBlack.withOpacity(0.06),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(21),
                            child: AppImage(
                              imagePath: capturedImagePath!,
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // Floating status pill badge
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: badgeColor.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(badgeIcon, size: 13, color: Colors.white),
                                const SizedBox(width: 5),
                                Text(
                                  badgeLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 22),

              // 2. Headline Title
              FadeSlideTransition(
                delay: const Duration(milliseconds: 70),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.nearBlack,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // 3. User-friendly Explanation Message
              FadeSlideTransition(
                delay: const Duration(milliseconds: 100),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.charcoalGray,
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 4. Missing Evidence list (if applicable)
              if (missingEvidence.isNotEmpty) ...[
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 120),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.veryLightWarmGray,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.nearBlack.withOpacity(0.06),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Needed for reliable identification:',
                          style: TextStyle(
                            color: AppColors.nearBlack,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...missingEvidence.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Icon(
                                      Icons.circle,
                                      size: 5,
                                      color: AppColors.deepForestGreen,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: const TextStyle(
                                        color: AppColors.charcoalGray,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 5. Best Practices Tips Card
              FadeSlideTransition(
                delay: const Duration(milliseconds: 140),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.softWarmGray,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.nearBlack.withOpacity(0.05),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            CupertinoIcons.lightbulb_fill,
                            size: 16,
                            color: AppColors.deepForestGreen,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'Scanning Tips',
                            style: TextStyle(
                              color: AppColors.nearBlack,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• Center the luxury item on a plain, well-lit surface.\n'
                        '• Avoid shadows, heavy glare, and camera blur.\n'
                        '• Supported categories: Handbags, Watches, Sneakers & Shoes, Clothing, Wallets, Jewelry and Accessories.',
                        style: TextStyle(
                          color: AppColors.charcoalGray,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // 6. Action Buttons
              FadeSlideTransition(
                delay: const Duration(milliseconds: 170),
                child: Column(
                  children: [
                    BounceButton(
                      onTap: onTryAgain,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.deepForestGreen,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.deepForestGreen.withOpacity(0.22),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            buttonText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: onClose,
                      child: const Text(
                        'Back to Home',
                        style: TextStyle(
                          color: AppColors.charcoalGray,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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

