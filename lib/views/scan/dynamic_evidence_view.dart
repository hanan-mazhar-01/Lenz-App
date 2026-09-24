import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/evidence.dart';
import '../../models/product.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/common/app_image.dart';

/// The requested capture plan. Every angle is a request, not a requirement —
/// the user may supply what they have and analyse at any time (§4, §27).
class DynamicEvidenceView extends StatelessWidget {
  final Product product;
  final List<EvidenceItem> evidenceItems;
  final Map<String, String> capturedImages;
  final int acceptedCount;
  final bool canAnalyze;

  final ValueChanged<int> onSelectPart;
  final ValueChanged<int> onMarkUnavailable;
  final ValueChanged<int> onClearEvidence;
  final VoidCallback onAnalyze;
  final VoidCallback onBack;

  const DynamicEvidenceView({
    super.key,
    required this.product,
    required this.evidenceItems,
    required this.capturedImages,
    required this.acceptedCount,
    required this.canAnalyze,
    required this.onSelectPart,
    required this.onMarkUnavailable,
    required this.onClearEvidence,
    required this.onAnalyze,
    required this.onBack,
  });

  /// Find the first uncaptured evidence index to start capturing from.
  int get _firstUncapturedIndex {
    for (int i = 0; i < evidenceItems.length; i++) {
      final item = evidenceItems[i];
      if (!capturedImages.containsKey(item.id) && !item.isUnavailable) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final total = evidenceItems.length;
    final allCaptured = evidenceItems.every(
      (e) => capturedImages.containsKey(e.id) || e.isUnavailable,
    );

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        child: Column(
          children: [
            // ───────────────────── Top bar: back arrow
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 20, 0),
              child: Row(
                children: [
                  BounceButton(
                    onTap: onBack,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.veryLightWarmGray,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.nearBlack.withOpacity(0.06),
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.chevron_back,
                          color: AppColors.nearBlack,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ───────────────────── Header: Title + photo count pill
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FadeSlideTransition(
                delay: const Duration(milliseconds: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'We need a closer look',
                            style: TextStyle(
                              color: AppColors.nearBlack,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Photo count pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.veryLightWarmGray,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.nearBlack.withOpacity(0.06),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.camera_fill,
                                size: 14,
                                color: AppColors.nearBlack,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$total photos',
                                style: TextStyle(
                                  color: AppColors.nearBlack,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "We'll guide you through the photos we need.",
                      style: TextStyle(
                        color: AppColors.charcoalGray,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ───────────────────── Evidence items list
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: evidenceItems.length,
                itemBuilder: (context, index) {
                  final item = evidenceItems[index];
                  final photo = capturedImages[item.id];
                  final hasPhoto = photo != null && photo.isNotEmpty;

                  return FadeSlideTransition(
                    delay: Duration(milliseconds: 60 + (index * 30)),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: BounceButton(
                        onTap: () => onSelectPart(index),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: hasPhoto
                                ? AppColors.pureWhite
                                : AppColors.veryLightWarmGray,
                            borderRadius: BorderRadius.circular(18),
                            border: hasPhoto
                                ? Border.all(
                                    color: AppColors.deepForestGreen
                                        .withOpacity(0.25),
                                    width: 1.2,
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              // Thumbnail or placeholder
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: hasPhoto
                                      ? Colors.transparent
                                      : AppColors.softWarmGray,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: hasPhoto
                                    ? AppImage(
                                        imagePath: photo,
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      )
                                    : item.imageAsset.isNotEmpty
                                        ? AppImage(
                                            imagePath: item.imageAsset,
                                            width: 60,
                                            height: 60,
                                            fit: BoxFit.cover,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          )
                                        : Center(
                                            child: Icon(
                                              item.isUnavailable
                                                  ? CupertinoIcons.nosign
                                                  : CupertinoIcons.camera,
                                              size: 22,
                                              color: AppColors.softGray,
                                            ),
                                          ),
                              ),

                              const SizedBox(width: 12),

                              // Number badge
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: hasPhoto
                                      ? AppColors.deepForestGreen
                                      : AppColors.nearBlack.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${item.index}',
                                    style: TextStyle(
                                      color: hasPhoto
                                          ? Colors.white
                                          : AppColors.nearBlack,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),

                              // Title + guide text
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: TextStyle(
                                        color: AppColors.nearBlack,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      hasPhoto
                                          ? 'Photo added ✓'
                                          : item.isUnavailable
                                              ? 'Skipped'
                                              : item.guide,
                                      style: TextStyle(
                                        color: hasPhoto
                                            ? AppColors.deepForestGreen
                                            : item.isUnavailable
                                                ? AppColors.softGray
                                                : AppColors.charcoalGray,
                                        fontSize: 12.5,
                                        fontWeight: hasPhoto
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        height: 1.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Checkmark or Chevron
                              if (hasPhoto)
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: AppColors.deepForestGreen,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 15,
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 16,
                                  color: AppColors.softGray,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ───────────────────── Bottom button: Start capturing / Check photos
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: BounceButton(
                onTap: allCaptured
                    ? (canAnalyze ? onAnalyze : null)
                    : () => onSelectPart(_firstUncapturedIndex),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    color: AppColors.deepForestGreen,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.deepForestGreen.withOpacity(0.2),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        allCaptured
                            ? 'Check $acceptedCount photo${acceptedCount == 1 ? '' : 's'}'
                            : 'Start capturing',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
