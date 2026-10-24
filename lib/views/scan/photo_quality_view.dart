import 'package:flutter/material.dart';

import '../../models/evidence.dart';
import '../../models/evidence_validation.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// Review screen shown after every submitted photo.
///
/// Presents photo quality and authentication usefulness as separate numbers,
/// and refuses a photo that does not show the requested area (§10-14).
///
/// Lenz layout (prototype `SCREENS.quality`): the photo with the part label
/// and a status pill, Lenz reacting, meters bound to the validation's real
/// scores (amber when weak), then Keep / Retake / Keep anyway.
class PhotoQualityView extends StatelessWidget {
  final EvidenceItem item;
  final String? photoPath;
  final EvidenceValidationResult validation;

  /// Accept the photo as evidence for this item.
  final VoidCallback onKeep;

  /// Keep a photo the app flagged as low quality. Null when not permitted.
  final VoidCallback? onKeepAnyway;

  final VoidCallback onRetake;
  final VoidCallback onChooseAnother;

  const PhotoQualityView({
    super.key,
    required this.item,
    required this.validation,
    required this.onKeep,
    required this.onRetake,
    required this.onChooseAnother,
    this.photoPath,
    this.onKeepAnyway,
  });

  /// Below this a measurement is shown amber (same 70 line as the old
  /// colour scale's "good").
  static const int _warnBelow = 70;

  @override
  Widget build(BuildContext context) {
    final verdict = validation.verdict;
    final quality = validation.quality;
    final isWrongEvidence = verdict == EvidenceVerdict.rejectedWrongEvidence;
    final isRejected = verdict != EvidenceVerdict.accepted;
    final canKeepAnyway = validation.isOverridable && onKeepAnyway != null;

    // One consistent plain-English line, plus short fix-it hints (§22, §23).
    final note = validation.usefulnessExplanation;
    final tips = {
      if (quality.firstFix != null) quality.firstFix!,
      ...validation.issues.where((i) => i.length < 60),
    }.where((t) => t != validation.headline).toList();

    final mood = isWrongEvidence
        ? LenzMood.sorry
        : isRejected
        ? LenzMood.unsure
        : LenzMood.happy;
    final coachText = isRejected
        ? '${validation.guidance} ${validation.callToAction}'
        : '${validation.headline}! $note';

    // The prototype's three meters, bound to the real measurements. A
    // sub-score of 0 means the model did not report it: it is left out
    // rather than drawn as an empty bar.
    final meters = <_MeterRow>[
      if (quality.sharpness > 0) _MeterRow('Sharpness', quality.sharpness),
      if (quality.lighting > 0) _MeterRow('Lighting', quality.lighting),
      _MeterRow(
        'Right part',
        validation.matchConfidence,
        caption: validation.matchToRequestedEvidence
            ? 'Shows the ${item.title.toLowerCase()}'
            : "Doesn't show the ${item.title.toLowerCase()}",
        warn: !validation.matchToRequestedEvidence,
      ),
    ];
    final details = <_MeterRow>[
      _MeterRow('Photo quality', quality.qualityScore, caption: quality.simpleSummary),
      _MeterRow(
        'Check usefulness',
        validation.authenticationUsefulness,
        caption: validation.usefulnessLabel,
      ),
      if (quality.framing > 0) _MeterRow('Framing', quality.framing),
      if (quality.detail > 0) _MeterRow('Close-up', quality.detail),
    ];

    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: LenzMoodBackground(
        mood: isRejected ? const Color(0xFFF6E4B8) : const Color(0xFFCFEED6),
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + safeBottom),
            children: [
              LenzTopBar(title: 'Photo quality', onBack: onRetake),

              // ------------------------------------------------ the photo
              LenzRise(
                index: 0,
                child: LenzCard(
                  radius: 32,
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: 210,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(0, -.2),
                                radius: .8,
                                colors: [Color(0xFF3B5F50), Color(0xFF14221C)],
                              ),
                            ),
                          ),
                          if (photoPath != null && photoPath!.isNotEmpty)
                            AppImage(
                              imagePath: photoPath!,
                              fit: BoxFit.cover,
                              placeholder: const SizedBox.shrink(),
                            ),
                          Positioned(
                            left: 12,
                            top: 12,
                            right: 12,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(child: _pillBox(LenzPill(label: item.title))),
                                const SizedBox(width: 8),
                                isRejected
                                    ? LenzPill(
                                        label: validation.headline,
                                        icon: LenzIcons.warn,
                                        iconStrokeWidth: 3,
                                        variant: isWrongEvidence
                                            ? LenzPillVariant.fake
                                            : LenzPillVariant.unsure,
                                      )
                                    : const LenzPill(
                                        label: 'Looks good',
                                        icon: LenzIcons.check,
                                        iconStrokeWidth: 3,
                                        variant: LenzPillVariant.auth,
                                      ),
                              ],
                            ),
                          ),
                          if (isWrongEvidence)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 12,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _pillBox(
                                  LenzPill(
                                    label: 'Looks like: ${validation.evidenceTypeDetected}',
                                    variant: LenzPillVariant.fake,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // -------------------------------------------- Lenz reacts
              LenzRise(
                index: 1,
                child: LenzCoach(
                  mood: mood,
                  text: coachText,
                  width: 118,
                  margin: const EdgeInsets.only(top: 6, bottom: 8),
                ),
              ),

              // ------------------------------------- the real measurements
              LenzRise(
                index: 2,
                child: LenzCard(
                  radius: 28,
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [for (final m in meters) _meter(m)]),
                ),
              ),
              const SizedBox(height: 12),
              LenzRise(
                index: 3,
                child: LenzCard(
                  radius: 24,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PHOTO DETAILS',
                        style: LenzText.cap.copyWith(fontSize: 11.5, letterSpacing: .8),
                      ),
                      const SizedBox(height: 4),
                      for (final m in details) _detail(m),
                    ],
                  ),
                ),
              ),

              if (note.isNotEmpty && isRejected) ...[
                const SizedBox(height: 12),
                LenzRise(
                  index: 4,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: LenzColors.warnSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LenzIcon(
                          LenzIcons.warn,
                          size: 16,
                          strokeWidth: 2.4,
                          color: LenzColors.warn,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(note, style: LenzText.cap.copyWith(color: LenzColors.warn)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (tips.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final t in tips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6, right: 8),
                          child: SizedBox(
                            width: 5,
                            height: 5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: LenzColors.muted,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: Text(t, style: LenzText.cap)),
                      ],
                    ),
                  ),
              ],

              const SizedBox(height: 16),

              // ---------------------------------------------------- actions
              LenzRise(
                index: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isRejected) ...[
                      LenzButton(
                        label: 'Keep photo',
                        icon: LenzIcons.check,
                        iconStrokeWidth: 2.6,
                        onPressed: onKeep,
                      ),
                      const SizedBox(height: 8),
                      LenzButton(
                        label: 'Retake',
                        variant: LenzButtonVariant.ghost,
                        onPressed: onRetake,
                      ),
                    ] else ...[
                      LenzButton(
                        label: 'Retake photo',
                        icon: LenzIcons.refresh,
                        variant: canKeepAnyway
                            ? LenzButtonVariant.ghost
                            : LenzButtonVariant.primary,
                        onPressed: onRetake,
                      ),
                      if (canKeepAnyway) ...[
                        const SizedBox(height: 8),
                        LenzButton(
                          label: 'Keep anyway',
                          variant: LenzButtonVariant.soft,
                          onPressed: onKeepAnyway,
                        ),
                      ],
                    ],
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        onPressed: onChooseAnother,
                        child: Text(
                          'Choose another photo',
                          style: LenzText.link.copyWith(color: LenzColors.forest2),
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

  static Widget _pillBox(Widget pill) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: pill);

  Widget _meter(_MeterRow m) {
    final warn = m.warn || m.value < _warnBelow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.label, style: LenzText.item.copyWith(fontSize: 15.5)),
                    if (m.caption != null)
                      Text(m.caption!, style: LenzText.itemSub.copyWith(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              LenzPill(
                label: '${m.value}%',
                variant: warn ? LenzPillVariant.unsure : LenzPillVariant.auth,
              ),
            ],
          ),
          const SizedBox(height: 8),
          warn ? LenzMeter.warn(value: m.value / 100) : LenzMeter(value: m.value / 100),
        ],
      ),
    );
  }

  Widget _detail(_MeterRow m) {
    final warn = m.value < _warnBelow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.label, style: LenzText.item.copyWith(fontSize: 14)),
                if (m.caption != null)
                  Text(m.caption!, style: LenzText.itemSub.copyWith(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${m.value}%',
            style: LenzText.item.copyWith(
              fontSize: 15,
              color: warn ? LenzColors.warn : LenzColors.ok,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeterRow {
  final String label;
  final int value;
  final String? caption;
  final bool warn;
  const _MeterRow(this.label, this.value, {this.caption, this.warn = false});
}
