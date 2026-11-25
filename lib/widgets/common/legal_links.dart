import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/revenue_cat_config.dart';
import '../ui/ui.dart';

/// Opens [url] in the browser; never throws.
Future<void> openExternalUrl(String url) async {
  final uri = Uri.parse(url);
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[LegalLinks] Could not open $url: $e');
  }
}

/// "`prefix` Terms of Service and Privacy Policy." with both names tappable.
/// Used wherever an account is created or a purchase can start (Guideline
/// 3.1.2 / 5.1.1 ask for working links there).
class LegalLinksText extends StatefulWidget {
  const LegalLinksText({
    super.key,
    this.prefix = 'By continuing you agree to the',
    this.style,
    this.textAlign = TextAlign.center,
  });

  final String prefix;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<LegalLinksText> createState() => _LegalLinksTextState();
}

class _LegalLinksTextState extends State<LegalLinksText> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => openExternalUrl(RevenueCatConfig.termsOfServiceUrl);
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => openExternalUrl(RevenueCatConfig.privacyPolicyUrl);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? LenzText.tiny;
    final link = base.copyWith(
      color: LenzColors.forest,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: '${widget.prefix} '),
          TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }
}
