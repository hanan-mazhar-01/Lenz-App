import 'package:flutter/material.dart';
import '../../models/evidence.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// One evidence part of a report (prototype `SCREENS.part`): the user's photo
/// (tap to zoom), the part's status with Lenz reacting, and the engine's
/// real observations / flagged / consistent signals and inspection guide.
class PartDetailView extends StatelessWidget {
  final EvidenceItem item;
  final VoidCallback onBack;

  const PartDetailView({
    super.key,
    required this.item,
    required this.onBack,
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
              icon: const LenzIcon(LenzIcons.x, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              title,
              style: LenzText.item.copyWith(color: Colors.white, fontSize: 16),
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
    // Same status rule as before the redesign: suspicious or a low legacy
    // score is "flagged"; consistent is good; everything else is unclear.
    final isLowScore = item.status == EvidenceStatus.suspicious || (item.score > 0 && item.score < 60);
    final isGood = !isLowScore &&
        (item.status == EvidenceStatus.consistent ||
            item.status == EvidenceStatus.completed ||
            item.status == EvidenceStatus.captured ||
            item.score >= 60);
    final noPhoto = !item.hasPhoto && item.displayImage.isEmpty;
    final _PartTone tone = isLowScore
        ? _PartTone.bad
        : isGood
            ? _PartTone.good
            : (noPhoto ? _PartTone.miss : _PartTone.warn);
    final displayImg = item.displayImage;
    final pad = MediaQuery.paddingOf(context);
    final hint = item.reason.isNotEmpty ? item.reason : item.guide;
    final compact = MediaQuery.sizeOf(context).width < 360;
    final ringSize = compact ? 68.0 : 84.0;

    final children = <Widget>[
      // Photo card with "Tap to zoom".
      LenzCard(
        radius: 32,
        padding: const EdgeInsets.all(12),
        onTap: displayImg.isNotEmpty ? () => _openFullScreenImage(context, displayImg, item.title) : null,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const RadialGradient(
              center: Alignment(0, -.2),
              radius: .75,
              colors: [Color(0xFF3B5F50), Color(0xFF14221C)],
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (displayImg.isNotEmpty)
                AppImage(
                  imagePath: displayImg,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.contain,
                  placeholder: const Center(child: LenzIcon(LenzIcons.image, size: 44, color: Color(0x99FFFFFF))),
                )
              else
                const Center(child: LenzIcon(LenzIcons.image, size: 44, color: Color(0x99FFFFFF))),
              if (displayImg.isNotEmpty)
                const Positioned(
                  left: 12,
                  bottom: 12,
                  child: LenzPill(label: 'Tap to zoom', icon: LenzIcons.search, iconStrokeWidth: 2.6),
                ),
            ],
          ),
        ),
      ),
      // Status row: ring + pill + hint + Lenz.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            SizedBox.square(
              dimension: ringSize,
              child: tone == _PartTone.miss
                  ? const Center(child: Text('-', style: LenzText.title))
                  : LenzRing(
                      // Legacy parts carry a score; engine v3 parts don't, so
                      // the ring fills to the measured clarity (or full) and
                      // shows the status icon instead of a number.
                      value: item.score > 0
                          ? item.score / 100
                          : (item.clarity > 0 ? item.clarity / 100 : (tone == _PartTone.warn ? .4 : 1)),
                      size: ringSize,
                      strokeWidth: compact ? 8 : 10,
                      color: tone.fg,
                      child: item.score > 0
                          ? Text('${item.score}%', style: LenzText.title.copyWith(fontSize: 22))
                          : LenzIcon(tone.icon, size: 30, strokeWidth: 3, color: tone.fg),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LenzPill(label: _statusWord(item.status), background: tone.soft, foreground: tone.fg),
                  if (hint.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(hint, maxLines: 3, overflow: TextOverflow.ellipsis, style: LenzText.sub),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: compact ? 64 : 96,
              child: LenzCharacter(mood: tone.mood, view: LenzView.bust, fx: false),
            ),
          ],
        ),
      ),
      if (item.inconsistentSignals.isNotEmpty)
        _ListCard(
          icon: LenzIcons.warn,
          title: 'Inconsistencies flagged',
          lines: item.inconsistentSignals,
          tone: _PartTone.bad,
        ),
      if (item.consistentSignals.isNotEmpty)
        _ListCard(
          icon: LenzIcons.shieldOk,
          title: 'Consistent manufacturing signals',
          lines: item.consistentSignals,
          tone: _PartTone.good,
        ),
      if (item.observations.isNotEmpty)
        _ListCard(
          icon: LenzIcons.eye,
          title: 'Visual observations',
          lines: item.observations,
          tone: _PartTone.neutral,
        ),
      if (item.guide.isNotEmpty)
        _ListCard(
          title: 'Inspection criteria',
          lines: [item.guide],
          tone: _PartTone.good,
          bulletIcon: LenzIcons.layers,
        ),
    ];

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LenzBlob(color: tone.blob),
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, pad.top + 14, 20, 40 + pad.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                LenzTopBar(title: item.title, onBack: onBack),
                LenzStagger(spacing: 14, children: children),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _statusWord(EvidenceStatus s) => switch (s) {
      EvidenceStatus.consistent => 'Consistent',
      EvidenceStatus.suspicious => 'Flagged',
      EvidenceStatus.inconclusive => 'Unclear',
      _ => s.label,
    };

enum _PartTone {
  good(LenzColors.ok, LenzColors.okSoft, LenzIcons.check, LenzMood.pleased, Color(0xFFCFEED6)),
  bad(LenzColors.bad, LenzColors.badSoft, LenzIcons.x, LenzMood.shocked, Color(0xFFF8D6CF)),
  warn(LenzColors.warn, LenzColors.warnSoft, LenzIcons.help, LenzMood.unsure, Color(0xFFFBEBC1)),
  miss(LenzColors.warn, LenzColors.warnSoft, LenzIcons.help, LenzMood.sorry, Color(0xFFFBEBC1)),
  neutral(LenzColors.forest, LenzColors.mint2, LenzIcons.eye, LenzMood.idle, LenzColors.mint);

  const _PartTone(this.fg, this.soft, this.icon, this.mood, this.blob);
  final Color fg;
  final Color soft;
  final String icon;
  final LenzMood mood;
  final Color blob;
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.lines,
    required this.tone,
    this.icon,
    this.bulletIcon,
  });

  final String? icon;
  final String title;
  final List<String> lines;
  final _PartTone tone;
  final String? bulletIcon;

  @override
  Widget build(BuildContext context) {
    return LenzCard(
      radius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                LenzIcon(icon!, size: 20, color: LenzColors.ink),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(title, style: LenzText.item.copyWith(fontSize: 16.5))),
            ],
          ),
          const SizedBox(height: 6),
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
                    decoration: BoxDecoration(color: tone.soft, shape: BoxShape.circle),
                    child: Center(
                      child: LenzIcon(
                        bulletIcon ?? tone.icon,
                        size: bulletIcon != null ? 12 : 13,
                        strokeWidth: bulletIcon != null ? 2.6 : 3.2,
                        color: tone.fg,
                      ),
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
