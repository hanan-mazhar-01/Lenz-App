import 'package:flutter/material.dart';
import '../auth/auth_screen.dart';
import 'first_screen_view.dart';

/// Onboarding screen displaying the first Welcome / Field Authentication Desk screen.
/// "Get Started" completes onboarding straight into Home. "Log in" pushes the
/// real sign-in screen on top so an existing user can actually authenticate,
/// and only marks onboarding complete once that screen is dismissed.
///
/// Order matters here: calling onFinish() before the push would swap the
/// app's root content to Home immediately, so the very first frame of the
/// push transition would flash Home before the sign-in screen slides in to
/// cover it. Deferring onFinish() to the pop instead means Home only ever
/// appears once the sign-in screen is already sliding away to reveal it.
class OnboardingScreen extends StatelessWidget {
  final VoidCallback onFinish;

  const OnboardingScreen({super.key, required this.onFinish});

  void _openLogin(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AuthScreen()))
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
