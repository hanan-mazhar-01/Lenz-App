import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';
import '../paywall/guest_paywall_screen.dart';
import 'profile_sheet_parts.dart';

/// Free scans a guest starts with.
const int kGuestScanAllowance = 3;

/// Free scans a signed-in account gets (the server gives 3, once per device);
/// only used to size the ring, so a full free balance fills it.
const int kAccountScanAllowance = 3;

/// Scan credits sheet (prototype `ACT.credits`, mood `think`, or `happy` for
/// Pro). Paints its own ivory frame + grabber so it works inside a plain
/// `showModalBottomSheet(backgroundColor: Colors.transparent, ...)`.
///
/// Guests never see the Pro upgrade here; they get the account-creation
/// prompt (guest paywall) instead.
class ScanCreditsSheet extends StatelessWidget {
  final VoidCallback onOpenPremium;

  const ScanCreditsSheet({super.key, required this.onOpenPremium});

  bool _isGuest(BuildContext context) {
    try {
      return context.read<AuthService>().isAnonymous;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileVm = context.watch<ProfileViewModel>();
    final user = profileVm.user;
    final isGuest = _isGuest(context);
    final pro = user.isPremium;
    final allowance = isGuest ? kGuestScanAllowance : kAccountScanAllowance;
    final left = user.scansRemaining < 0 ? 0 : user.scansRemaining;

    return LenzSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LenzSheetHead(
            title: 'Scan credits',
            subtitle: pro
                ? 'You have unlimited scans.'
                : (isGuest ? 'Your free guest scans.' : 'Your free scans.'),
            mood: pro ? LenzMood.happy : LenzMood.think,
          ),
          LenzCard(
            radius: 30,
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                LenzRing(
                  value: pro ? 1 : (left / allowance).clamp(0.0, 1.0),
                  size: 140,
                  strokeWidth: 14,
                  color: pro ? LenzColors.gold : LenzColors.leaf,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        child: pro
                            ? const LenzInfinityGlyph(width: 54, strokeWidth: 5)
                            : AnimatedCount(to: left, style: _bigNumber),
                      ),
                      Text(
                        pro
                            ? 'unlimited'
                            : (isGuest && left <= allowance
                                  ? 'of $allowance left'
                                  : 'left'),
                        style: LenzText.cap,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  pro
                      ? '${user.planName} Active • Unlimited authentications unlocked.'
                      : 'Free scans don\'t reset automatically - each one is used once.',
                  textAlign: TextAlign.center,
                  style: LenzText.sub,
                ),
              ],
            ),
          ),
          if (!pro && !isGuest) ...[
            const SizedBox(height: 14),
            LenzButton(
              label: 'Upgrade for unlimited scans',
              variant: LenzButtonVariant.gold,
              icon: LenzIcons.crown,
              onPressed: () {
                Navigator.of(context).pop();
                onOpenPremium();
              },
            ),
          ],
          if (!pro && isGuest) ...[
            const SizedBox(height: 14),
            LenzButton(
              label: 'Sign In / Create Account',
              icon: LenzIcons.gift,
              onPressed: () {
                final rootContext = Navigator.of(
                  context,
                  rootNavigator: true,
                ).context;
                Navigator.of(context).pop();
                GuestPaywallScreen.show(rootContext);
              },
            ),
          ],
        ],
      ),
    );
  }
}

const TextStyle _bigNumber = TextStyle(
  fontFamily: LenzText.family,
  color: LenzColors.ink,
  fontSize: 40,
  fontWeight: FontWeight.w900,
  height: 1,
);
