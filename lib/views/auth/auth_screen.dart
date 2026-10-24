import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/haptics.dart';
import '../../widgets/common/google_icon.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';

/// Sign in / create account (prototype `SCREENS.auth`).
///
/// Lenz peeks above the card and reacts: focusing email/name -> `focus`,
/// focusing the password -> `shy` (eyes closed), showing the password ->
/// `hello`, blur -> `idle`. Errors appear inline and shake the card.
class AuthScreen extends StatefulWidget {
  final VoidCallback? onContinueAsGuest;

  /// Opens in "Create account" mode (presentation only; defaults to sign in).
  final bool initialSignUp;

  const AuthScreen({
    super.key,
    this.onContinueAsGuest,
    this.initialSignUp = false,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _nameFocus = FocusNode();
  final LenzController _lenz = LenzController();

  late bool _isSignUp = widget.initialSignUp;
  bool _obscurePassword = true;

  /// Inline error under the form (same strings the screen always showed).
  String? _error;
  late String _say = _isSignUp
      ? "Let's set you up!"
      : 'Welcome back, detective.';
  LenzMood? _override;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(_onTextFocus);
    _nameFocus.addListener(_onTextFocus);
    _passwordFocus.addListener(_onPasswordFocus);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _nameFocus.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onTextFocus() {
    if (!mounted) return;
    setState(() {
      if (_emailFocus.hasFocus || _nameFocus.hasFocus) {
        _override = null;
        _say = _isSignUp ? 'Nice to meet you!' : 'Welcome back, detective.';
      }
    });
  }

  void _onPasswordFocus() {
    if (!mounted) return;
    setState(() {
      if (_passwordFocus.hasFocus) {
        _override = null;
        _say = _obscurePassword
            ? 'No peeking, I promise.'
            : 'Okay, I see it now.';
      }
    });
  }

  /// Lenz's mood derived from the form state.
  LenzMood _mood(bool busy) {
    if (_override != null) return _override!;
    if (busy) return LenzMood.focus;
    if (_passwordFocus.hasFocus) {
      return _obscurePassword ? LenzMood.shy : LenzMood.hello;
    }
    if (_emailFocus.hasFocus || _nameFocus.hasFocus) return LenzMood.focus;
    return _error != null ? LenzMood.sorry : LenzMood.hello;
  }

  void _toggleMode() {
    Haptics.selectionClick();
    _lenz.hop();
    setState(() {
      _isSignUp = !_isSignUp;
      _error = null;
      _override = null;
      _say = _isSignUp ? "Let's set you up!" : 'Good to see you again.';
    });
  }

  void _toggleObscure() {
    setState(() {
      _obscurePassword = !_obscurePassword;
      _say = _obscurePassword ? 'Eyes closed again.' : 'Okay, I see it now.';
    });
  }

  void _showError(String message) {
    setState(() {
      _error = message;
      _override = null;
      _say = "Hmm, let's try that again.";
    });
    Haptics.lightImpact();
    if (!LenzMotion.reduced(context)) _shake.forward(from: 0);
  }

  Future<void> _submit(AuthService authService) async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter both email and password.');
      return;
    }
    setState(() => _error = null);

    final credential = _isSignUp
        ? await authService.signUpWithEmail(
            email,
            password,
            displayName: _nameController.text.trim(),
          )
        : await authService.signInWithEmail(email, password);

    if (!mounted) return;

    if (authService.authError != null) {
      _showError(authService.authError!);
    } else if (credential != null) {
      setState(() {
        _override = LenzMood.happy;
        _say = 'You are in!';
      });
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
    showLenzSheet<void>(
      context,
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
    // Close button only when this screen was pushed (not while a sheet
    // opened from it is on top of a root-level auth screen).
    final canDismiss = !(ModalRoute.of(context)?.isFirst ?? true);
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LenzBlob(color: Color(0xFFD9ECDF)),
          SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              20,
              math.max(48.0, mq.padding.top + 4),
              20,
              24 + mq.padding.bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(busy),
                    LenzRise(
                      index: 1,
                      child: _buildCard(context, authService, busy),
                    ),
                    const SizedBox(height: 14),
                    LenzRise(
                      index: 2,
                      child: LenzPressable(
                        onTap: () async {
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
                        child: SizedBox(
                          height: 44,
                          child: Center(
                            child: Text(
                              'Continue as guest',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: LenzText.buttonSm.copyWith(
                                color: LenzColors.forest,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const LenzRise(
                      index: 3,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'By continuing you agree to the Terms of Service and Privacy Policy.',
                          textAlign: TextAlign.center,
                          style: LenzText.tiny,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (canDismiss)
            Positioned(
              top: mq.padding.top + 8,
              right: 16,
              child: LenzIconButton(
                icon: LenzIcons.x,
                semanticLabel: 'Close',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
        ],
      ),
    );
  }

  /// Lenz bust (244 wide) peeking above the card with his speech bubble.
  Widget _buildHero(bool busy) {
    // 222px tall block, with the card pulled up 36px over its bottom.
    return SizedBox(
      height: 222 - 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 244,
                child: LenzCharacter(
                  mood: _mood(busy),
                  view: LenzView.bust,
                  controller: _lenz,
                ),
              ),
            ),
          ),
          Positioned(left: 0, top: 16, child: LenzBubble(text: _say)),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, AuthService authService, bool busy) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final google = LenzSocialButton(
      label: 'Google',
      leading: const GoogleGIcon(size: 22),
      onPressed: busy
          ? null
          : () async {
              final result = await authService.signInWithGoogle();
              if (mounted && result != null) _dismissIfPushed();
            },
    );

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = t == 0 || t == 1
            ? 0.0
            : math.sin(t * math.pi * 6) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: LenzColors.paper,
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: LenzColors.line),
          boxShadow: LenzShadows.sh2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LenzSegmented(
              labels: const ['Sign in', 'Create account'],
              index: _isSignUp ? 1 : 0,
              onChanged: (_) => _toggleMode(),
            ),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              key: ValueKey(_isSignUp),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 400),
              curve: LenzMotion.ease,
              builder: (context, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - v)),
                  child: child,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isSignUp) ...[
                    LenzField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      hint: 'Full name',
                      icon: LenzIcons.user,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      onSubmitted: (_) => _emailFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  LenzField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    hint: 'Email address',
                    icon: LenzIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 12),
                  _AuthPasswordField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscure: _obscurePassword,
                    onToggle: _toggleObscure,
                    hasError: _error != null,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _submit(authService),
                  ),
                  if (!_isSignUp) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: LenzPressable(
                        onTap: busy
                            ? null
                            : () => _openForgotPassword(authService),
                        child: Text(
                          'Forgot password?',
                          style: LenzText.link.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: LenzColors.forest2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: LenzMotion.ease,
              alignment: Alignment.topCenter,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _InlineError(message: _error!),
                    ),
            ),
            const SizedBox(height: 16),
            LenzButton(
              label: _isSignUp ? 'Create account' : 'Sign in',
              loading: busy,
              onPressed: busy ? null : () => _submit(authService),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LenzDivider(label: 'or continue with'),
            ),
            if (isIOS)
              Row(
                children: [
                  Expanded(
                    child: LenzSocialButton(
                      label: 'Apple',
                      icon: LenzIcons.apple,
                      onPressed: busy
                          ? null
                          : () async {
                              final result = await authService
                                  .signInWithApple();
                              if (mounted && result != null) _dismissIfPushed();
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: google),
                ],
              )
            else
              google,
          ],
        ),
      ),
    );
  }
}

/// Inline error row (bad-soft pill) used by the auth forms.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: LenzColors.badSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: LenzIcon(LenzIcons.warn, size: 18, color: LenzColors.bad),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: LenzText.cap.copyWith(color: LenzColors.bad, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Password variant of `LenzField` whose show/hide state is owned by the
/// screen (so Lenz can react to the eye toggle). Same 58px / radius 20 /
/// 1.5px border / focus ring look as the kit field.
class _AuthPasswordField extends StatefulWidget {
  const _AuthPasswordField({
    required this.controller,
    required this.focusNode,
    required this.obscure,
    required this.onToggle,
    this.hasError = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscure;
  final VoidCallback onToggle;
  final bool hasError;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<_AuthPasswordField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _AuthPasswordField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    final borderColor = widget.hasError
        ? LenzColors.bad
        : focused
        ? LenzColors.forest2
        : LenzColors.line;
    return AnimatedContainer(
      duration: LenzMotion.field,
      curve: Curves.ease,
      height: 58,
      padding: const EdgeInsets.only(left: 16, right: 5),
      decoration: BoxDecoration(
        color: LenzColors.paper,
        borderRadius: BorderRadius.circular(LenzRadii.field),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: widget.hasError
                      ? LenzColors.bad.withValues(alpha: .14)
                      : LenzColors.focusRing,
                  spreadRadius: 5,
                ),
              ]
            : LenzShadows.sh1,
      ),
      child: Row(
        children: [
          const LenzIcon(LenzIcons.lock, size: 22, color: LenzColors.subtle),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              obscureText: widget.obscure,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              maxLines: 1,
              style: LenzText.field,
              cursorColor: LenzColors.forest2,
              cursorWidth: 2,
              cursorRadius: const Radius.circular(2),
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: 'Password',
                hintStyle: LenzText.placeholder,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: widget.obscure ? 'Show password' : 'Hide password',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggle,
              child: SizedBox(
                width: 44,
                height: 58,
                child: Center(
                  child: LenzIcon(
                    widget.obscure ? LenzIcons.eye : LenzIcons.eyeOff,
                    size: 22,
                    color: LenzColors.subtle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for password-reset requests (prototype `ACT.forgot`).
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialEmail,
  );

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
        _error =
            widget.authService.authError ??
            'Something went wrong. Please try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Transform.translate(
          offset: const Offset(0, -6),
          child: SizedBox(
            width: 170,
            child: LenzCharacter(
              mood: _sent
                  ? LenzMood.happy
                  : (_error != null ? LenzMood.unsure : LenzMood.think),
              view: LenzView.bust,
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: _sent ? _buildSentState(context) : _buildFormState(context),
        ),
      ],
    );
  }

  Widget _buildFormState(BuildContext context) {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Reset your password',
          textAlign: TextAlign.center,
          style: LenzText.title,
        ),
        const SizedBox(height: 12),
        const Text(
          'We will email you a reset link.',
          textAlign: TextAlign.center,
          style: LenzText.sub,
        ),
        const SizedBox(height: 12),
        LenzField(
          controller: _controller,
          hint: 'Email address',
          icon: LenzIcons.mail,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          errorText: _error,
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 12),
        LenzButton(
          label: 'Send reset link',
          loading: _isSending,
          onPressed: _isSending ? null : _send,
        ),
      ],
    );
  }

  Widget _buildSentState(BuildContext context) {
    return Column(
      key: const ValueKey('sent'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Check your inbox',
          textAlign: TextAlign.center,
          style: LenzText.title,
        ),
        const SizedBox(height: 12),
        Text(
          'Reset link sent to ${_controller.text.trim()}',
          textAlign: TextAlign.center,
          style: LenzText.sub,
        ),
        const SizedBox(height: 12),
        LenzButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
