import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/authentication_result.dart';
import '../../models/evidence.dart';
import '../../widgets/cards/animated_favorite_button.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/lenz_confetti.dart';
import '../../widgets/ui/ui.dart';

/// The verdict report (prototype `SCREENS.report`): verdict hero with Lenz
/// reacting to the result, summary card with the evidence-strength ring,
/// per-part evidence list and the disclaimer.
///
/// Every value shown comes from the real [AuthenticationReport]. Engine v3+
/// reports carry no numeric confidence: the ring shows the qualitative
/// evidence strength (Strong / Moderate / Limited); only legacy reports that
/// stored a percentage show one.
class AuthenticationReportView extends StatefulWidget {
  final AuthenticationReport report;
  final VoidCallback onDone;
  final VoidCallback onToggleFavorite;
  final ValueChanged<EvidenceItem> onSelectPart;
  final VoidCallback? onCaptureMoreEvidence;

  const AuthenticationReportView({
    super.key,
    required this.report,
    required this.onDone,
    required this.onToggleFavorite,
    required this.onSelectPart,
    this.onCaptureMoreEvidence,
  });

  @override
  State<AuthenticationReportView> createState() => _AuthenticationReportViewState();
}

/// Lenz's first line per verdict (prototype `BUB`) and the line after a tap.
const Map<LenzVerdictKind, (String, String)> _bubbles = {
  LenzVerdictKind.auth: ('This one passes my inspection!', 'Told you, a good one!'),
  LenzVerdictKind.fake: ('Oh no. I found some red flags.', 'Trust the details, not the tag.'),
  LenzVerdictKind.unsure: ("Hmm, I can't say for sure.", 'More photos, please!'),
};

LenzMood _moodFor(LenzVerdictKind k) => switch (k) {
      LenzVerdictKind.auth => LenzMood.happy,
      LenzVerdictKind.fake => LenzMood.shocked,
      LenzVerdictKind.unsure => LenzMood.unsure,
    };

class _AuthenticationReportViewState extends State<AuthenticationReportView> {
  final LenzConfettiController _confetti = LenzConfettiController();
  Timer? _confettiTimer;
  bool _tapped = false;

  @override
  void initState() {
    super.initState();
    // Confetti only for an authentic verdict (prototype: 600ms after mount).
    if (widget.report.verdict == Verdict.likelyAuthentic) {
      _confettiTimer = Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        final w = MediaQuery.sizeOf(context).width;
        _confetti.burst(origin: Offset(w / 2, 260), count: 130);
      });
    }
  }

  @override
  void dispose() {
    _confettiTimer?.cancel();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final v = LenzVerdictStyle.of(report.verdict);
    final pad = MediaQuery.paddingOf(context);
    final bubble = _bubbles[v.kind]!;

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LenzBlob(color: v.bg, height: 520),
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Back / favorite row (the app has no share feature).
                Padding(
                  padding: EdgeInsets.fromLTRB(20, pad.top + 14, 20, 0),
                  child: Row(
                    children: [
                      LenzIconButton(
                        icon: LenzIcons.chevL,
                        semanticLabel: 'Back',
                        onTap: widget.onDone,
                      ),
                      const Spacer(),
                      LenzIconButton(
                        semanticLabel: 'Favorite',
                        onTap: widget.onToggleFavorite,
                        child: AnimatedFavoriteButton(
                          isFavorite: report.isFavorite,
                          onToggle: widget.onToggleFavorite,
                        ),
                      ),
                    ],
                  ),
                ),
                // Verdict hero: Lenz reacting + bubble.
                SizedBox(
                  height: 260,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: -2,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: SizedBox(
                            width: 270,
                            child: LenzCharacter(
                              mood: _moodFor(v.kind),
                              view: LenzView.bust,
                              onTap: () => setState(() => _tapped = true),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        top: 34,
                        child: LenzBubble(
                          key: ValueKey(_tapped),
                          text: _tapped ? bubble.$2 : bubble.$1,
                          maxWidth: 150,
                        ),
                      ),
                    ],
                  ),
                ),
                _sheet(context, report, v, pad),
              ],
            ),
          ),
          Positioned.fill(child: LenzConfetti(controller: _confetti)),
        ],
      ),
    );
  }

  Widget _sheet(BuildContext context, AuthenticationReport report, LenzVerdictStyle v, EdgeInsets pad) {
    final children = <Widget>[
      _verdictHeader(report, v),
      _summaryCard(report, v),
      if (_hasAssessmentDetails(report)) _assessmentDetailsCard(report),
      _evidenceSection(report),
      const Text(
        'AI-assisted opinion, not an official authentication.',
        textAlign: TextAlign.center,
        style: LenzText.tiny,
      ),
      _actions(report),
    ];

    return Container(
      constraints: const BoxConstraints(minHeight: 560),
      padding: EdgeInsets.fromLTRB(20, 26, 20, 34 + pad.bottom),
      decoration: const BoxDecoration(
        color: LenzColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(18, 47, 36, .3),
            offset: Offset(0, -24),
            blurRadius: 60,
            spreadRadius: -24,
          ),
        ],
      ),
      child: LenzStagger(spacing: 16, children: children),
    );
  }

  // ------------------------------------------------------------ verdict head
  Widget _verdictHeader(AuthenticationReport report, LenzVerdictStyle v) {
    return Column(
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: v.soft,
            borderRadius: BorderRadius.circular(LenzRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LenzIcon(v.icon, size: 17, strokeWidth: 2.4, color: v.color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  report.verdict.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LenzText.pill.copyWith(fontSize: 14.5, color: v.color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          report.product.name,
          textAlign: TextAlign.center,
          style: LenzText.display.copyWith(fontSize: 30),
        ),
        const SizedBox(height: 8),
        Text(
          '${report.product.category.label} · ${report.product.brand}',
          textAlign: TextAlign.center,
          style: LenzText.cap,
        ),
      ],
    );
  }

  // ------------------------------------------------------------ summary card
  Widget _summaryCard(AuthenticationReport report, LenzVerdictStyle v) {
    final isAuthentic = report.verdict == Verdict.likelyAuthentic;
    final isReplica = report.verdict == Verdict.likelyReplica;
    final score = report.authenticationConfidence;

    // Engine v3 reports carry no percentage: the ring shows the evidence
    // strength word instead (same binding as before the redesign).
    final qualitative = report.usesQualitativeStrength;
    final strengthWord = (() {
      final s = report.evidenceStrength ?? 'limited';
      return '${s[0].toUpperCase()}${s.substring(1)}';
    })();
    final ringProgress = qualitative
        ? (report.evidenceStrength == 'strong'
            ? 1.0
            : report.evidenceStrength == 'moderate'
                ? 0.66
                : 0.33)
        : (score / 100).clamp(0.0, 1.0);

    String reason;
    if (qualitative && (isAuthentic || isReplica)) {
      reason = report.rationale.isNotEmpty
          ? report.rationale.split('.').first
          : (isAuthentic ? 'Based on the details visible in your photos.' : 'Based on product-specific inconsistencies.');
    } else if (isAuthentic) {
      reason = '$score% confidence, based on the details visible in your photos.';
    } else if (isReplica) {
      reason = '$score% confidence, based on multiple product-specific inconsistencies.';
    } else {
      reason = report.rationale.isNotEmpty
          ? report.rationale.split('.').first
          : 'More evidence needed to determine authenticity.';
    }

    // Only real findings: never pad with generic filler text.
    final bullets = <String>[];
    if (report.quickSummaryPoints.isNotEmpty) {
      bullets.addAll(report.quickSummaryPoints.take(3));
    } else if (report.positiveFindings.isNotEmpty) {
      bullets.addAll(report.positiveFindings.take(2));
    }
    if (bullets.isEmpty && report.rationale.isNotEmpty && report.rationale.split('.').first != reason) {
      bullets.add(report.rationale);
    }
    final suspicious = report.suspiciousFindings.map((s) => s.toLowerCase()).toSet();

    final ringCenter = qualitative
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strengthWord, style: LenzText.title.copyWith(fontSize: 18, height: 1)),
              const SizedBox(height: 3),
              Text('evidence', style: LenzText.cap.copyWith(fontSize: 10.5)),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedCount(
                to: score,
                suffix: '%',
                delay: const Duration(milliseconds: 400),
                duration: const Duration(milliseconds: 1300),
                style: LenzText.title.copyWith(fontSize: 28, height: 1),
              ),
              const SizedBox(height: 3),
              Text('confidence', style: LenzText.cap.copyWith(fontSize: 10.5)),
            ],
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(v.soft.withValues(alpha: .2), LenzColors.paper),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: v.color.withValues(alpha: .13)),
        boxShadow: LenzShadows.sh1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LenzRing(
                value: ringProgress,
                size: 104,
                strokeWidth: 12,
                color: v.color,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(padding: const EdgeInsets.all(18), child: ringCenter),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quick summary', style: LenzText.item.copyWith(fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(reason, style: LenzText.sub.copyWith(fontSize: 13.5)),
                  ],
                ),
              ),
            ],
          ),
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final b in bullets) _Bullet(text: b, tone: _toneFor(b, report, suspicious), fontSize: 13.5),
          ],
        ],
      ),
    );
  }

  _Tone _toneFor(String point, AuthenticationReport report, Set<String> suspicious) {
    final p = point.toLowerCase();
    if (suspicious.contains(p) || p.startsWith('needs a closer look')) return _Tone.bad;
    if (p.startsWith('next photo') || p.contains('earlier scan') || report.limitations.any((l) => l.toLowerCase() == p)) {
      return _Tone.warn;
    }
    return _Tone.good;
  }

  // ------------------------------------------------------ assessment details
  bool _hasAssessmentDetails(AuthenticationReport report) =>
      report.imageQualityScore > 0 ||
      report.limitations.isNotEmpty ||
      report.recommendedViews.isNotEmpty ||
      (report.consistency?.note.isNotEmpty ?? false);

  /// Photo quality, analysis confidence and identification are separate
  /// questions from authenticity (§15); shown only when the report has them.
  Widget _assessmentDetailsCard(AuthenticationReport report) {
    Widget scoreTile(String label, int value) => Expanded(
          child: Column(
            children: [
              Text(value > 0 ? '$value%' : '—', style: LenzText.title.copyWith(fontSize: 19)),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: LenzText.cap.copyWith(fontSize: 11)),
            ],
          ),
        );
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Text(text, style: LenzText.item.copyWith(fontSize: 15)),
        );
    final note = report.consistency?.note ?? '';

    return LenzCard(
      radius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.imageQualityScore > 0)
            Row(
              children: [
                scoreTile('Photo quality', report.imageQualityScore),
                scoreTile('Analysis confidence', report.analysisConfidence),
                scoreTile('Item identified', report.identificationConfidence),
              ],
            ),
          if (note.isNotEmpty) ...[
            heading('Earlier scans'),
            _Bullet(text: note, tone: _Tone.good, icon: LenzIcons.refresh, fontSize: 13.5),
          ],
          if (report.limitations.isNotEmpty) ...[
            heading('Limitations'),
            for (final l in report.limitations) _Bullet(text: l, tone: _Tone.warn, icon: LenzIcons.info, fontSize: 13.5),
          ],
          if (report.recommendedViews.isNotEmpty) ...[
            heading(report.needsMoreImages ? 'More photos needed' : 'Recommended next photo'),
            for (final r in report.recommendedViews) _Bullet(text: r, tone: _Tone.good, icon: LenzIcons.camera, fontSize: 13.5),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- evidence
  Widget _evidenceSection(AuthenticationReport report) {
    // Only parts the user actually supplied a photo for.
    final list = report.evidenceItems.where((e) => e.hasPhoto || e.capturedImagePath.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Expanded(child: Text('Evidence', style: LenzText.section)),
              if (list.isNotEmpty)
                Text(
                  '${list.length} verified item${list.length == 1 ? '' : 's'}',
                  style: LenzText.cap,
                ),
            ],
          ),
        ),
        if (list.isEmpty)
          LenzCard(
            radius: 24,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            child: Text(
              'No specific part photos were provided for this scan.',
              textAlign: TextAlign.center,
              style: LenzText.sub.copyWith(fontSize: 13.5),
            ),
          )
        else
          for (final item in list) _evidenceRow(report, item),
      ],
    );
  }

  Widget _evidenceRow(AuthenticationReport report, EvidenceItem item) {
    final qualitative = report.usesQualitativeStrength;
    final itemPercent = item.score > 0
        ? item.score
        : (item.photoQualityScore > 0 ? item.photoQualityScore : report.authenticationConfidence);

    final _Tone tone = qualitative
        ? (item.status == EvidenceStatus.consistent
            ? _Tone.good
            : item.status == EvidenceStatus.suspicious
                ? _Tone.bad
                : _Tone.warn)
        : itemPercent >= 75
            ? _Tone.good
            : (itemPercent >= 45 ? _Tone.warn : _Tone.bad);
    final String badge = qualitative ? _statusWord(item.status) : '$itemPercent%';
    // Qualitative parts: how much of the photo's detail could be judged
    // clearly (measured per report), not a fixed bar.
    final double bar = qualitative
        ? (item.clarity > 0
            ? (item.clarity / 100.0).clamp(0.05, 1.0)
            : (item.status == EvidenceStatus.inconclusive ? 0.4 : 1.0))
        : (itemPercent / 100.0).clamp(0.03, 1.0);

    final img = item.displayImage;
    final statusIcon = tone == _Tone.good ? LenzIcons.check : (tone == _Tone.bad ? LenzIcons.x : LenzIcons.help);
    final iconThumb = Center(child: LenzIcon(statusIcon, size: 26, strokeWidth: 2.8, color: tone.fg));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LenzCard(
        radius: 24,
        padding: const EdgeInsets.all(12),
        onTap: () => widget.onSelectPart(item),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(color: tone.soft, borderRadius: BorderRadius.circular(18)),
                      clipBehavior: Clip.antiAlias,
                      child: img.isNotEmpty
                          ? AppImage(imagePath: img, width: 58, height: 58, fit: BoxFit.cover, placeholder: iconThumb)
                          : iconThumb,
                    ),
                  ),
                  if (img.isNotEmpty)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: tone.soft,
                          shape: BoxShape.circle,
                          border: Border.all(color: LenzColors.paper, width: 2),
                        ),
                        child: Center(child: LenzIcon(statusIcon, size: 12, strokeWidth: 3.2, color: tone.fg)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: LenzText.item),
                  const SizedBox(height: 8),
                  _ToneBar(value: bar, color: tone.fg),
                ],
              ),
            ),
            const SizedBox(width: 10),
            LenzPill(label: badge, background: tone.soft, foreground: tone.fg),
          ],
        ),
      ),
    );
  }

  Widget _actions(AuthenticationReport report) {
    final capture = widget.onCaptureMoreEvidence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (capture != null) ...[
          LenzButton(
            label: 'Capture more evidence',
            icon: LenzIcons.camera,
            variant: LenzButtonVariant.ghost,
            onPressed: capture,
          ),
          const SizedBox(height: 8),
        ],
        LenzButton(label: 'Done', onPressed: widget.onDone),
      ],
    );
  }
}

/// Prototype wording for the post-analysis part states.
String _statusWord(EvidenceStatus s) => switch (s) {
      EvidenceStatus.consistent => 'Consistent',
      EvidenceStatus.suspicious => 'Flagged',
      EvidenceStatus.inconclusive => 'Unclear',
      _ => s.label,
    };

enum _Tone {
  good(LenzColors.ok, LenzColors.okSoft, LenzIcons.check),
  bad(LenzColors.bad, LenzColors.badSoft, LenzIcons.x),
  warn(LenzColors.warn, LenzColors.warnSoft, LenzIcons.help);

  const _Tone(this.fg, this.soft, this.icon);
  final Color fg;
  final Color soft;
  final String icon;
}

/// The prototype's `.bullet` with a tinted `.d` dot.
class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.tone, this.icon, this.fontSize = 14.5});

  final String text;
  final _Tone tone;
  final String? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(color: tone.soft, shape: BoxShape.circle),
            child: Center(child: LenzIcon(icon ?? tone.icon, size: 13, strokeWidth: 3.2, color: tone.fg)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: LenzText.bullet.copyWith(fontSize: fontSize))),
        ],
      ),
    );
  }
}

/// Thin animated bar under an evidence row (clarity / legacy percentage).
class _ToneBar extends StatelessWidget {
  const _ToneBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LenzAnimatedDouble(
      value: value,
      initialValue: 0,
      duration: LenzMotion.meter,
      delay: LenzMotion.meterDelay,
      curve: LenzMotion.ease,
      builder: (context, v) => Container(
        height: 6,
        decoration: BoxDecoration(color: LenzColors.meterTrack, borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ),
    );
  }
}
