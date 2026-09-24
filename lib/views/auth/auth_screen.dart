import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/auth_service.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';
import '../../services/haptics.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback? onContinueAsGuest;

  const AuthScreen({super.key, this.onContinueAsGuest});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isSignUp = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _toggleMode() {
    Haptics.selectionClick();
    setState(() => _isSignUp = !_isSignUp);
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.danger : AppColors.deepForestGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  Future<void> _submit(AuthService authService) async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Please enter both email and password.');
      return;
    }

    final credential = _isSignUp
        ? await authService.signUpWithEmail(
            email,
            password,
            displayName: _nameController.text.trim(),
          )
        : await authService.signInWithEmail(email, password);

    if (!mounted) return;

    if (authService.authError != null) {
      _showSnack(authService.authError!, isError: true);
    } else if (credential != null) {
      _dismissIfPushed();
    }
  }

  /// When this screen was pushed on top of another (e.g. from onboarding's
  /// "Log in" link), pop it after a successful sign-in so the user lands
  /// straight back on whatever screen is underneath.
  void _dismissIfPushed() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  void _openForgotPassword(AuthService authService) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ForgotPasswordSheet(
        authService: authService,
        initialEmail: _emailController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final busy = authService.isLoading;
    final canDismiss = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Stack(
          children: [
            _buildForm(context, authService, busy),
            if (canDismiss)
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(
                  icon: Icon(Icons.close_rounded, color: AppColors.textTertiaryOf(context)),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, AuthService authService, bool busy) {
    return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),

                  // Mascot
                  const FadeSlideTransition(
                    child: Center(
                      child: DetectiveMascotWidget(
                        state: MascotState.curious,
                        size: 104,
                        showHalo: true,
                        triggerGlance: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Title (crossfades between Welcome Back / Create Account)
                  FadeSlideTransition(
                    delay: const Duration(milliseconds: 80),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.18),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          _isSignUp ? 'Create Account' : 'Welcome Back',
                          key: ValueKey(_isSignUp),
                          textAlign: TextAlign.center,
                          style: AppTypography.displayLarge.copyWith(
                            color: AppColors.text(context),
                            fontFamily: 'Schyler',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Fields
                  FadeSlideTransition(
                    delay: const Duration(milliseconds: 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _isSignUp
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _AuthField(
                                    controller: _nameController,
                                    hint: 'Name',
                                    icon: Icons.person_outline_rounded,
                                    textInputAction: TextInputAction.next,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        _AuthField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          hint: 'Email',
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: 12),
                        _AuthField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          hint: 'Password',
                          icon: Icons.lock_outline_rounded,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(authService),
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 20,
                              color: AppColors.textTertiaryOf(context),
                            ),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _isSignUp
                              ? const SizedBox(height: 20)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed:
                                          busy ? null : () => _openForgotPassword(authService),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        'Forgot password?',
                                        style: AppTypography.callout.copyWith(
                                          color: AppColors.accentOf(context),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Primary CTA
                  FadeSlideTransition(
                    delay: const Duration(milliseconds: 200),
                    child: BounceButton(
                      onTap: busy ? null : () => _submit(authService),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: busy ? 0.7 : 1,
                        child: Container(
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.deepForestGreen,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.deepForestGreen.withValues(alpha: 0.28),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: AppColors.pureWhite,
                                  ),
                                )
                              : AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: Text(
                                    _isSignUp ? 'Create Account' : 'Sign In',
                                    key: ValueKey(_isSignUp),
                                    style: const TextStyle(
                                      color: AppColors.pureWhite,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Mode toggle
                  FadeSlideTransition(
                    delay: const Duration(milliseconds: 240),
                    child: Center(
                      child: GestureDetector(
                        onTap: _toggleMode,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: RichText(
                            text: TextSpan(
                              style: AppTypography.callout
                                  .copyWith(color: AppColors.secondaryText(context)),
                              children: [
                                TextSpan(text: _isSignUp ? 'Have an account? ' : 'New here? '),
                                TextSpan(
                                  text: _isSignUp ? 'Sign In' : 'Sign Up',
                                  style: TextStyle(
                                    color: AppColors.accentOf(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Divider
                  FadeSlideTransition(
                    delay: const Duration(milliseconds: 280),
                    child: Row(
                      children: [
                        Expanded(child: Divider(color: AppColors.borderOf(context))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textTertiaryOf(context)),
                          ),
                        ),
                        Expanded(child: Divider(color: AppColors.borderOf(context))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Google
                  FadeSlideTransition(
                    delay: const Duration(milliseconds: 320),
                    child: BounceButton(
                      onTap: busy
                          ? null
                          : () async {
                              final result = await authService.signInWithGoogle();
                              if (mounted && result != null) _dismissIfPushed();
                            },
                      child: _SocialButton(
                        icon: const _GoogleGIcon(),
                        label: 'Continue with Google',
                        disabled: busy,
                      ),
                    ),
                  ),

                  // Apple (iOS only)
                  if (Theme.of(context).platform == TargetPlatform.iOS) ...[
                    const SizedBox(height: 12),
                    FadeSlideTransition(
                      delay: const Duration(milliseconds: 360),
                      child: BounceButton(
                        onTap: busy
                            ? null
                            : () async {
                                final result = await authService.signInWithApple();
                                if (mounted && result != null) _dismissIfPushed();
                              },
                        child: _SocialButton(
                          icon: Icon(Icons.apple, size: 22, color: AppColors.text(context)),
                          label: 'Continue with Apple',
                          disabled: busy,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Guest
                  FadeSlideTransition(
                    delay: const Duration(milliseconds: 400),
                    child: Center(
                      child: TextButton(
                        onPressed: () async {
                          if (widget.onContinueAsGuest != null) {
                            widget.onContinueAsGuest!();
                            return;
                          }
                          // Pushed context (e.g. from onboarding's "Log in"):
                          // there's already an anonymous session by default,
                          // so just close this screen to reveal Home. Only
                          // sign in if that's somehow not already the case.
                          if (!authService.isAuthenticated) {
                            await authService.signInAnonymously();
                          }
                          if (mounted) _dismissIfPushed();
                        },
                        child: Text(
                          'Continue as Guest',
                          style: AppTypography.callout.copyWith(
                            color: AppColors.textTertiaryOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
  }
}

/// Minimal, theme-aware input used across the auth screen.
class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  const _AuthField({
    required this.controller,
    this.focusNode,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: AppTypography.bodyLarge.copyWith(color: AppColors.text(context)),
      cursorColor: AppColors.accentOf(context),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.bodyLarge.copyWith(color: AppColors.textTertiaryOf(context)),
        prefixIcon: Icon(icon, size: 20, color: AppColors.textTertiaryOf(context)),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surfaceOf(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.accentOf(context), width: 1.6),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final bool disabled;

  const _SocialButton({
    required this.icon,
    required this.label,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: disabled ? 0.6 : 1,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: AppTypography.titleMedium.copyWith(
                fontSize: 15,
                color: AppColors.text(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Official multi-color Google "G" mark, embedded so no extra asset is needed.
class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  static const _svg = '''
<svg viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg">
  <path fill="#4285F4" d="M17.64 9.2045c0-.6381-.0573-1.2518-.1636-1.8409H9v3.4814h4.8436c-.2086 1.125-.8427 2.0782-1.7959 2.7164v2.2582h2.9087c1.7018-1.5668 2.6836-3.8741 2.6836-6.6151z"/>
  <path fill="#34A853" d="M9 18c2.43 0 4.4673-.806 5.9564-2.1805l-2.9087-2.2582c-.8059.54-1.8368.8591-3.0477.8591-2.344 0-4.3282-1.5831-5.036-3.7104H.9573v2.3318C2.4382 15.9832 5.4818 18 9 18z"/>
  <path fill="#FBBC05" d="M3.964 10.71c-.18-.54-.2822-1.1168-.2822-1.71s.1023-1.17.2823-1.71V4.9582H.9573A8.9965 8.9965 0 000 9c0 1.4523.3477 2.8268.9573 4.0418L3.964 10.71z"/>
  <path fill="#EA4335" d="M9 3.5795c1.3214 0 2.5077.4541 3.4405 1.346l2.5813-2.5814C13.4632.8918 11.426 0 9 0 5.4818 0 2.4382 2.0168.9573 4.9582L3.964 7.29C4.6718 5.1627 6.656 3.5795 9 3.5795z"/>
</svg>''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_svg, width: 20, height: 20);
  }
}

/// Bottom sheet for password-reset requests.
class _ForgotPasswordSheet extends StatefulWidget {
  final AuthService authService;
  final String initialEmail;

  const _ForgotPasswordSheet({
    required this.authService,
    required this.initialEmail,
  });

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialEmail);

  bool _isSending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _controller.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });

    final success = await widget.authService.sendPasswordResetEmail(email);
    if (!mounted) return;

    setState(() {
      _isSending = false;
      if (success) {
        _sent = true;
      } else {
        _error = widget.authService.authError ?? 'Something went wrong. Please try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
        decoration: BoxDecoration(
          color: AppColors.bg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child),
              ),
              child: _sent ? _buildSentState(context) : _buildFormState(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormState(BuildContext context) {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Reset Password',
          textAlign: TextAlign.center,
          style: AppTypography.titleLarge.copyWith(color: AppColors.text(context)),
        ),
        const SizedBox(height: 6),
        Text(
          "We'll email you a reset link.",
          textAlign: TextAlign.center,
          style: AppTypography.callout.copyWith(color: AppColors.secondaryText(context)),
        ),
        const SizedBox(height: 20),
        _AuthField(
          controller: _controller,
          hint: 'Email',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _send(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: AppTypography.callout.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: 18),
        BounceButton(
          onTap: _isSending ? null : _send,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.deepForestGreen,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.pureWhite),
                  )
                : const Text(
                    'Send Reset Link',
                    style: TextStyle(
                      color: AppColors.pureWhite,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSentState(BuildContext context) {
    return Column(
      key: const ValueKey('sent'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_rounded, size: 48, color: AppColors.deepForestGreen),
        const SizedBox(height: 14),
        Text(
          'Check your inbox',
          textAlign: TextAlign.center,
          style: AppTypography.titleLarge.copyWith(color: AppColors.text(context)),
        ),
        const SizedBox(height: 6),
        Text(
          'Reset link sent to ${_controller.text.trim()}',
          textAlign: TextAlign.center,
          style: AppTypography.callout.copyWith(color: AppColors.secondaryText(context)),
        ),
        const SizedBox(height: 20),
        BounceButton(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.deepForestGreen,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Done',
              style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}
