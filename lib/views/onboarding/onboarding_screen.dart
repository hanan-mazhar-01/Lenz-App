import 'package:flutter/material.dart';
import '../../widgets/ui/ui.dart';
import '../auth/auth_screen.dart';
import 'first_screen_view.dart';

/// Onboarding: the 3-page Lenz welcome carousel (FirstScreenView).
/// "Get started" completes onboarding (the app root then shows the auth
/// screen). "Skip" / "I already have an account" push the real sign-in screen
/// on top so an existing user can actually authenticate, and only mark
/// onboarding complete once that screen is dismissed.
///
/// Order matters here: calling onFinish() before the push would swap the
/// app's root content immediately, so the very first frame of the push
/// transition would flash the next root screen before the sign-in screen
/// slides in to cover it. Deferring onFinish() to the pop instead means it
/// only appears once the sign-in screen is already sliding away to reveal it.
class OnboardingScreen extends StatelessWidget {
  final VoidCallback onFinish;

  const OnboardingScreen({super.key, required this.onFinish});

  void _openLogin(BuildContext context) {
    Navigator.of(context)
        .push(LenzRoutes.forward(const AuthScreen()))
        .then((_) => onFinish());
  }

  @override
  Widget build(BuildContext context) {
    return FirstScreenView(
      onGetStarted: onFinish,
      onSkip: () => _openLogin(context),
      onBack: () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
    );
  }
}
