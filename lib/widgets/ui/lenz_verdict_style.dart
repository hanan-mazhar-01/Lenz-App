import 'package:flutter/painting.dart';

import '../../core/theme/lenz_colors.dart';
import '../../models/authentication_result.dart';
import 'lenz_icons.dart';

/// Pill / hero variants that map onto a verdict.
enum LenzVerdictKind { auth, fake, unsure }

/// Colours, copy and icon of a verdict (the prototype's `V` table), bound to
/// the app's [Verdict] enum.
///
/// Labels are always `Appears Authentic` / `Likely Replica` /
/// `Unable to Verify` (short: `Authentic` / `Replica` / `Not sure`).
class LenzVerdictStyle {
  const LenzVerdictStyle._({
    required this.kind,
    required this.label,
    required this.short,
    required this.color,
    required this.soft,
    required this.bg,
    required this.icon,
    required this.mood,
  });

  final LenzVerdictKind kind;
  final String label;
  final String short;

  /// Text / ring colour (`V.color`).
  final Color color;

  /// Pill / badge fill (`V.soft`).
  final Color soft;

  /// Mood tint of the screen blob and verdict hero (`V.bg`).
  final Color bg;

  /// Icon name for [LenzIcon].
  final String icon;

  /// Name of the Lenz character mood the prototype uses for this verdict
  /// (`happy` / `shocked` / `unsure`).
  final String mood;

  static const LenzVerdictStyle auth = LenzVerdictStyle._(
    kind: LenzVerdictKind.auth,
    label: 'Appears Authentic',
    short: 'Authentic',
    color: LenzColors.ok,
    soft: LenzColors.okSoft,
    bg: Color(0xFFCDEFD3),
    icon: LenzIcons.shieldOk,
    mood: 'happy',
  );

  static const LenzVerdictStyle fake = LenzVerdictStyle._(
    kind: LenzVerdictKind.fake,
    label: 'Likely Replica',
    short: 'Replica',
    color: LenzColors.bad,
    soft: LenzColors.badSoft,
    bg: Color(0xFFF8D6CF),
    icon: LenzIcons.warn,
    mood: 'shocked',
  );

  static const LenzVerdictStyle unsure = LenzVerdictStyle._(
    kind: LenzVerdictKind.unsure,
    label: 'Unable to Verify',
    short: 'Not sure',
    color: LenzColors.warn,
    soft: LenzColors.warnSoft,
    bg: Color(0xFFFBEBC1),
    icon: LenzIcons.help,
    mood: 'unsure',
  );

  /// Style for the app's [Verdict].
  static LenzVerdictStyle of(Verdict verdict) => switch (verdict) {
        Verdict.likelyAuthentic => auth,
        Verdict.likelyReplica => fake,
        Verdict.inconclusive => unsure,
      };

  /// Style for a nullable verdict (e.g. a report that is still loading):
  /// falls back to [unsure].
  static LenzVerdictStyle ofOrUnsure(Verdict? verdict) =>
      verdict == null ? unsure : of(verdict);
}
