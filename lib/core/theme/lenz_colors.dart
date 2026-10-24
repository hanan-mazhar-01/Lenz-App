import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Lenz design tokens, copied 1:1 from the prototype `app.css` `:root` block.
///
/// New screens must use [LenzColors], [LenzShadows], [LenzRadii],
/// [LenzGradients], `LenzText` and `LenzMotion`. The legacy `AppColors` /
/// `AppTypography` classes are remapped onto these values so screens that have
/// not been migrated yet still look coherent.
abstract final class LenzColors {
  static const Color ivory = Color(0xFFFCF8F6);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF10241C);
  static const Color forest = Color(0xFF122F24);
  static const Color forest2 = Color(0xFF1D4C3A);
  static const Color mint = Color(0xFFD6E8DE);
  static const Color mint2 = Color(0xFFEAF4EE);
  static const Color leaf = Color(0xFF2EA44F);
  static const Color gold = Color(0xFFD4AF37);
  static const Color gold2 = Color(0xFFF4D97B);
  static const Color muted = Color(0xFF66716B);

  /// `rgba(18,47,36,.09)` hairline used for every card / chip border.
  static const Color line = Color.fromRGBO(18, 47, 36, .09);

  static const Color ok = Color(0xFF1F8A4C);
  static const Color okSoft = Color(0xFFDDF1E4);
  static const Color bad = Color(0xFFC23B3B);
  static const Color badSoft = Color(0xFFFBE0DC);
  static const Color warn = Color(0xFFB9741A);
  static const Color warnSoft = Color(0xFFFBEBC1);

  // ---- values that appear inline in app.css ----------------------------
  /// Inactive tab / field icon colour (`#8B948F`).
  static const Color subtle = Color(0xFF8B948F);

  /// Input placeholder (`#9AA39E`).
  static const Color placeholder = Color(0xFF9AA39E);

  /// Switch track when off (`#CBD3CE`).
  static const Color switchOff = Color(0xFFCBD3CE);

  /// Gold button label (`#3a2c05`).
  static const Color goldInk = Color(0xFF3A2C05);

  /// Light grey-green text on dark screens (`#9DB5A8`).
  static const Color onDarkMuted = Color(0xFF9DB5A8);

  /// Hero sub text (`#C5D8CD`).
  static const Color onHeroMuted = Color(0xFFC5D8CD);

  /// Camera screen background.
  static const Color camera = Color(0xFF0A110E);

  /// Journey / seg track tints.
  static const Color trackTint = Color.fromRGBO(18, 47, 36, .12);
  static const Color segTrack = Color.fromRGBO(18, 47, 36, .07);
  static const Color meterTrack = Color.fromRGBO(18, 47, 36, .08);
  static const Color ringTrack = Color.fromRGBO(18, 47, 36, .10);
  static const Color grabber = Color.fromRGBO(18, 47, 36, .18);
  static const Color checkBorder = Color.fromRGBO(18, 47, 36, .20);
  static const Color dotBorder = Color.fromRGBO(18, 47, 36, .14);

  /// Sheet scrim `rgba(10,20,15,.45)`.
  static const Color scrim = Color.fromRGBO(10, 20, 15, .45);

  /// Focus ring of fields (`rgba(46,164,79,.16)`).
  static const Color focusRing = Color.fromRGBO(46, 164, 79, .16);

  /// Pulse ring of buttons (`rgba(46,164,79,.55)`) and the FAB (`.5`).
  static const Color pulseRing = Color.fromRGBO(46, 164, 79, .55);

  /// Tab bar border `rgba(18,47,36,.08)`.
  static const Color tabBarBorder = Color.fromRGBO(18, 47, 36, .08);

  /// Amber meter fill used for "blurry"/warning measurements.
  static const Color meterWarnA = Color(0xFFE39A2D);
  static const Color meterWarnB = Color(0xFFF2C36B);
}

/// Box shadows (`--sh1`, `--sh2` and the inline shadows of components).
abstract final class LenzShadows {
  /// `0 1px 2px rgba(18,47,36,.05), 0 8px 24px -10px rgba(18,47,36,.16)`
  static const List<BoxShadow> sh1 = [
    BoxShadow(
      color: Color.fromRGBO(18, 47, 36, .05),
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
    BoxShadow(
      color: Color.fromRGBO(18, 47, 36, .16),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -10,
    ),
  ];

  /// `0 2px 4px rgba(18,47,36,.06), 0 18px 40px -14px rgba(18,47,36,.28)`
  static const List<BoxShadow> sh2 = [
    BoxShadow(
      color: Color.fromRGBO(18, 47, 36, .06),
      offset: Offset(0, 2),
      blurRadius: 4,
    ),
    BoxShadow(
      color: Color.fromRGBO(18, 47, 36, .28),
      offset: Offset(0, 18),
      blurRadius: 40,
      spreadRadius: -14,
    ),
  ];

  /// Primary button: `0 14px 26px -10px rgba(18,47,36,.7)`.
  static const List<BoxShadow> button = [
    BoxShadow(
      color: Color.fromRGBO(18, 47, 36, .7),
      offset: Offset(0, 14),
      blurRadius: 26,
      spreadRadius: -10,
    ),
  ];

  /// Gold button: `0 14px 26px -10px rgba(212,175,55,.75)`.
  static const List<BoxShadow> buttonGold = [
    BoxShadow(
      color: Color.fromRGBO(212, 175, 55, .75),
      offset: Offset(0, 14),
      blurRadius: 26,
      spreadRadius: -10,
    ),
  ];

  /// Hero card: `0 26px 50px -20px rgba(18,47,36,.7)`.
  static const List<BoxShadow> hero = [
    BoxShadow(
      color: Color.fromRGBO(18, 47, 36, .7),
      offset: Offset(0, 26),
      blurRadius: 50,
      spreadRadius: -20,
    ),
  ];

  /// Floating tab bar: `0 18px 40px -14px rgba(18,47,36,.4)`.
  static const List<BoxShadow> tabBar = [
    BoxShadow(
      color: Color.fromRGBO(18, 47, 36, .4),
      offset: Offset(0, 18),
      blurRadius: 40,
      spreadRadius: -14,
    ),
  ];

  /// Raised centre FAB: ivory ring + `0 16px 30px -8px rgba(18,47,36,.75)`.
  static const List<BoxShadow> fab = [
    BoxShadow(color: LenzColors.ivory, spreadRadius: 6),
    BoxShadow(
      color: Color.fromRGBO(18, 47, 36, .75),
      offset: Offset(0, 16),
      blurRadius: 30,
      spreadRadius: -8,
    ),
  ];

  /// Journey rider: `0 8px 18px -6px rgba(18,47,36,.5)`.
  static const List<BoxShadow> rider = [
    BoxShadow(
      color: Color.fromRGBO(18, 47, 36, .5),
      offset: Offset(0, 8),
      blurRadius: 18,
      spreadRadius: -6,
    ),
  ];

  /// Bottom sheet: `0 -20px 60px rgba(0,0,0,.25)`.
  static const List<BoxShadow> sheet = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, .25),
      offset: Offset(0, -20),
      blurRadius: 60,
    ),
  ];

  /// Switch thumb: `0 2px 6px rgba(0,0,0,.25)`.
  static const List<BoxShadow> thumb = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, .25),
      offset: Offset(0, 2),
      blurRadius: 6,
    ),
  ];
}

/// Corner radii used by the prototype.
abstract final class LenzRadii {
  static const double card = 26;
  static const double item = 24;
  static const double stat = 22;
  static const double hero = 34;
  static const double verdictHero = 36;
  static const double sheet = 34;
  static const double button = 20;
  static const double buttonSm = 16;
  static const double field = 20;
  static const double iconButton = 16;
  static const double tabBar = 30;
  static const double segTrack = 20;
  static const double segThumb = 15;
  static const double check = 9;
  static const double pill = 999;

  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get buttonRadius => BorderRadius.circular(button);
  static const BorderRadius sheetRadius =
      BorderRadius.vertical(top: Radius.circular(sheet));
}

/// Gradients of the prototype. [css] reproduces CSS `linear-gradient(<deg>, ...)`
/// including its aspect-ratio dependent gradient line.
abstract final class LenzGradients {
  /// Primary button `linear-gradient(180deg,#1F5240 0%,#112B21 100%)`.
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1F5240), Color(0xFF112B21)],
  );

  /// Gold `linear-gradient(180deg,#F6DE86,#D4AF37)`.
  static const LinearGradient gold = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF6DE86), Color(0xFFD4AF37)],
  );

  /// White hero button `linear-gradient(180deg,#fff,#E7F2EB)`.
  static const LinearGradient light = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFE7F2EB)],
  );

  /// Centre FAB `linear-gradient(180deg,#256148,#102A20)`.
  static const LinearGradient fab = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF256148), Color(0xFF102A20)],
  );

  /// Journey fill `linear-gradient(90deg,#2EA44F,#7BD389)`.
  static const LinearGradient journeyFill = LinearGradient(
    colors: [Color(0xFF2EA44F), Color(0xFF7BD389)],
  );

  /// Meter fill `linear-gradient(90deg,#2EA44F,#74D28A)`.
  static const LinearGradient meter = LinearGradient(
    colors: [Color(0xFF2EA44F), Color(0xFF74D28A)],
  );

  /// Amber meter fill `linear-gradient(90deg,#E39A2D,#F2C36B)`.
  static const LinearGradient meterWarn = LinearGradient(
    colors: [LenzColors.meterWarnA, LenzColors.meterWarnB],
  );

  /// Hero card `linear-gradient(155deg,#1E5340 0%,#112C21 70%)`.
  static final LinearGradient hero = css(
    155,
    const [Color(0xFF1E5340), Color(0xFF112C21)],
    const [0, .7],
  );

  /// Pro promo strip `linear-gradient(120deg,#14241B,#25402F)`.
  static final LinearGradient promo = css(
    120,
    const [Color(0xFF14241B), Color(0xFF25402F)],
  );

  /// CSS `linear-gradient(<angleDeg>, colors...)`: 0deg points up, 90deg right,
  /// 180deg down; the gradient line is stretched so that the corners get the
  /// first/last colour exactly like in a browser.
  static LinearGradient css(
    double angleDeg,
    List<Color> colors, [
    List<double>? stops,
  ]) {
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: colors,
      stops: stops,
      transform: _CssAngleTransform(angleDeg),
    );
  }
}

class _CssAngleTransform extends GradientTransform {
  const _CssAngleTransform(this.deg);
  final double deg;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final a = deg * math.pi / 180;
    final dx = math.sin(a);
    final dy = -math.cos(a);
    final length = (bounds.width * dx).abs() + (bounds.height * dy).abs();
    final scale = bounds.width == 0 ? 1.0 : length / bounds.width;
    final c = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..rotateZ(math.atan2(dy, dx))
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }
}
