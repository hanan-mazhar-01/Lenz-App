import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// Prototype `sheetHead()`: an 84px Lenz bust next to the sheet title and a
/// sub line. Shared by the profile/paywall support sheets.
class LenzSheetHead extends StatelessWidget {
  const LenzSheetHead({
    super.key,
    required this.title,
    required this.subtitle,
    this.mood = LenzMood.hello,
  });

  final String title;
  final String subtitle;
  final LenzMood mood;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Transform.translate(
            offset: const Offset(0, -4),
            child: SizedBox(
              width: 84,
              child: LenzCharacter(mood: mood, view: LenzView.bust, fx: false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: LenzText.title),
                const SizedBox(height: 2),
                Text(subtitle, style: LenzText.sub.copyWith(fontSize: 13.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A paper card row with a mint icon box, bold title and muted body
/// (prototype privacy sheet rows).
class LenzInfoCard extends StatelessWidget {
  const LenzInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return LenzCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: LenzRadii.item,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: LenzColors.mint2,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: LenzIcon(icon, size: 20, color: LenzColors.forest),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: LenzText.family,
                    color: LenzColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: LenzText.sub.copyWith(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft secondary button with an "open externally" arrow, used for the
/// hosted Terms / Privacy policy links.
class LenzExternalLinkButton extends StatelessWidget {
  const LenzExternalLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return LenzButton(
      label: label,
      variant: LenzButtonVariant.soft,
      size: LenzButtonSize.sm,
      trailing: const LenzIcon(
        LenzIcons.chevR,
        size: 16,
        strokeWidth: 2.6,
        color: LenzColors.forest,
      ),
      onPressed: onPressed,
    );
  }
}

/// Infinity sign for unlimited (Pro) scans, drawn as a lemniscate: Nunito
/// has no "∞" glyph.
class LenzInfinityGlyph extends StatelessWidget {
  const LenzInfinityGlyph({
    super.key,
    this.width = 30,
    this.strokeWidth = 3.4,
    this.color = LenzColors.ink,
  });

  final double width;
  final double strokeWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Unlimited',
      child: CustomPaint(
        size: Size(width, width * .5),
        painter: _InfinityPainter(color, strokeWidth),
      ),
    );
  }
}

class _InfinityPainter extends CustomPainter {
  _InfinityPainter(this.color, this.strokeWidth);
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final a = (size.width - strokeWidth) / 2;
    final c = size.center(Offset.zero);
    final path = Path();
    for (var i = 0; i <= 120; i++) {
      final t = i / 120 * 2 * math.pi;
      final d = 1 + math.sin(t) * math.sin(t);
      final p = Offset(
        c.dx + a * math.cos(t) / d,
        c.dy + a * math.sin(t) * math.cos(t) / d * 1.25,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _InfinityPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
