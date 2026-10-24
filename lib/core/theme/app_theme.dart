import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lenz_colors.dart';
import 'lenz_page_transitions.dart';
import 'lenz_text.dart';

/// The Lenz Material 3 theme: light only, Nunito, ivory canvas, forest primary.
abstract final class AppTheme {
  static const ColorScheme _scheme = ColorScheme(
    brightness: Brightness.light,
    primary: LenzColors.forest,
    onPrimary: Colors.white,
    primaryContainer: LenzColors.mint,
    onPrimaryContainer: LenzColors.forest,
    secondary: LenzColors.forest2,
    onSecondary: Colors.white,
    secondaryContainer: LenzColors.mint2,
    onSecondaryContainer: LenzColors.forest,
    tertiary: LenzColors.gold,
    onTertiary: LenzColors.goldInk,
    tertiaryContainer: LenzColors.warnSoft,
    onTertiaryContainer: LenzColors.goldInk,
    error: LenzColors.bad,
    onError: Colors.white,
    errorContainer: LenzColors.badSoft,
    onErrorContainer: LenzColors.bad,
    surface: LenzColors.ivory,
    onSurface: LenzColors.ink,
    onSurfaceVariant: LenzColors.muted,
    surfaceDim: Color(0xFFF2EEEC),
    surfaceBright: LenzColors.paper,
    surfaceContainerLowest: LenzColors.paper,
    surfaceContainerLow: LenzColors.paper,
    surfaceContainer: LenzColors.paper,
    surfaceContainerHigh: LenzColors.mint2,
    surfaceContainerHighest: LenzColors.mint2,
    outline: LenzColors.subtle,
    outlineVariant: LenzColors.line,
    shadow: LenzColors.forest,
    scrim: LenzColors.scrim,
    inverseSurface: LenzColors.forest,
    onInverseSurface: Colors.white,
    inversePrimary: LenzColors.mint,
    surfaceTint: Colors.transparent,
  );

  static TextTheme get _textTheme => TextTheme(
        displayLarge: LenzText.display.copyWith(fontSize: 38),
        displayMedium: LenzText.display.copyWith(fontSize: 34),
        displaySmall: LenzText.display,
        headlineLarge: LenzText.hero.copyWith(color: LenzColors.ink, fontSize: 28),
        headlineMedium: LenzText.hero.copyWith(color: LenzColors.ink),
        headlineSmall: LenzText.title,
        titleLarge: LenzText.section,
        titleMedium: LenzText.item.copyWith(fontSize: 16),
        titleSmall: LenzText.item.copyWith(fontSize: 14.5),
        bodyLarge: LenzText.setting,
        bodyMedium: LenzText.sub,
        bodySmall: LenzText.itemSub,
        labelLarge: LenzText.button.copyWith(color: LenzColors.ink),
        labelMedium: LenzText.chip,
        labelSmall: LenzText.tab,
      );

  static ThemeData get lightTheme {
    final textTheme = _textTheme;
    const radius20 = BorderRadius.all(Radius.circular(LenzRadii.field));
    OutlineInputBorder border(Color color, [double width = 1.5]) =>
        OutlineInputBorder(
          borderRadius: radius20,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: _scheme,
      fontFamily: LenzText.family,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: LenzColors.ivory,
      canvasColor: LenzColors.ivory,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconTheme: const IconThemeData(color: LenzColors.ink, size: 22),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: LenzPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: LenzPageTransitionsBuilder(),
          TargetPlatform.linux: LenzPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: LenzPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: LenzText.section,
        iconTheme: const IconThemeData(color: LenzColors.ink, size: 22),
      ),
      cardTheme: CardThemeData(
        color: LenzColors.paper,
        surfaceTintColor: Colors.transparent,
        shadowColor: LenzColors.forest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: LenzRadii.cardRadius,
          side: const BorderSide(color: LenzColors.line),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: LenzColors.line,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: LenzColors.paper,
        selectedColor: LenzColors.forest,
        disabledColor: LenzColors.mint2,
        side: const BorderSide(color: LenzColors.line),
        shape: const StadiumBorder(),
        labelStyle: LenzText.chip,
        secondaryLabelStyle: LenzText.chip.copyWith(color: Colors.white),
        checkmarkColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LenzColors.paper,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: LenzText.placeholder,
        labelStyle: LenzText.placeholder,
        floatingLabelStyle: LenzText.cap.copyWith(color: LenzColors.forest2),
        errorStyle: LenzText.cap.copyWith(color: LenzColors.bad),
        prefixIconColor: LenzColors.subtle,
        suffixIconColor: LenzColors.subtle,
        border: border(LenzColors.line),
        enabledBorder: border(LenzColors.line),
        disabledBorder: border(LenzColors.line),
        focusedBorder: border(LenzColors.forest2),
        errorBorder: border(LenzColors.bad),
        focusedErrorBorder: border(LenzColors.bad),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: LenzColors.forest2,
        selectionColor: LenzColors.leaf.withValues(alpha: .25),
        selectionHandleColor: LenzColors.leaf,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _filled()),
      filledButtonTheme: FilledButtonThemeData(style: _filled()),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _filled().copyWith(
          backgroundColor: const WidgetStatePropertyAll(LenzColors.paper),
          foregroundColor: const WidgetStatePropertyAll(LenzColors.ink),
          side: const WidgetStatePropertyAll(
            BorderSide(color: LenzColors.line),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: LenzColors.forest2,
          textStyle: LenzText.link,
          splashFactory: NoSplash.splashFactory,
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: LenzColors.ink,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: LenzColors.forest,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: CircleBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: LenzColors.ivory,
        modalBackgroundColor: LenzColors.ivory,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: LenzRadii.sheetRadius),
        dragHandleColor: LenzColors.grabber,
        dragHandleSize: Size(44, 5),
        modalBarrierColor: LenzColors.scrim,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: LenzColors.ivory,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: LenzColors.line),
        ),
        titleTextStyle: LenzText.title,
        contentTextStyle: LenzText.sub,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: LenzColors.forest,
        contentTextStyle: LenzText.toast,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? LenzColors.leaf
              : LenzColors.switchOff,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LenzRadii.check),
        ),
        side: const BorderSide(color: LenzColors.checkBorder, width: 2),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? LenzColors.leaf
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? LenzColors.leaf
              : LenzColors.checkBorder,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: LenzColors.leaf,
        linearTrackColor: LenzColors.meterTrack,
        circularTrackColor: LenzColors.ringTrack,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: LenzColors.forest,
        textColor: LenzColors.ink,
        titleTextStyle: LenzText.setting,
        subtitleTextStyle: LenzText.settingSub,
        shape: RoundedRectangleBorder(borderRadius: LenzRadii.cardRadius),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: LenzColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: LenzColors.forest.withValues(alpha: .3),
        textStyle: LenzText.setting,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: LenzColors.line),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: LenzColors.forest,
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: LenzText.toast.copyWith(fontSize: 12.5),
      ),
    );
  }

  /// The app is light-only; kept for API compatibility with older callers.
  static ThemeData get darkTheme => lightTheme;

  static ButtonStyle _filled() => ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(64, 58)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? LenzColors.forest.withValues(alpha: .45)
              : LenzColors.forest,
        ),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        textStyle: const WidgetStatePropertyAll(LenzText.button),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: LenzRadii.buttonRadius),
        ),
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      );
}
