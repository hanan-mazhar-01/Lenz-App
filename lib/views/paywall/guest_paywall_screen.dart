import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/mascot/detective_mascot_widget.dart';
import '../../services/haptics.dart';

const int _guestScanAllowance = 3;

class GuestPaywallScreen extends StatefulWidget {
  final VoidCallback? onDismiss;

  const GuestPaywallScreen({super.key, this.onDismiss});

  static Future<bool?> show(BuildContext context) {
    Haptics.mediumImpact();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GuestPaywallScreen(),
    );
  }

  @override
  State<GuestPaywallScreen> createState() => _GuestPaywallScreenState();
}

class _GuestPaywallScreenState extends State<GuestPaywallScreen> {
  bool _showEmailForm = false;
  bool _isSignUp = true;
  bool _obscurePassword = true;

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

  Future<void> _handleGoogleSignIn(AuthService authService) async {
    Haptics.lightImpact();
    final cred = await authService.signInWithGoogle();
    if (!mounted) return;
    if (cred != null) {
      Haptics.mediumImpact();
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _handleAppleSignIn(AuthService authService) async {
    Haptics.lightImpact();
    final cred = await authService.signInWithApple();
    if (!mounted) return;
    if (cred != null) {
      Haptics.mediumImpact();
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _handleEmailSubmit(AuthService authService) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password.')),
      );
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
        Haptics.mediumImpact();
        Navigator.of(context).pop(true);
      }
    } else {
      final cred = await authService.signInWithEmail(email, password);
      if (!mounted) return;
      if (cred != null) {
        Haptics.mediumImpact();
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final profileVm = context.watch<ProfileViewModel>();
    final scansUsed = (_guestScanAllowance - profileVm.user.scansRemaining)
        .clamp(0, _guestScanAllowance);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.warmIvory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top drag indicator
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: AppColors.nearBlack.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Header Bar with Close Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: AppColors.deepForestGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_clock_outlined,
                          size: 13,
                          color: AppColors.deepForestGreen,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$scansUsed of $_guestScanAllowance Guest Scans Used',
                          style: const TextStyle(
                            color: AppColors.deepForestGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      if (widget.onDismiss != null) {
                        widget.onDismiss!();
                      } else {
                        Navigator.of(context).pop(false);
                      }
                    },
                    icon: const Icon(CupertinoIcons.xmark, size: 20),
                    color: AppColors.charcoalGray,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Detective Mascot
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.veryLightWarmGray,
                        border: Border.all(
                          color: AppColors.nearBlack.withValues(alpha: 0.06),
                          width: 1.5,
                        ),
                      ),
                    ),
                    const DetectiveMascotWidget(
                      size: 90,
                      state: MascotState.inspecting,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Headline & Description
              const Text(
                'Create an Account to Keep Scanning',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.nearBlack,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                scansUsed >= _guestScanAllowance
                    ? 'You have used all $_guestScanAllowance free guest scans. Sign in or register in seconds to preserve your scan history and get 5 more checks.'
                    : "You've used $scansUsed of your $_guestScanAllowance free guest scans. Sign in or register now to preserve your scan history and get 5 more checks.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.charcoalGray,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 18),

              // Benefit Rows Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.veryLightWarmGray,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.nearBlack.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  children: [
                    _buildBenefitRow(
                      icon: Icons.history_edu_rounded,
                      title: 'Keep All 3 Past Scan Reports',
                      subtitle: 'Your forensic reports and photos stay permanently saved',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    _buildBenefitRow(
                      icon: Icons.add_circle_outline_rounded,
                      title: 'Get 5 Additional Free Scans',
                      subtitle: 'Instant credit upgrade upon account activation',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    _buildBenefitRow(
                      icon: Icons.cloud_done_outlined,
                      title: 'Cross-Device Cloud Sync',
                      subtitle: 'Access your luxury vault and reports from any phone',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Error notification if present
              if (authService.authError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    authService.authError!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Google Sign In Button
              BounceButton(
                onTap: authService.isLoading ? null : () => _handleGoogleSignIn(authService),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.nearBlack.withValues(alpha: 0.12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.nearBlack.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Center(
                          child: Text(
                            'G',
                            style: TextStyle(
                              color: Color(0xFF4285F4),
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Continue with Google',
                        style: TextStyle(
                          color: AppColors.nearBlack,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Apple Sign In (iOS only)
              if (Platform.isIOS) ...[
                BounceButton(
                  onTap: authService.isLoading ? null : () => _handleAppleSignIn(authService),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.nearBlack,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.apple, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Continue with Apple',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Toggle Email Form Button / Email Form Container
              if (!_showEmailForm) ...[
                BounceButton(
                  onTap: () {
                    Haptics.lightImpact();
                    setState(() => _showEmailForm = true);
                  },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.deepForestGreen,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.deepForestGreen.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mail_outline_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Continue with Email',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Inline Email Input Fields
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.veryLightWarmGray,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.nearBlack.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isSignUp ? 'Create Account' : 'Sign In with Email',
                            style: const TextStyle(
                              color: AppColors.nearBlack,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showEmailForm = false),
                            child: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_isSignUp) ...[
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            hintText: 'Your Name',
                            prefixIcon: const Icon(Icons.person_outline_rounded, size: 19),
                            filled: true,
                            fillColor: AppColors.pureWhite,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'Email address',
                          prefixIcon: const Icon(Icons.alternate_email_rounded, size: 19),
                          filled: true,
                          fillColor: AppColors.pureWhite,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 19,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          filled: true,
                          fillColor: AppColors.pureWhite,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      BounceButton(
                        onTap: authService.isLoading ? null : () => _handleEmailSubmit(authService),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.deepForestGreen,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: authService.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _isSignUp ? 'Register & Unlock Scans' : 'Sign In',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() => _isSignUp = !_isSignUp),
                          child: Text(
                            _isSignUp
                                ? 'Already have an account? Sign In'
                                : "Don't have an account? Register",
                            style: const TextStyle(
                              color: AppColors.deepForestGreen,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.deepForestGreen.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: AppColors.deepForestGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.nearBlack,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.charcoalGray,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
