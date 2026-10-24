import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/revenue_cat_config.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';
import 'profile_sheet_parts.dart';

/// Privacy and security sheet (prototype `ACT.privacy`, mood `pleased`).
/// Paints its own ivory frame + grabber so it works inside a plain
/// `showModalBottomSheet(backgroundColor: Colors.transparent, ...)`.
class PrivacySecuritySheet extends StatelessWidget {
  const PrivacySecuritySheet({super.key});

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(RevenueCatConfig.privacyPolicyUrl);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Could not open privacy policy: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LenzSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LenzSheetHead(
            title: 'Privacy and security',
            subtitle: 'How your scan data and photos are guarded.',
            mood: LenzMood.pleased,
          ),
          const LenzInfoCard(
            icon: LenzIcons.camera,
            title: 'Product photos and AI analysis',
            body:
                'Photos you submit are sent to our server and analyzed with Google Gemini AI models '
                'to evaluate stitching, materials, hardware, and typography. '
                'With an account, your photos are stored with our image host (Cloudinary) so your '
                'reports stay in your history. As a guest nothing is saved: your report is shown '
                'once and not kept. You can permanently delete your photos and reports at any time '
                'from Profile > Delete account.',
          ),
          const LenzInfoCard(
            icon: LenzIcons.cloud,
            title: 'Account and scan reports',
            body:
                'Your sign-in details, reports and favorites are kept in Firebase (Google Cloud) '
                'with access limited to your own account. To limit free scans to one set per '
                'phone, we also keep a one-way hash of a device identifier. We never sell your '
                'personal information.',
          ),
          const LenzInfoCard(
            icon: LenzIcons.lock,
            title: 'Data in transit and storage',
            body:
                'All network communication between your device and our servers is '
                'strictly encrypted via industry-standard TLS. Signing out clears '
                'local device caches while preserving your cloud account data.',
          ),
          const SizedBox(height: 6),
          LenzExternalLinkButton(
            label: 'View Privacy Policy',
            onPressed: _openPrivacyPolicy,
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
