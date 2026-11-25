import 'package:flutter/material.dart';

import '../../services/storage_service.dart';
import '../../widgets/common/legal_links.dart';
import '../../widgets/ui/ui.dart';

/// One-time permission before the first scan sends photos off the device
/// (App Review Guideline 5.1.2(i): name the third parties and ask first).
///
/// The answer is stored on this device under [kAiConsentKey]. "Not now"
/// stores nothing, so the sheet is shown again on the next scan attempt.
abstract final class AiConsent {
  static const String kAiConsentKey = 'ai_photo_consent_v1';

  static bool isGiven(StorageService storage) =>
      storage.getBool(kAiConsentKey, defaultValue: false);

  /// Returns true when the user has agreed (now or earlier).
  static Future<bool> ensure(BuildContext context, StorageService storage) async {
    if (isGiven(storage)) return true;
    final ok = await showLenzSheet<bool>(
      context,
      barrierLabel: 'Photo analysis permission',
      builder: (_) => const AiConsentContent(),
    );
    if (ok == true) {
      storage.setBool(kAiConsentKey, true);
      return true;
    }
    return false;
  }
}

/// Body of the consent sheet; public so tests and the gallery can show it.
class AiConsentContent extends StatelessWidget {
  const AiConsentContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          'Allow photo analysis?',
          textAlign: TextAlign.center,
          style: LenzText.title,
        ),
        const SizedBox(height: 8),
        Text(
          'To check your item, Lenz sends the photos you take to third-party services:',
          textAlign: TextAlign.center,
          style: LenzText.sub,
        ),
        const SizedBox(height: 12),
        const _Point(
          icon: LenzIcons.sparkles,
          title: 'Google Gemini (AI analysis)',
          body: 'Your photos are analysed by Google\'s Gemini AI to assess the item. '
              'Only the photos are sent, not your name or email.',
        ),
        const _Point(
          icon: LenzIcons.cloud,
          title: 'Cloudinary (photo storage)',
          body: 'With an account, photos are stored so your reports keep them. '
              'Delete a report or your account to remove them. Guest photos are not kept.',
        ),
        const SizedBox(height: 6),
        LegalLinksText(prefix: 'Details are in our', style: LenzText.tiny),
        const SizedBox(height: 14),
        LenzButton(
          label: 'Allow',
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 8),
        LenzButton(
          label: 'Not now',
          variant: LenzButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: LenzColors.mint2,
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: LenzIcon(icon, size: 20, color: LenzColors.forest),
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
                    fontSize: 15,
                    color: LenzColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: LenzText.sub.copyWith(fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
