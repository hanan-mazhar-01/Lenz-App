import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/haptics.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/common/google_icon.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

const int _guestScanAllowance = 3;

/// "Create an account to keep scanning" (prototype `SCREENS.guest`): shown
/// when a guest has used their free scans. Slides up as a full-screen modal.
class GuestPaywallScreen extends StatefulWidget {
  final VoidCallback? onDismiss;

  /// Overrides `Platform.isIOS` for the Apple button (previews/tests only).
  final bool? showAppleOverride;

  const GuestPaywallScreen({super.key, this.onDismiss, this.showAppleOverride});

  static Future<bool?> show(BuildContext context) {
    Haptics.mediumImpact();
    return Navigator.of(context).push<bool>(LenzRoutes.modalUp<bool>(const GuestPaywallScreen()));
  }

  @override
  State<GuestPaywallScreen> createState() => _GuestPaywallScreenState();
}

class _GuestPaywallScreenState extends State<GuestPaywallScreen> {
  bool _showEmailForm = false;
  bool _isSignUp = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onAccountLinked() {
    try {
      final profileVm = context.read<ProfileViewModel>();
      profileVm.setPlanName('Free Plan');
      // The server decides the starting balance (free scans are given once per
      // device) and the profile listener shows it; the toast says which case.
      final usedUp = context.read<AuthService>().freeScansAlreadyUsedOnDevice;
      showLenzToast(
        context,
        usedUp
            ? 'Account created. This device has already used its free scans.'
            : 'Account created! Your free scans are ready.',
      );
    } catch (_) {}
    Haptics.mediumImpact();
    Navigator.of(context).pop(true);
  }

  Future<void> _handleGoogleSignIn(AuthService authService) async {
    Haptics.lightImpact();
    final cred = await authService.signInWithGoogle();
    if (!mounted) return;
    if (cred != null) {
      _onAccountLinked();
    }
  }

  Future<void> _handleAppleSignIn(AuthService authService) async {
    Haptics.lightImpact();
    final cred = await authService.signInWithApple();
    if (!mounted) return;
    if (cred != null) {
      _onAccountLinked();
    }
  }

  Future<void> _handleEmailSubmit(AuthService authService) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter email and password.')));
      return;
    }

    Haptics.lightImpact();
    if (_isSignUp) {
      final cred = await authService.signUpWithEmail(
        email,
        password,
        displayName: _nameController.text.trim(),
      );
      if (!mounted) return;
      if (cred != null) {
        _onAccountLinked();
      }
    } else {
      final cred = await authService.signInWithEmail(email, password);
      if (!mounted) return;
      if (cred != null) {
        _onAccountLinked();
      }
    }
  }

  void _close() {
    if (widget.onDismiss != null) {
      widget.onDismiss!();
    } else {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final profileVm = context.watch<ProfileViewModel>();
    final scansUsed = (_guestScanAllowance - profileVm.user.scansRemaining).clamp(
      0,
      _guestScanAllowance,
    );
    final busy = authService.isLoading;
    final showApple = widget.showAppleOverride ?? Platform.isIOS;
    final mq = MediaQuery.of(context);

    final google = LenzSocialButton(
      label: 'Google',
      leading: const GoogleGIcon(size: 22),
      onPressed: busy ? null : () => _handleGoogleSignIn(authService),
    );

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LenzBlob(color: Color(0xFFF4DEB8)),
          SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              20,
              math.max(14.0, mq.padding.top + 14),
              20,
              28 + mq.padding.bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        LenzIconButton(icon: LenzIcons.x, semanticLabel: 'Close', onTap: _close),
                        const SizedBox(width: 12),
                        const Spacer(),
                        Flexible(
                          flex: 6,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: LenzPill(
                              label: '$scansUsed of $_guestScanAllowance guest scans used',
                              variant: LenzPillVariant.unsure,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 220,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: SizedBox(
                                width: 240,
                                child: LenzCharacter(mood: LenzMood.sorry, view: LenzView.bust),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 30,
                            child: LenzBubble(
                              text: authService.guestScansAlreadyUsedOnDevice
                                  ? 'This device has already used its guest scans.'
                                  : scansUsed >= _guestScanAllowance
                                  ? 'You used all $_guestScanAllowance guest scans.'
                                  : "You've used $scansUsed of $_guestScanAllowance guest scans.",
                              maxWidth: 140,
                              style: LenzText.bubble.copyWith(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    LenzStagger(
                      spacing: 14,
                      children: [
                        Text(
                          'Create an account to keep scanning',
                          textAlign: TextAlign.center,
                          style: LenzText.display.copyWith(fontSize: 29, letterSpacing: -.035 * 29),
                        ),
                        const LenzCard(
                          radius: 28,
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _BenefitRow(
                                icon: LenzIcons.layers,
                                title: 'Save your scan reports',
                                subtitle: 'Guest scans are not kept. Yours stay saved',
                              ),
                              _BenefitRow(
                                icon: LenzIcons.gift,
                                title: 'Free scans with your account',
                                subtitle: 'Given once per device, when your account is active',
                              ),
                              _BenefitRow(
                                icon: LenzIcons.cloud,
                                title: 'Sync across devices',
                                subtitle: 'Open your vault from any phone',
                              ),
                            ],
                          ),
                        ),
                        if (authService.authError != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: LenzColors.badSoft,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              authService.authError!,
                              textAlign: TextAlign.center,
                              style: LenzText.cap.copyWith(color: LenzColors.bad, height: 1.35),
                            ),
                          ),
                        if (showApple)
                          Row(
                            children: [
                              Expanded(
                                child: LenzSocialButton(
                                  label: 'Apple',
                                  icon: LenzIcons.apple,
                                  onPressed: busy ? null : () => _handleAppleSignIn(authService),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: google),
                            ],
                          )
                        else
                          google,
                        AnimatedSize(
                          duration: const Duration(milliseconds: 320),
                          curve: LenzMotion.ease,
                          alignment: Alignment.topCenter,
                          child: _showEmailForm
                              ? _buildEmailForm(authService, busy)
                              : LenzButton(
                                  label: 'Continue with email',
                                  icon: LenzIcons.mail,
                                  onPressed: () {
                                    Haptics.lightImpact();
                                    setState(() => _showEmailForm = true);
                                  },
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailForm(AuthService authService, bool busy) {
    return LenzCard(
      radius: 28,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isSignUp ? 'Create account' : 'Sign in with email',
                  style: LenzText.title.copyWith(fontSize: 19),
                ),
              ),
              LenzIconButton(
                icon: LenzIcons.x,
                size: 36,
                iconSize: 18,
                semanticLabel: 'Hide email form',
                onTap: () => setState(() => _showEmailForm = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isSignUp) ...[
            LenzField(
              controller: _nameController,
              hint: 'Your name',
              icon: LenzIcons.user,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
          ],
          LenzField(
            controller: _emailController,
            hint: 'Email address',
            icon: LenzIcons.mail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          LenzField(
            controller: _passwordController,
            hint: 'Password',
            icon: LenzIcons.lock,
            obscure: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleEmailSubmit(authService),
          ),
          const SizedBox(height: 14),
          LenzButton(
            label: _isSignUp ? 'Register & unlock scans' : 'Sign in',
            loading: busy,
            onPressed: busy ? null : () => _handleEmailSubmit(authService),
          ),
          const SizedBox(height: 4),
          LenzPressable(
            onTap: () => setState(() => _isSignUp = !_isSignUp),
            child: SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  _isSignUp
                      ? 'Already have an account? Sign in'
                      : "Don't have an account? Register",
                  textAlign: TextAlign.center,
                  style: LenzText.cap.copyWith(color: LenzColors.forest2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.icon, required this.title, required this.subtitle});

  final String icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: LenzColors.mint2,
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: LenzIcon(icon, size: 22, color: LenzColors.forest),
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
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: LenzColors.ink,
                  ),
                ),
                Text(subtitle, style: LenzText.sub.copyWith(fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
