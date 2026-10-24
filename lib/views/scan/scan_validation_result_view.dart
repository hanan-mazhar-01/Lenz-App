import 'package:flutter/material.dart';

import '../../models/product_identification.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// "Not a product / can't identify" screen (prototype `SCREENS.notproduct`).
/// Every real validation outcome keeps its own title, badge and button copy;
/// the user's photo (when there is one) is shown with the outcome badge.
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
    // Title, badge, and icon based on validation outcome (unchanged mapping).
    String title;
    String badgeLabel;
    String badgeIcon;
    String buttonText;
    LenzMood mood = LenzMood.unsure;

    if (reason == 'not_real_photo') {
      title = 'This is a picture, not the item';
      badgeLabel = 'Not a Real Photo';
      badgeIcon = LenzIcons.image;
      buttonText = 'Take a Photo';
    } else if (reason == 'image_too_dark') {
      title = 'Too dark to analyze';
      badgeLabel = 'Too Dark';
      badgeIcon = LenzIcons.eyeOff;
      buttonText = 'Try Again';
      mood = LenzMood.sorry;
    } else if (reason == 'no_visible_content') {
      title = 'No visible item detected';
      badgeLabel = 'No Object';
      badgeIcon = LenzIcons.eyeOff;
      buttonText = 'Scan Again';
    } else if (reason == 'insufficient_visual_quality') {
      title = "Image isn't clear enough";
      badgeLabel = 'Blurry / Unclear';
      badgeIcon = LenzIcons.sparkles;
      buttonText = 'Retake Photo';
      mood = LenzMood.sorry;
    } else if (reason == 'human_detected') {
      title = 'No supported luxury item detected';
      badgeLabel = 'Person Detected';
      badgeIcon = LenzIcons.user;
      buttonText = 'Scan a Luxury Item';
      mood = LenzMood.shy;
    } else if (status == IdentificationStatus.insufficientEvidence ||
        reason == 'partial_product_insufficient_evidence') {
      title = 'More details needed';
      badgeLabel = 'Incomplete View';
      badgeIcon = LenzIcons.info;
      buttonText = 'Retake Clearer Photo';
      mood = LenzMood.think;
    } else {
      title = 'No supported luxury item detected';
      badgeLabel = 'Non-Luxury Object';
      badgeIcon = LenzIcons.help;
      buttonText = 'Scan a Supported Item';
    }

    final hasPhoto = capturedImagePath != null && capturedImagePath!.isNotEmpty;
    final pad = MediaQuery.paddingOf(context);
    const tips = [
      'Center the luxury item on a plain, well-lit surface.',
      'Avoid shadows, heavy glare, and camera blur.',
      'Supported categories: Handbags, Watches, Sneakers & Shoes, Clothing, Wallets, Jewelry and Accessories.',
    ];

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LenzBlob(color: LenzColors.warnSoft),
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, pad.top + 14, 20, 30 + pad.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                LenzTopBar(
                  title: 'Hmm',
                  leading: LenzIconButton(
                    icon: LenzIcons.x,
                    semanticLabel: 'Close',
                    onTap: onClose,
                  ),
                ),
                const SizedBox(height: 6),
                LenzStagger(
                  spacing: 10,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (hasPhoto)
                      SizedBox(
                        height: 230,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: SizedBox(width: 200, child: LenzCharacter(mood: mood)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _PhotoBadge(path: capturedImagePath!),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SizedBox(width: 250, child: LenzCharacter(mood: mood)),
                      ),
                    LenzPill(label: badgeLabel, icon: badgeIcon, variant: LenzPillVariant.unsure),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: LenzText.display.copyWith(fontSize: 28),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(message, textAlign: TextAlign.center, style: LenzText.sub),
                    ),
                    if (missingEvidence.isNotEmpty)
                      _BulletCard(
                        title: 'Needed for reliable identification',
                        lines: missingEvidence,
                        icon: LenzIcons.camera,
                      ),
                    const _BulletCard(title: 'Scanning tips', lines: tips, icon: LenzIcons.tip),
                    LenzButton(label: buttonText, icon: LenzIcons.camera, onPressed: onTryAgain),
                    LenzButton(
                      label: 'Back to home',
                      variant: LenzButtonVariant.ghost,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The user's photo as a tilted polaroid.
class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: .06,
      child: Container(
        width: 96,
        height: 96,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: LenzColors.paper,
          borderRadius: BorderRadius.circular(22),
          boxShadow: LenzShadows.sh2,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: AppImage(imagePath: path, width: 86, height: 86, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  const _BulletCard({required this.title, required this.lines, required this.icon});

  final String title;
  final List<String> lines;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return LenzCard(
      radius: 26,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: LenzText.item.copyWith(fontSize: 15.5)),
          const SizedBox(height: 2),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: const BoxDecoration(
                      color: LenzColors.warnSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: LenzIcon(icon, size: 13, strokeWidth: 2.6, color: LenzColors.warn),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l, style: LenzText.bullet)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
