import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../core/theme/lenz_text.dart';
import 'lenz_button.dart';

/// Shows a Lenz bottom sheet (prototype `openSheet()`): ivory surface with a
/// 34px top radius, 44x5 grabber, scrim `rgba(10,20,15,.45)` + 3px backdrop
/// blur, slide up in 520ms `cubic-bezier(.2,.9,.2,1)` and down in 380ms
/// `cubic-bezier(.5,0,.8,.4)`. Drag the sheet down or tap the scrim to dismiss.
///
/// [builder] builds the content *inside* the frame (grabber, padding, max
/// height 88% and scrolling are provided). Close it with
/// `Navigator.of(context).pop(result)`.
Future<T?> showLenzSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
  bool framed = true,
  double maxHeightFactor = .88,
  EdgeInsetsGeometry? padding,
  String? barrierLabel,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push(
    _LenzSheetRoute<T>(
      builder: framed
          ? (context) => LenzSheetFrame(
                maxHeightFactor: maxHeightFactor,
                padding: padding,
                child: builder(context),
              )
          : builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel:
          barrierLabel ?? MaterialLocalizations.of(context).scrimLabel,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
    ),
  );
}

class _LenzSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _LenzSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.isDismissible,
    super.enableDrag,
  }) : super(
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          clipBehavior: Clip.none,
          showDragHandle: false,
          modalBarrierColor: LenzColors.scrim,
          sheetAnimationStyle: AnimationStyle(
            duration: LenzMotion.sheetIn520,
            curve: LenzMotion.sheetIn,
            reverseDuration: LenzMotion.sheetOut380,
            reverseCurve: LenzMotion.sheetOut.flipped,
          ),
        );

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    final anim = animation;
    if (anim == null) return barrier;
    return AnimatedBuilder(
      animation: anim,
      child: barrier,
      builder: (context, child) {
        final t = anim.value.clamp(0.0, 1.0);
        if (t <= 0) return child!;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3 * t, sigmaY: 3 * t),
          child: child,
        );
      },
    );
  }
}

/// The visual frame of a Lenz sheet: ivory, radius 34 at the top, soft upward
/// shadow, grabber, padding `12 20 26+safe-area`, scrolls when taller than
/// [maxHeightFactor] of the screen and lifts above the keyboard.
class LenzSheetFrame extends StatelessWidget {
  const LenzSheetFrame({
    super.key,
    required this.child,
    this.maxHeightFactor = .88,
    this.padding,
    this.showGrabber = true,
  });

  final Widget child;
  final double maxHeightFactor;

  /// Overrides the default `EdgeInsets.fromLTRB(20, 12, 20, 26 + safe area)`.
  final EdgeInsetsGeometry? padding;
  final bool showGrabber;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final maxHeight = ((mq.size.height - keyboard) * maxHeightFactor)
        .clamp(120.0, mq.size.height);
    final inner = padding ??
        EdgeInsets.fromLTRB(20, 12, 20, 26 + mq.padding.bottom);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: LenzColors.ivory,
            borderRadius: LenzRadii.sheetRadius,
            boxShadow: LenzShadows.sheet,
          ),
          child: ClipRRect(
            borderRadius: LenzRadii.sheetRadius,
            child: Padding(
              padding: inner,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showGrabber) ...[
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: LenzColors.grabber,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirmation sheet (prototype `confirmSheet()`): optional Lenz [character]
/// on top (150px wide), title, text, an ok button (primary or danger) and a
/// ghost Cancel. Resolves to `true` when confirmed.
///
/// [character] is a slot for the Lenz character widget, e.g.
/// `(context) => LenzCharacter(mood: LenzMood.unsure, view: LenzView.bust)`.
Future<bool> showLenzConfirm(
  BuildContext context, {
  required String title,
  required String text,
  String okLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool danger = false,
  WidgetBuilder? character,
  VoidCallback? onOk,
}) async {
  final ok = await showLenzSheet<bool>(
    context,
    builder: (context) => LenzConfirmContent(
      title: title,
      text: text,
      okLabel: okLabel,
      cancelLabel: cancelLabel,
      danger: danger,
      character: character,
    ),
  );
  if (ok == true) onOk?.call();
  return ok == true;
}

/// Body of [showLenzConfirm]; public so it can be previewed in the gallery.
class LenzConfirmContent extends StatelessWidget {
  const LenzConfirmContent({
    super.key,
    required this.title,
    required this.text,
    this.okLabel = 'OK',
    this.cancelLabel = 'Cancel',
    this.danger = false,
    this.character,
    this.onOk,
    this.onCancel,
  });

  final String title;
  final String text;
  final String okLabel;
  final String cancelLabel;
  final bool danger;
  final WidgetBuilder? character;
  final VoidCallback? onOk;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (character != null) ...[
          Transform.translate(
            offset: const Offset(0, -6),
            child: SizedBox(width: 150, child: character!(context)),
          ),
        ],
        const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: LenzText.title),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Text(text, textAlign: TextAlign.center, style: LenzText.sub),
        ),
        const SizedBox(height: 14),
        LenzButton(
          label: okLabel,
          variant: danger ? LenzButtonVariant.danger : LenzButtonVariant.primary,
          onPressed: onOk ?? () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 8),
        LenzButton(
          label: cancelLabel,
          variant: LenzButtonVariant.ghost,
          onPressed: onCancel ?? () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
