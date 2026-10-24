import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/haptics.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';
import 'profile_sheet_parts.dart';

/// Help and support sheet (prototype `ACT.help`, mood `hello`): support email
/// row, the real FAQ accordion, and Cancel / Copy email buttons. Paints its
/// own ivory frame + grabber so it works inside a plain
/// `showModalBottomSheet(backgroundColor: Colors.transparent, ...)`.
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
      'a': 'Lenz uses Google\'s Gemini AI to visually examine your photos - stitching, hardware, materials, fonts, and construction details - and compares what it sees against known authentic and replica patterns for that product. It\'s an AI-assisted opinion, not an official brand certification.',
    },
    {
      'q': 'What does "Inconclusive" mean?',
      'a': 'An Inconclusive result means the evidence provided wasn\'t enough for a confident call either way - often because of missing angles, glare, or blur. Recapturing the requested photos in better lighting usually resolves it.',
    },
    {
      'q': 'Which categories are supported?',
      'a': 'Sneakers, bags, watches, clothing, and accessories all have their own guided capture checklists tailored to what actually matters for that category.',
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

  Future<void> _showContactInfoDialog() async {
    Haptics.lightImpact();
    final copy = await showLenzConfirm(
      context,
      title: 'Contact support',
      text:
          'Have questions or need help? Reach out directly via email:\n$_supportEmail',
      okLabel: 'Copy email',
      character: (_) =>
          const LenzCharacter(mood: LenzMood.hello, view: LenzView.bust),
    );
    if (copy && mounted) _copyEmail();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = LenzMotion.reduced(context);
    return LenzSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LenzSheetHead(
            title: 'Help and support',
            subtitle:
                'Answers to common questions and our contact information.',
          ),
          LenzSettingGroup(
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              LenzSettingRow(
                icon: LenzIcons.mail,
                title: 'Email support',
                subtitle: _supportEmail,
                trailing: LenzIconButton(
                  icon: LenzIcons.file,
                  size: 38,
                  radius: 13,
                  iconSize: 18,
                  semanticLabel: 'Copy Email',
                  onTap: _copyEmail,
                ),
                onTap: _showContactInfoDialog,
              ),
            ],
          ),
          Text(
            'Have a question about a result or your subscription? Email us and include the item name.',
            style: LenzText.sub.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Common questions',
              style: LenzText.section.copyWith(fontSize: 17),
            ),
          ),
          LenzSettingGroup(
            margin: EdgeInsets.zero,
            children: [
              for (var i = 0; i < _faqs.length; i++)
                _FaqRow(
                  question: _faqs[i]['q']!,
                  answer: _faqs[i]['a']!,
                  expanded: _expandedIndex == i,
                  reduced: reduced,
                  onTap: () {
                    Haptics.selectionClick();
                    setState(() {
                      _expandedIndex = _expandedIndex == i ? null : i;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: LenzButton(
                  label: 'Cancel',
                  variant: LenzButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LenzButton(label: 'Copy email', onPressed: _copyEmail),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  const _FaqRow({
    required this.question,
    required this.answer,
    required this.expanded,
    required this.reduced,
    required this.onTap,
  });

  final String question;
  final String answer;
  final bool expanded;
  final bool reduced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: reduced ? 0 : 320);
    return Semantics(
      button: true,
      expanded: expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(question, style: LenzText.setting)),
                  const SizedBox(width: 10),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: duration,
                    curve: LenzMotion.spring,
                    child: const LenzIcon(
                      LenzIcons.chevD,
                      size: 18,
                      color: LenzColors.ink,
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: duration,
                curve: LenzMotion.ease,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          answer,
                          style: LenzText.sub.copyWith(fontSize: 13.5),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
