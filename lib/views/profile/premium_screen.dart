import 'package:flutter/material.dart';
import '../paywall/premium_paywall_screen.dart';

/// Fullscreen Lenz Premium paywall powered by RevenueCat.
class PremiumScreen extends StatelessWidget {
  final VoidCallback onClose;

  const PremiumScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return PremiumPaywallScreen(onClose: onClose);
  }
}
