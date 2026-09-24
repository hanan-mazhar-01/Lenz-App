import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../services/haptics.dart';

class HelpSupportSheet extends StatefulWidget {
  const HelpSupportSheet({super.key});

  @override
  State<HelpSupportSheet> createState() => _HelpSupportSheetState();
}

class _HelpSupportSheetState extends State<HelpSupportSheet> {
  static const String _supportEmail = 'support@veradostudio.com';

  final List<Map<String, String>> _faqs = [
    {
      'q': 'How does the authenticity check work?',
      'a':
          'Lenz uses Google\'s Gemini AI to visually examine your photos - stitching, hardware, materials, fonts, and construction details - and compares what it sees against known authentic and replica patterns for that product. It\'s an AI-assisted opinion, not an official brand certification.',
    },
    {
      'q': 'What does "Inconclusive" mean?',
      'a':
          'An Inconclusive result means the evidence provided wasn\'t enough for a confident call either way - often because of missing angles, glare, or blur. Recapturing the requested photos in better lighting usually resolves it.',
    },
    {
      'q': 'Which categories are supported?',
      'a':
          'Sneakers, bags, watches, clothing, and accessories all have their own guided capture checklists tailored to what actually matters for that category.',
    },
  ];

  int? _expandedIndex;

  void _copyEmail() {
    Clipboard.setData(const ClipboardData(text: _supportEmail));
    Haptics.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Support email copied: $_supportEmail'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showContactInfoDialog() {
    Haptics.lightImpact();
    showCupertinoDialog(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: const Text('Contact Support'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Have questions or need help? Reach out directly via email:',
                style: TextStyle(fontSize: 13),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              SelectableText(
                _supportEmail,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Copy Email'),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _copyEmail();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppColors.neutralPill,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Help & Support', style: AppTypography.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Answers to common questions and our contact information.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 16),

            // FAQs Accordion
            ...List.generate(_faqs.length, (i) {
              final isExpanded = _expandedIndex == i;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Haptics.selectionClick();
                    setState(() {
                      _expandedIndex = isExpanded ? null : i;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _faqs[i]['q']!,
                                style: AppTypography.titleMedium.copyWith(fontSize: 14),
                              ),
                            ),
                            Icon(
                              isExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                              size: 16,
                              color: AppColors.textTertiary,
                            ),
                          ],
                        ),
                        if (isExpanded) ...[
                          const SizedBox(height: 10),
                          Text(
                            _faqs[i]['a']!,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 14),

            // Contact Info Section
            Text(
              'CONTACT INFO',
              style: AppTypography.captionMedium.copyWith(letterSpacing: 0.6),
            ),
            const SizedBox(height: 10),

            // Contact Info Card with Copy Email
            BounceButton(
              onTap: _showContactInfoDialog,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.deepForestGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        CupertinoIcons.mail_solid,
                        size: 20,
                        color: AppColors.deepForestGreen,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Email Support',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _supportEmail,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        CupertinoIcons.doc_on_clipboard,
                        size: 19,
                        color: AppColors.accent,
                      ),
                      tooltip: 'Copy Email',
                      onPressed: _copyEmail,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
