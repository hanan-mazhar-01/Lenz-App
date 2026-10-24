import 'package:flutter/material.dart';

import '../../models/evidence.dart';
import '../../models/product.dart';
import '../../widgets/camera/capture_guide_overlay.dart';
import '../../widgets/camera/lenz_camera_chrome.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// The requested capture plan. Every angle is a request, not a requirement —
/// the user may supply what they have and analyse at any time (§4, §27).
///
/// Lenz layout (prototype `SCREENS.evidence`): journey stepper at Evidence, a
/// progress ring of photos supplied, Lenz coaching, one row per requested
/// part (Done / Skipped / Capture), and the bottom action.
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

  bool _hasPhoto(EvidenceItem item) {
    final photo = capturedImages[item.id];
    return photo != null && photo.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final total = evidenceItems.length;
    final allCaptured = evidenceItems.every(
      (e) => capturedImages.containsKey(e.id) || e.isUnavailable,
    );
    final done = evidenceItems.where(_hasPhoto).length;
    final nextIndex = allCaptured ? -1 : _firstUncapturedIndex;
    final next = nextIndex >= 0 && nextIndex < total ? evidenceItems[nextIndex] : null;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final narrow = MediaQuery.of(context).size.width < 360;

    final coachText = allCaptured
        ? (canAnalyze ? 'Nice work! Ready when you are.' : 'That covers every photo on the list.')
        : next != null
        ? 'Next up: ${next.title}.'
        : "We'll guide you through the photos we need.";

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: LenzMoodBackground(
        mood: const Color(0xFFE4E0F4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              bottom: false,
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, 12, 20, 120 + safeBottom),
                children: [
                  LenzTopBar(title: 'Evidence', onBack: onBack),
                  const LenzJourneyStepper(step: 2, rider: LenzJourneyRider()),
                  LenzRise(
                    index: 0,
                    child: Row(
                      children: [
                        LenzRing(
                          value: total == 0 ? 0 : done / total,
                          size: narrow ? 82 : 96,
                          strokeWidth: narrow ? 10 : 11,
                          color: LenzColors.leaf,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                child: Text(
                                  '$done/$total',
                                  style: LenzText.stat.copyWith(fontSize: 26, height: 1),
                                ),
                              ),
                              Text('photos', style: LenzText.cap.copyWith(fontSize: 11)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'We need a closer look',
                                style: LenzText.display.copyWith(fontSize: 25),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "We'll guide you through the photos we need.",
                                style: LenzText.sub,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  LenzRise(
                    index: 1,
                    child: LenzCoach(
                      mood: allCaptured ? LenzMood.pleased : LenzMood.think,
                      text: coachText,
                      width: 104,
                      margin: const EdgeInsets.only(top: 6, bottom: 8),
                    ),
                  ),
                  for (var i = 0; i < evidenceItems.length; i++)
                    LenzRise(
                      index: 2 + i,
                      child: _row(i, evidenceItems[i], isNext: i == nextIndex),
                    ),
                ],
              ),
            ),

            // ───────────────────── Bottom action over an ivory fade
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + safeBottom),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00FCF8F6), LenzColors.ivory],
                    stops: [0, .38],
                  ),
                ),
                child: allCaptured
                    ? LenzButton(
                        label: 'Check $acceptedCount photo${acceptedCount == 1 ? '' : 's'}',
                        icon: LenzIcons.sparkles,
                        pulse: canAnalyze,
                        onPressed: canAnalyze ? onAnalyze : null,
                      )
                    : LenzButton(
                        label: done == 0 ? 'Start capturing' : 'Take next photo',
                        icon: LenzIcons.camera,
                        onPressed: () => onSelectPart(_firstUncapturedIndex),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int index, EvidenceItem item, {required bool isNext}) {
    final photo = capturedImages[item.id];
    final hasPhoto = photo != null && photo.isNotEmpty;
    final skipped = !hasPhoto && item.isUnavailable;

    Widget thumb;
    if (hasPhoto) {
      thumb = Stack(
        fit: StackFit.expand,
        children: [
          AppImage(imagePath: photo, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x99BFE3CB), Color(0xCC7FCB97)],
              ),
            ),
          ),
          const Center(
            child: LenzIcon(LenzIcons.check, size: 26, strokeWidth: 3, color: Colors.white),
          ),
        ],
      );
    } else if (item.imageAsset.isNotEmpty) {
      thumb = AppImage(imagePath: item.imageAsset, fit: BoxFit.cover);
    } else {
      thumb = Center(
        child: CaptureGuideIllustration(
          type: item.guideType,
          size: 40,
          background: Colors.transparent,
          foreground: LenzColors.forest,
        ),
      );
    }

    final Widget trailing;
    if (hasPhoto) {
      trailing = const LenzPill(label: 'Done', variant: LenzPillVariant.auth);
    } else if (skipped) {
      trailing = const LenzPill(
        label: 'Skipped',
        background: Color(0xFFEEEEEE),
        foreground: Color(0xFF777777),
      );
    } else if (isNext) {
      trailing = const LenzPill(
        label: 'Capture',
        icon: LenzIcons.camera,
        background: LenzColors.forest,
        foreground: Colors.white,
      );
    } else {
      trailing = const LenzIcon(LenzIcons.chevR, size: 18, color: LenzColors.ink);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LenzPressable(
        onTap: () => onSelectPart(index),
        pressedScale: .97,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: LenzColors.paper,
            borderRadius: BorderRadius.circular(LenzRadii.item),
            border: Border.all(
              color: isNext ? LenzColors.leaf : LenzColors.line,
              width: isNext ? 2 : 1,
            ),
            boxShadow: [
              if (isNext) const BoxShadow(color: Color.fromRGBO(46, 164, 79, .12), spreadRadius: 6),
              ...LenzShadows.sh1,
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: LenzColors.mint2,
                  borderRadius: BorderRadius.circular(18),
                ),
                clipBehavior: Clip.antiAlias,
                child: thumb,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LenzText.item,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      skipped ? 'Skipped' : item.guide,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LenzText.itemSub,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
