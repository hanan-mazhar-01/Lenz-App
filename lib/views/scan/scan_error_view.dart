import 'package:flutter/material.dart';

import '../../core/errors/app_error.dart';
import '../../services/haptics.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// Scan failure screen (prototype `SCREENS.error`). Title, message and the
/// recovery hint come from the real [AppError]; Lenz's mood and the icon
/// follow the error type.
class ScanErrorView extends StatelessWidget {
  final String errorMessage;
  final AppError? appError;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const ScanErrorView({
    super.key,
    required this.errorMessage,
    this.appError,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveError = appError ?? AppError.fromException(errorMessage);

    final (
      String icon,
      Color iconColor,
      LenzMood mood,
      String kind,
    ) = switch (effectiveError.type) {
      AppErrorType.noInternet => (
        LenzIcons.cloud,
        LenzColors.warn,
        LenzMood.sorry,
        'Network error',
      ),
      AppErrorType.serviceUnreachable => (
        LenzIcons.cloud,
        LenzColors.warn,
        LenzMood.sorry,
        'Service unreachable',
      ),
      AppErrorType.timeout => (LenzIcons.clock, LenzColors.warn, LenzMood.sorry, 'Timed out'),
      AppErrorType.quotaLimit => (
        LenzIcons.clock,
        LenzColors.warn,
        LenzMood.unsure,
        'Busy right now',
      ),
      AppErrorType.aiBillingUnavailable => (
        LenzIcons.clock,
        LenzColors.warn,
        LenzMood.unsure,
        'Temporarily unavailable',
      ),
      AppErrorType.apiUnauthorized => (
        LenzIcons.lock,
        LenzColors.bad,
        LenzMood.shocked,
        'Access problem',
      ),
      AppErrorType.serverError => (LenzIcons.warn, LenzColors.bad, LenzMood.sorry, 'Server error'),
      AppErrorType.invalidResponse => (
        LenzIcons.help,
        LenzColors.warn,
        LenzMood.unsure,
        'Unreadable result',
      ),
      AppErrorType.cameraError => (
        LenzIcons.camera,
        LenzColors.bad,
        LenzMood.sorry,
        'Camera error',
      ),
      AppErrorType.unknownError => (
        LenzIcons.warn,
        LenzColors.warn,
        LenzMood.shocked,
        'Unexpected error',
      ),
    };
    final pad = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LenzBlob(color: Color(0xFFE9E4DE)),
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, pad.top + 14, 20, 30 + pad.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                LenzTopBar(title: 'Something went wrong', onBack: onCancel),
                const SizedBox(height: 6),
                LenzStagger(
                  spacing: 10,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, 6),
                      child: SizedBox(width: 250, child: LenzCharacter(mood: mood)),
                    ),
                    Text(
                      effectiveError.title,
                      textAlign: TextAlign.center,
                      style: LenzText.display.copyWith(fontSize: 28),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        effectiveError.message,
                        textAlign: TextAlign.center,
                        style: LenzText.sub,
                      ),
                    ),
                    LenzCard(
                      radius: 24,
                      width: double.infinity,
                      child: Row(
                        children: [
                          LenzIcon(icon, size: 22, color: iconColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(kind, style: LenzText.item.copyWith(fontSize: 15)),
                                if (effectiveError.recoveryAction != null)
                                  Text(
                                    effectiveError.recoveryAction!,
                                    style: LenzText.sub.copyWith(fontSize: 12.5),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    LenzButton(
                      label: 'Try again',
                      icon: LenzIcons.refresh,
                      onPressed: () {
                        Haptics.mediumImpact();
                        onRetry();
                      },
                    ),
                    LenzButton(
                      label: 'Cancel and return home',
                      variant: LenzButtonVariant.ghost,
                      onPressed: () {
                        Haptics.lightImpact();
                        onCancel();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
