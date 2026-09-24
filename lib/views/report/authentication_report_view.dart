import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/authentication_result.dart';
import '../../models/collection_item.dart';
import '../../models/evidence.dart';
import '../../repositories/collection_repository.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/cards/animated_favorite_button.dart';
import '../../widgets/common/app_image.dart';
import '../../services/haptics.dart';

class AuthenticationReportView extends StatefulWidget {
  final AuthenticationReport report;
  final VoidCallback onDone;
  final VoidCallback onToggleFavorite;
  final ValueChanged<EvidenceItem> onSelectPart;
  final VoidCallback onOpenDetectYourself;
  final VoidCallback? onCaptureMoreEvidence;

  const AuthenticationReportView({
    super.key,
    required this.report,
    required this.onDone,
    required this.onToggleFavorite,
    required this.onSelectPart,
    required this.onOpenDetectYourself,
    this.onCaptureMoreEvidence,
  });

  @override
  State<AuthenticationReportView> createState() => _AuthenticationReportViewState();
}

class _AuthenticationReportViewState extends State<AuthenticationReportView> {
  bool _savedToCollection = false;

  @override
  void initState() {
    super.initState();
    _savedToCollection =
        context.read<CollectionRepository>().containsReport(widget.report.id);
  }

  void _saveToCollection() {
    Haptics.mediumImpact();
    context.read<CollectionRepository>().addItem(
          CollectionItem.fromReport(widget.report),
        );
    setState(() => _savedToCollection = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved to My Collection'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final int score = report.authenticationConfidence;

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            CupertinoIcons.chevron_back,
            color: AppColors.nearBlack,
            size: 24,
          ),
          onPressed: widget.onDone,
        ),
        centerTitle: true,
        title: const Text(
          'Authentication Report',
          style: TextStyle(
            color: AppColors.nearBlack,
            fontSize: 18.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _savedToCollection ? 'Saved to Collection' : 'Save to Collection',
            icon: Icon(
              _savedToCollection ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
              color: _savedToCollection ? AppColors.deepForestGreen : AppColors.nearBlack,
              size: 22,
            ),
            onPressed: _saveToCollection,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedFavoriteButton(
              isFavorite: report.isFavorite,
              onToggle: widget.onToggleFavorite,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
          children: [
            // 1. Product Card
            FadeSlideTransition(
              delay: const Duration(milliseconds: 40),
              child: _buildProductCard(context, report),
            ),

            const SizedBox(height: 18),

            // 2. Score Ring + Verdict Badge + 1-line Reason
            FadeSlideTransition(
              delay: const Duration(milliseconds: 80),
              child: _buildScoreAndVerdictSection(context, score, report),
            ),

            const SizedBox(height: 18),

            // 3. Quick Summary Card
            FadeSlideTransition(
              delay: const Duration(milliseconds: 120),
              child: _buildQuickSummaryCard(context, report),
            ),

            const SizedBox(height: 22),

            // 4. Evidence List Section (Only shows items with user photos + percentage indicator line)
            FadeSlideTransition(
              delay: const Duration(milliseconds: 160),
              child: _buildEvidenceSection(context, report),
            ),

            const SizedBox(height: 20),

            // 5. "Check It Yourself" Button
            FadeSlideTransition(
              delay: const Duration(milliseconds: 200),
              child: _buildCheckYourselfButton(context),
            ),

            const SizedBox(height: 24),

            // 6. Disclaimer
            const Center(
              child: Text(
                'AI assessment, not a professional certification.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.softGray,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1. Product Card matching the reference mockup
  Widget _buildProductCard(BuildContext context, AuthenticationReport report) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          // Product Thumbnail
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.nearBlack.withOpacity(0.08),
                width: 0.8,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: AppImage(
                imagePath: report.product.imageAsset,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Product Name & Category
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  report.product.name,
                  style: const TextStyle(
                    color: AppColors.nearBlack,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${report.product.category.label} · ${report.product.brand}',
                  style: const TextStyle(
                    color: AppColors.charcoalGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 2. Score Ring + Verdict Badge + Single line Reason
  Widget _buildScoreAndVerdictSection(
    BuildContext context,
    int score,
    AuthenticationReport report,
  ) {
    // Determine verdict state:
    final bool isAuthentic = report.verdict == Verdict.likelyAuthentic;
    final bool isReplica = report.verdict == Verdict.likelyReplica;

    final Color ringColor = isAuthentic
        ? AppColors.deepForestGreen
        : (isReplica ? const Color(0xFF991B1B) : const Color(0xFFD97706));

    final Color badgeBg = isAuthentic
        ? AppColors.deepForestGreen
        : (isReplica ? const Color(0xFF991B1B) : const Color(0xFF5F6264));

    final IconData badgeIcon = isAuthentic
        ? CupertinoIcons.shield_lefthalf_fill
        : (isReplica
            ? CupertinoIcons.exclamationmark_shield_fill
            : CupertinoIcons.question_circle_fill);

    // Use the Verdict enum's own label directly so this always matches
    // exactly what the rest of the app (history cards, stats, etc.) calls
    // the same verdict - it previously said "Replica"/"Uncertain" here
    // while everywhere else said "Likely Replica"/"Inconclusive".
    final String badgeText = report.verdict.label;

    // 1-line reason explaining the confidence percentage clearly
    String singleLineReason;
    if (isAuthentic) {
      singleLineReason = '$score% confidence genuine based on matching specifications.';
    } else if (isReplica) {
      singleLineReason = '$score% confidence replica based on detected manufacturing flaws.';
    } else {
      singleLineReason = report.rationale.isNotEmpty
          ? report.rationale.split('.').first
          : 'More evidence needed to determine authenticity.';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Circular Score Ring showing confidence percentage
        SizedBox(
          width: 88,
          height: 88,
          child: CustomPaint(
            painter: _ScoreRingPainter(
              progress: (score / 100).clamp(0.0, 1.0),
              color: ringColor,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$score%',
                    style: const TextStyle(
                      color: AppColors.nearBlack,
                      fontSize: 22.5,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isReplica ? 'Replica' : (isAuthentic ? 'Authentic' : 'Confidence'),
                    style: const TextStyle(
                      color: AppColors.charcoalGray,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 18),

        // Verdict Badge Pill + 1-line reason underneath
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Verdict Badge Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: badgeBg.withOpacity(0.24),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, color: Colors.white, size: 17),
                    const SizedBox(width: 8),
                    Text(
                      badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 1-line explanation underneath verdict
              Text(
                singleLineReason,
                style: const TextStyle(
                  color: AppColors.charcoalGray,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 3. Quick Summary Card
  Widget _buildQuickSummaryCard(BuildContext context, AuthenticationReport report) {
    // Derive clean summary bullet points from quickSummaryPoints or positive findings or defaults
    final List<String> bulletPoints = [];
    if (report.quickSummaryPoints.isNotEmpty) {
      bulletPoints.addAll(report.quickSummaryPoints.take(2));
    } else if (report.positiveFindings.isNotEmpty) {
      bulletPoints.addAll(report.positiveFindings.take(2));
    }

    if (bulletPoints.isEmpty) {
      bulletPoints.add('Logo placement and typography analyzed.');
      bulletPoints.add('Materials, seams, and hardware inspected.');
    } else if (bulletPoints.length == 1) {
      bulletPoints.add('Materials and finishing analyzed.');
    }

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Document icon + Quick Summary
          Row(
            children: const [
              Icon(
                Icons.article_outlined,
                size: 20,
                color: AppColors.nearBlack,
              ),
              SizedBox(width: 8),
              Text(
                'Quick Summary',
                style: TextStyle(
                  color: AppColors.nearBlack,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Bullet points
          ...bulletPoints.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: AppColors.deepForestGreen,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      point,
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
    );
  }

  /// 4. Evidence List Section (Only shows items with user-supplied photos + progress indicator)
  Widget _buildEvidenceSection(BuildContext context, AuthenticationReport report) {
    // Only show evidence items where the user actually captured or provided a photo
    final evidenceList = report.evidenceItems
        .where((e) => e.hasPhoto || e.capturedImagePath.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text(
              'Evidence',
              style: TextStyle(
                color: AppColors.nearBlack,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            if (evidenceList.isNotEmpty)
              Text(
                '${evidenceList.length} verified item${evidenceList.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: AppColors.charcoalGray,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),

        const SizedBox(height: 10),

        Container(
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
          child: evidenceList.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Center(
                    child: Text(
                      'No specific part photos were provided for this scan.',
                      style: TextStyle(color: AppColors.charcoalGray, fontSize: 13),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                  itemCount: evidenceList.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 16,
                    thickness: 0.8,
                    color: Color(0xFFE8E2DD),
                  ),
                  itemBuilder: (context, i) {
                    final item = evidenceList[i];
                    final int itemPercent = item.score > 0
                        ? item.score
                        : (item.photoQualityScore > 0 ? item.photoQualityScore : report.authenticationConfidence);

                    final Color progressColor = itemPercent >= 75
                        ? AppColors.deepForestGreen
                        : (itemPercent >= 45 ? const Color(0xFFD97706) : const Color(0xFFDC2626));

                    return InkWell(
                      onTap: () => widget.onSelectPart(item),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Evidence thumbnail image
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: AppColors.warmIvory,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.nearBlack.withOpacity(0.08),
                                    width: 1,
                                  ),
                                ),
                                child: item.displayImage.isNotEmpty
                                    ? AppImage(
                                        imagePath: item.displayImage,
                                        width: 46,
                                        height: 46,
                                        fit: BoxFit.cover,
                                        placeholder: Center(
                                          child: Icon(
                                            _resolveEvidenceIcon(item.title),
                                            size: 20,
                                            color: AppColors.deepForestGreen,
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Icon(
                                          _resolveEvidenceIcon(item.title),
                                          size: 20,
                                          color: AppColors.deepForestGreen,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(width: 14),

                            // Item title & Progress indicator line
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: const TextStyle(
                                            color: AppColors.nearBlack,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Percentage badge text
                                      Text(
                                        '$itemPercent%',
                                        style: TextStyle(
                                          color: progressColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Indicator line: filled to itemPercent out of 100%
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: Container(
                                      height: 5.5,
                                      width: double.infinity,
                                      color: const Color(0xFFE2DDD7),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: FractionallySizedBox(
                                          widthFactor: (itemPercent / 100.0).clamp(0.03, 1.0),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: progressColor,
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 10),

                            // Chevron right
                            const Icon(
                              CupertinoIcons.chevron_right,
                              size: 15,
                              color: AppColors.softGray,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 5. "Check Yourself" Button
  Widget _buildCheckYourselfButton(BuildContext context) {
    return BounceButton(
      onTap: () {
        Haptics.lightImpact();
        widget.onOpenDetectYourself();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.deepForestGreen,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepForestGreen.withOpacity(0.24),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.search,
                color: Colors.white,
                size: 17,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Check It Yourself',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Hands-on physical tips for ${widget.report.product.name}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.arrow_right,
              color: Colors.white.withOpacity(0.8),
              size: 17,
            ),
          ],
        ),
      ),
    );
  }

  IconData _resolveEvidenceIcon(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('dial') || lower.contains('face')) {
      return CupertinoIcons.time;
    } else if (lower.contains('crown') || lower.contains('logo') || lower.contains('stamp')) {
      return Icons.military_tech_outlined;
    } else if (lower.contains('serial') || lower.contains('code') || lower.contains('tag')) {
      return Icons.numbers_rounded;
    } else if (lower.contains('stitch') || lower.contains('seam')) {
      return Icons.linear_scale_rounded;
    } else if (lower.contains('sole') || lower.contains('heel') || lower.contains('shoe')) {
      return Icons.hiking_rounded;
    } else if (lower.contains('leather') || lower.contains('material')) {
      return Icons.texture_rounded;
    }
    return CupertinoIcons.viewfinder;
  }
}

/// Custom painter for the circular score ring
class _ScoreRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ScoreRingPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 8) / 2;

    // Background track ring
    final bgPaint = Paint()
      ..color = const Color(0xFFE2DDD7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawCircle(center, radius, bgPaint);

    // Active progress arc
    final activePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
