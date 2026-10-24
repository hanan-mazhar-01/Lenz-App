import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/revenue_cat_config.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';
import 'profile_sheet_parts.dart';

/// Terms of service sheet (prototype `ACT.terms`, mood `focus`). Paints its
/// own ivory frame + grabber so it works inside a plain
/// `showModalBottomSheet(backgroundColor: Colors.transparent, ...)`.
class TermsOfServiceSheet extends StatelessWidget {
  const TermsOfServiceSheet({super.key});

  Future<void> _openTermsOfService() async {
    final uri = Uri.parse(RevenueCatConfig.termsOfServiceUrl);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Could not open terms of service: $e');
    }
  }

  static const _sectionTitle = TextStyle(
    fontFamily: LenzText.family,
    color: LenzColors.ink,
    fontSize: 16,
    fontWeight: FontWeight.w900,
  );

  static const _sections = <(String, String)>[
    (
      'Subscription and auto-renewal',
      'Subscriptions automatically renew unless auto-renew is turned off at least 24 hours before the end of the current billing period. Payment will be charged to your Apple ID account at confirmation of purchase.',
    ),
    (
      '3-day free trial',
      'Any unused portion of a free trial period, if offered, will be forfeited when purchasing a subscription. You can cancel your free trial anytime in your Apple ID account settings without being charged.',
    ),
    (
      'Cancellation and refunds',
      'You can manage or cancel your subscription anytime in your iPhone Settings > Apple ID > Subscriptions. All refunds are handled directly by Apple according to App Store policy.',
    ),
    (
      'Authentication disclaimer',
      'Lenz gives an AI-assisted opinion on product authenticity, not an official brand authentication or a guarantee. A result that an item "looks authentic" does not guarantee that it is genuine, and a result that it "looks fake" does not prove that it is counterfeit. Results are intended for advisory purposes and do not replace certified manufacturer appraisals.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LenzSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LenzSheetHead(
            title: 'Terms of service',
            subtitle: 'Lenz subscription and usage agreement.',
            mood: LenzMood.focus,
          ),
          for (final s in _sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.$1, style: _sectionTitle),
                  const SizedBox(height: 3),
                  Text(s.$2, style: LenzText.sub.copyWith(fontSize: 13.5)),
                ],
              ),
            ),
          LenzExternalLinkButton(
            label: 'View Terms of Service',
            onPressed: _openTermsOfService,
          ),
          const SizedBox(height: 10),
          LenzButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
