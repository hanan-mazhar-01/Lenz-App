import 'package:flutter/material.dart';

import '../../models/evidence.dart';
import '../../widgets/camera/capture_guide_overlay.dart';
import '../../widgets/camera/lenz_camera_chrome.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// Shown while a submitted photo is being checked against the requested angle.
///
/// Lenz layout: journey stepper at Evidence, Lenz inspecting through his
/// magnifier, the part being checked, and an indeterminate bar (the check has
/// no measurable progress, so none is invented).
class ValidatingPhotoView extends StatelessWidget {
  final EvidenceItem? item;

  const ValidatingPhotoView({super.key, this.item});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final lenzWidth = (size.width * .56).clamp(150.0, 230.0);
    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: LenzMoodBackground(
        mood: LenzColors.mint,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 36),
                child: Column(
                  children: [
                    const LenzJourneyStepper(step: 2, rider: LenzJourneyRider()),
                    SizedBox(height: size.height < 700 ? 8 : 36),
                    SizedBox(
                      width: lenzWidth,
                      child: const LenzCharacter(mood: LenzMood.inspect, view: LenzView.bust),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Checking your photo',
                      textAlign: TextAlign.center,
                      style: LenzText.display.copyWith(fontSize: 28),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item != null
                          ? 'Confirming this shows the ${item!.title.toLowerCase()} clearly enough to inspect.'
                          : 'Confirming this shows the requested detail.',
                      textAlign: TextAlign.center,
                      style: LenzText.sub,
                    ),
                    const SizedBox(height: 22),
                    if (item != null)
                      LenzCard(
                        radius: 24,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CaptureGuideIllustration(
                              type: item!.guideType,
                              size: 46,
                              background: LenzColors.mint2,
                              foreground: LenzColors.forest,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item!.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: LenzText.item,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                color: LenzColors.leaf,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: const LinearProgressIndicator(
                          minHeight: 8,
                          color: LenzColors.leaf,
                          backgroundColor: LenzColors.meterTrack,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
