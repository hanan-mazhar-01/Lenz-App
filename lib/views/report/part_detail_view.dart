import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/evidence.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/common/app_image.dart';

class PartDetailView extends StatelessWidget {
  final EvidenceItem item;
  final VoidCallback onBack;
  final VoidCallback onOpenDetectYourself;

  const PartDetailView({
    super.key,
    required this.item,
    required this.onBack,
    required this.onOpenDetectYourself,
  });

  void _openFullScreenImage(BuildContext context, String imagePath, String title) {
    if (imagePath.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.8,
              maxScale: 4.5,
              child: AppImage(
                imagePath: imagePath,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLowScore = item.status == EvidenceStatus.suspicious || item.score < 60;
    final displayImg = item.displayImage;

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      appBar: AppBar(
        backgroundColor: AppColors.warmIvory,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: BounceButton(
              onTap: onBack,
              child: Container(
                width: 40,
                height: 40,
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
          ),
        ),
        title: Text(
          item.title,
          style: const TextStyle(
            color: AppColors.nearBlack,
            fontSize: 17.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // Large Evidence Image Card with Tap to Zoom
              FadeSlideTransition(
                delay: const Duration(milliseconds: 40),
                child: GestureDetector(
                  onTap: () => _openFullScreenImage(context, displayImg, item.title),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.veryLightWarmGray,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.nearBlack.withOpacity(0.06),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.nearBlack.withOpacity(0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        displayImg.isNotEmpty
                            ? AppImage(
                                imagePath: displayImg,
                                width: double.infinity,
                                height: 240,
                                fit: BoxFit.contain,
                              )
                            : Container(
                                width: double.infinity,
                                height: 200,
                                color: AppColors.softWarmGray,
                                child: const Center(
                                  child: Icon(
                                    CupertinoIcons.photo,
                                    size: 48,
                                    color: AppColors.softGray,
                                  ),
                                ),
                              ),
                        if (displayImg.isNotEmpty)
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.zoom_in, color: Colors.white, size: 15),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tap to zoom',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
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
              ),

              const SizedBox(height: 16),

              // Score and Consistency Badge Card
              FadeSlideTransition(
                delay: const Duration(milliseconds: 80),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.veryLightWarmGray,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.nearBlack.withOpacity(0.06),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.nearBlack.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            item.score > 0 ? '${item.score}' : '--',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: isLowScore ? const Color(0xFFDC2626) : AppColors.deepForestGreen,
                            ),
                          ),
                          const Text(
                            ' /100',
                            style: TextStyle(
                              color: AppColors.softGray,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 1.2,
                        height: 32,
                        color: AppColors.nearBlack.withOpacity(0.08),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isLowScore
                              ? const Color(0xFFFEE2E2)
                              : AppColors.deepForestGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          item.status.label,
                          style: TextStyle(
                            color: isLowScore ? const Color(0xFFDC2626) : AppColors.deepForestGreen,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Visual Observations Card
              if (item.observations.isNotEmpty) ...[
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 100),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.veryLightWarmGray,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.nearBlack.withOpacity(0.06),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Visual Observations',
                          style: TextStyle(
                            color: AppColors.nearBlack,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...item.observations.map(
                          (obs) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(
                                    color: AppColors.deepForestGreen,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    obs,
                                    style: const TextStyle(
                                      color: AppColors.charcoalGray,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                    ),
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
                const SizedBox(height: 16),
              ],

              // Inconsistencies or Flaws Detected
              if (item.inconsistentSignals.isNotEmpty) ...[
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 120),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.veryLightWarmGray,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFDC2626).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Color(0xFFDC2626), size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Inconsistencies Flagged',
                              style: TextStyle(
                                color: Color(0xFFDC2626),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...item.inconsistentSignals.map(
                          (flaw) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              '⚠️ $flaw',
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Consistent Signals
              if (item.consistentSignals.isNotEmpty) ...[
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 130),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.veryLightWarmGray,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.nearBlack.withOpacity(0.06),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(CupertinoIcons.checkmark_circle_fill, color: AppColors.deepForestGreen, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Consistent Manufacturing Signals',
                              style: TextStyle(
                                color: AppColors.nearBlack,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...item.consistentSignals.map(
                          (sig) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(CupertinoIcons.check_mark, size: 14, color: AppColors.deepForestGreen),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    sig,
                                    style: const TextStyle(
                                      color: AppColors.charcoalGray,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                    ),
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
                const SizedBox(height: 16),
              ],

              // Capture Guideline Note
              FadeSlideTransition(
                delay: const Duration(milliseconds: 140),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.veryLightWarmGray,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.nearBlack.withOpacity(0.06),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Inspection Criteria',
                        style: TextStyle(
                          color: AppColors.nearBlack,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.guide,
                        style: const TextStyle(
                          color: AppColors.charcoalGray,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Bottom Button: Physical Detection Tips
              FadeSlideTransition(
                delay: const Duration(milliseconds: 160),
                child: BounceButton(
                  onTap: onOpenDetectYourself,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.deepForestGreen,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.deepForestGreen.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Physical Detection Tips',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
