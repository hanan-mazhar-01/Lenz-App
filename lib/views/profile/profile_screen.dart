import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../models/authentication_result.dart';
import '../../models/user_profile.dart';
import '../../repositories/history_repository.dart';
import '../../services/auth_service.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/common/app_image.dart';
import '../../widgets/lenz/lenz.dart';
import '../../widgets/ui/ui.dart';
import '../paywall/guest_paywall_screen.dart';
import '../../services/haptics.dart';
import 'profile_sheet_parts.dart';
import 'scan_credits_sheet.dart';

/// Profile tab (prototype `SCREENS.profile`, mood `pleased`).
class ProfileScreen extends StatelessWidget {
  final VoidCallback onOpenPremium;
  final VoidCallback? onOpenSettings;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenHelp;
  final VoidCallback onOpenCredits;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenGuestPaywall;
  final VoidCallback? onOpenTerms;

  const ProfileScreen({
    super.key,
    required this.onOpenPremium,
    this.onOpenSettings,
    required this.onOpenPrivacy,
    required this.onOpenHelp,
    required this.onOpenCredits,
    this.onOpenHistory,
    this.onOpenFavorites,
    this.onOpenGuestPaywall,
    this.onOpenTerms,
  });

  Future<void> _pickAvatar(
    BuildContext context,
    ProfileViewModel profileVm,
    ImageSource source,
  ) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (picked == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final avatarFile = File('${appDir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(picked.path).copy(avatarFile.path);

      await profileVm.updateAvatar(avatarFile.path);

      if (context.mounted) {
        Haptics.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated successfully!'),
            duration: Duration(seconds: 2),
            backgroundColor: LenzColors.forest,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update profile photo: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showAvatarPickerSheet(BuildContext context, ProfileViewModel profileVm) {
    Haptics.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => LenzSheetFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Profile photo', textAlign: TextAlign.center, style: LenzText.title),
            const SizedBox(height: 4),
            Text(
              'Select an image from camera or gallery',
              textAlign: TextAlign.center,
              style: LenzText.sub.copyWith(fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            LenzSettingGroup(
              children: [
                LenzSettingRow(
                  icon: LenzIcons.camera,
                  title: 'Take photo',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _pickAvatar(context, profileVm, ImageSource.camera);
                  },
                ),
                LenzSettingRow(
                  icon: LenzIcons.image,
                  title: 'Choose from gallery',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _pickAvatar(context, profileVm, ImageSource.gallery);
                  },
                ),
                // Remove Custom Photo
                if (profileVm.user.avatarPath != null)
                  LenzSettingRow(
                    icon: LenzIcons.trash,
                    title: 'Use default mascot',
                    destructive: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      profileVm.updateAvatar(null);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile photo reset to default.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
              ],
            ),
            LenzButton(
              label: 'Cancel',
              variant: LenzButtonVariant.ghost,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProfileSheet(BuildContext context, ProfileViewModel profileVm) {
    Haptics.lightImpact();
    final nameController = TextEditingController(text: profileVm.user.name);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return LenzSheetFrame(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Transform.translate(
                  offset: const Offset(0, -6),
                  child: const SizedBox(
                    width: 150,
                    child: LenzCharacter(mood: LenzMood.hello, view: LenzView.bust),
                  ),
                ),
              ),
              Text('Edit profile', textAlign: TextAlign.center, style: LenzText.title),
              const SizedBox(height: 14),

              // Avatar preview with change-photo tap
              Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showAvatarPickerSheet(context, profileVm);
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: LenzColors.mint,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: LenzShadows.sh1,
                        ),
                        child: ClipOval(
                          child: _buildAvatarImage(profileVm.user.avatarPath, peekWidth: 96),
                        ),
                      ),
                      const Positioned(
                        right: -2,
                        bottom: 0,
                        child: _EditBadge(size: 28, icon: LenzIcons.camera),
                      ),
                    ],
                  ),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _showAvatarPickerSheet(context, profileVm);
                  },
                  child: Text(
                    'Change profile photo',
                    style: LenzText.link.copyWith(color: LenzColors.forest),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              LenzField(
                controller: nameController,
                hint: 'Full name',
                icon: LenzIcons.user,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),

              // Save
              LenzButton(
                label: 'Save changes',
                onPressed: () async {
                  final newName = nameController.text.trim();
                  if (newName.isEmpty) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Name cannot be empty')));
                    return;
                  }
                  Navigator.of(ctx).pop();
                  // Email is tied to the sign-in account and is
                  // deliberately not editable here - only name/photo.
                  await profileVm.updateProfile(name: newName);
                  Haptics.mediumImpact();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated successfully!'),
                        duration: Duration(seconds: 2),
                        backgroundColor: LenzColors.forest,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    Haptics.heavyImpact();
    showLenzConfirm(
      context,
      title: 'Log out?',
      text: 'Are you sure you want to log out and clear your active session?',
      okLabel: 'Log out',
      danger: true,
      character: (_) => const LenzCharacter(mood: LenzMood.sorry, view: LenzView.bust),
      onOk: () {
        // Local-cache clearing (reports/collection/categories/cached
        // profile) happens centrally in main.dart's sign-out handler,
        // triggered once AuthService's uid actually goes null below -
        // not duplicated here. Fire-and-forget (not awaited) so this
        // stays synchronous with the snackbar below - by the time sign
        // out completes and the app reroutes to sign-in, the user has
        // already seen their confirmation.
        context.read<AuthService>().signOut();
        Haptics.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logged out. Session cleared.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
    );
  }

  /// Required by Apple Guideline 5.1.1(v): any app that lets a user create an
  /// account must let them delete it from within the app. Confirms first
  /// (irreversible), then delegates to `AuthService.deleteAccount()`, which
  /// wipes Firestore/Cloudinary data and the Auth account server-side and
  /// signs out locally on success - the app's existing auth-state routing
  /// then takes the user back to the sign-in/onboarding screen on its own,
  /// the same way `_showLogoutDialog` above does.
  void _showDeleteAccountDialog(BuildContext context) {
    Haptics.heavyImpact();
    showLenzConfirm(
      context,
      title: 'Delete account?',
      text: 'This permanently deletes your account and all your scan reports and favorites. This cannot be undone.',
      okLabel: 'Delete account',
      danger: true,
      character: (_) => const LenzCharacter(mood: LenzMood.shocked, view: LenzView.bust),
      onOk: () => _handleDeleteAccount(context),
    );
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    final authService = context.read<AuthService>();

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: LenzColors.scrim,
      builder: (_) => Center(
        child: LenzCard(
          radius: LenzRadii.item,
          padding: const EdgeInsets.all(22),
          child: const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3, color: LenzColors.forest),
          ),
        ),
      ),
    );

    final error = await authService.deleteAccount();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading indicator

    if (error != null) {
      Haptics.mediumImpact();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error), duration: const Duration(seconds: 3)));
      return;
    }

    Haptics.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account deleted.'), duration: Duration(seconds: 2)),
    );
  }

  /// Name shown under the avatar. Same resolution order as before: the
  /// profile name, else the Firebase display name, else a capitalised email
  /// prefix, else "Apple User" / "Collector" (private-relay Apple addresses
  /// never leak into the name).
  static String _displayName(UserProfile user, User? authUser, bool isGuest) {
    bool isPlaceholder(String n) => n.isEmpty || n == 'Collector' || n == 'Guest Collector';

    if (isGuest) {
      return !isPlaceholder(user.name) ? user.name : 'Guest Collector';
    }

    final email = user.email;
    final emailPrefix = email.contains('@') ? email.split('@').first.toLowerCase() : '';
    if (!isPlaceholder(user.name) &&
        (!email.toLowerCase().contains('privaterelay.appleid.com') ||
            user.name.toLowerCase() != emailPrefix)) {
      return user.name;
    }

    final authEmail = authUser?.email ?? '';
    final authPrefix = authEmail.contains('@') ? authEmail.split('@').first.toLowerCase() : '';
    final displayName = authUser?.displayName;
    if (displayName?.isNotEmpty == true &&
        !isPlaceholder(displayName!) &&
        (!authEmail.toLowerCase().contains('privaterelay.appleid.com') ||
            displayName.toLowerCase() != authPrefix)) {
      return displayName;
    }

    if (authUser?.email?.contains('@') == true &&
        !authUser!.email!.toLowerCase().contains('privaterelay.appleid.com')) {
      final prefix = authUser.email!.split('@').first;
      return prefix.isNotEmpty ? prefix[0].toUpperCase() + prefix.substring(1) : 'Collector';
    }
    return authUser?.providerData.any((p) => p.providerId == 'apple.com') == true
        ? 'Apple User'
        : 'Collector';
  }

  @override
  Widget build(BuildContext context) {
    final profileVm = context.watch<ProfileViewModel>();
    final historyRepo = context.watch<HistoryRepository>();
    final authService = context.watch<AuthService>();
    final user = profileVm.user;
    final isGuest = authService.isAnonymous;
    final isPro = user.isPremium;

    final allReports = historyRepo.allReports;
    final totalReports = allReports.length;
    final authenticReports = allReports.where((r) => r.verdict == Verdict.likelyAuthentic).length;
    final replicaReports = allReports.where((r) => r.verdict == Verdict.likelyReplica).length;

    // Guest scans are not kept in History, so the guest balance comes from the
    // scan balance itself, not from counting saved reports.
    final remainingGuestScans = user.scansRemaining.clamp(0, kGuestScanAllowance);
    final name = _displayName(user, authService.currentUser, isGuest);

    final proLabel = user.planName.toUpperCase().contains('YEARLY') ? 'Yearly Pro' : 'Monthly Pro';

    return Scaffold(
      backgroundColor: LenzColors.ivory,
      body: Stack(
        children: [
          const LenzBlob(color: Color(0xFFD9ECDF)),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 6, 20, LenzTabBar.contentPadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ─── Header: avatar + name + email + plan pill
                  LenzRise(
                    child: _ProfileHeader(
                      avatar: _buildAvatarImage(user.avatarPath),
                      name: name,
                      subtitle: isGuest
                          ? 'Guest account'
                          : (user.email.isNotEmpty ? user.email : 'No email added'),
                      pill: isPro
                          ? LenzPill(
                              label: proLabel,
                              variant: LenzPillVariant.gold,
                              icon: LenzIcons.crown,
                            )
                          : LenzPill(
                              label: isGuest ? 'Guest' : 'Free plan',
                              icon: isGuest ? LenzIcons.user : LenzIcons.sparkles,
                            ),
                      onAvatarTap: () => _showAvatarPickerSheet(context, profileVm),
                      onNameTap: () => _showEditProfileSheet(context, profileVm),
                    ),
                  ),
                  const SizedBox(height: 18),
                  LenzStagger(
                    startIndex: 1,
                    children: [
                      // ─── Scan credits card
                      _CreditsCard(
                        pro: isPro,
                        left: isGuest ? remainingGuestScans : user.scansRemaining,
                        allowance: isGuest ? kGuestScanAllowance : kAccountScanAllowance,
                        title: isPro ? 'Unlimited scans' : 'Scan credits',
                        subtitle: isPro
                            ? '${user.planName} is active. Check as much as you like.'
                            : isGuest
                            ? '$remainingGuestScans left of 3 guest scans.'
                            : '${user.scansRemaining} free scans left.',
                        onTap: onOpenCredits,
                      ),

                      // ─── Guests: account creation (never Pro)
                      if (isGuest)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _GuestPromoCard(
                            onTap: () {
                              if (onOpenGuestPaywall != null) {
                                onOpenGuestPaywall!();
                              } else {
                                GuestPaywallScreen.show(context);
                              }
                            },
                          ),
                        )
                      else if (!isPro)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: LenzButton(
                            label: 'Upgrade to Lenz Pro',
                            variant: LenzButtonVariant.gold,
                            icon: LenzIcons.crown,
                            onPressed: onOpenPremium,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: LenzButton(
                            label: 'Manage subscription',
                            variant: LenzButtonVariant.ghost,
                            icon: LenzIcons.crown,
                            onPressed: onOpenPremium,
                          ),
                        ),

                      // ─── Stats (Reports | Authentic | Replica)
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: _StatTile(count: totalReports, label: 'Reports'),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StatTile(count: authenticReports, label: 'Authentic'),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StatTile(count: replicaReports, label: 'Replica'),
                            ),
                          ],
                        ),
                      ),

                      // ─── Menu: history + favorites
                      LenzSettingGroup(
                        children: [
                          LenzSettingRow(
                            icon: LenzIcons.clock,
                            title: 'Scan history',
                            subtitle: 'View your past scans',
                            onTap: onOpenHistory ?? () {},
                          ),
                          LenzSettingRow(
                            icon: LenzIcons.heart,
                            title: 'Favorites',
                            subtitle: 'Reports you\'ve marked as favorites',
                            onTap: onOpenFavorites ?? () {},
                          ),
                        ],
                      ),

                      // ─── Support
                      LenzSettingGroup(
                        children: [
                          LenzSettingRow(
                            icon: LenzIcons.help,
                            title: 'Help and support',
                            subtitle: 'Get help or contact us',
                            onTap: onOpenHelp,
                          ),
                          LenzSettingRow(
                            icon: LenzIcons.shield,
                            title: 'Privacy and security',
                            subtitle: 'Learn how your data is protected',
                            onTap: onOpenPrivacy,
                          ),
                          if (onOpenTerms != null)
                            LenzSettingRow(
                              icon: LenzIcons.file,
                              title: 'Terms of service',
                              subtitle: 'Read our usage and subscription terms',
                              onTap: onOpenTerms!,
                            ),
                        ],
                      ),

                      // ─── Log out + Delete account (Guideline 5.1.1(v)).
                      // A guest has no account and nothing stored, so neither
                      // applies: guests create or sign in from the card above.
                      if (!isGuest) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: LenzButton(
                            label: 'Log out',
                            variant: LenzButtonVariant.ghost,
                            icon: LenzIcons.logout,
                            onPressed: () => _showLogoutDialog(context),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: LenzButton(
                            label: 'Delete account',
                            variant: LenzButtonVariant.danger,
                            icon: LenzIcons.trash,
                            onPressed: () => _showDeleteAccountDialog(context),
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          'Lenz · Verado Studio',
                          textAlign: TextAlign.center,
                          style: LenzText.tiny,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the user's avatar. Handles a network URL (Google profile photo,
  /// Cloudinary-hosted photo) as well as a local file path (camera/gallery
  /// pick) via the shared AppImage widget. With no avatar, Lenz peeks into
  /// the circle (prototype `peek` crop).
  Widget _buildAvatarImage(String? avatarPath, {double peekWidth = 140}) {
    final peek = _LenzPeek(width: peekWidth);
    if (avatarPath != null && avatarPath.isNotEmpty) {
      return AppImage(imagePath: avatarPath, fit: BoxFit.cover, placeholder: peek);
    }
    return peek;
  }
}

/// Lenz `peek` crop sized like the prototype avatar
/// (`width:140px;margin:-8px 0 0 -12px` inside a 116px circle).
class _LenzPeek extends StatelessWidget {
  const _LenzPeek({this.width = 140});

  final double width;

  @override
  Widget build(BuildContext context) {
    final k = width / 140;
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: width,
      maxWidth: width,
      maxHeight: double.infinity,
      child: Transform.translate(
        offset: Offset(-12 * k, -8 * k),
        child: SizedBox(
          width: width,
          child: const LenzCharacter(
            mood: LenzMood.pleased,
            view: LenzView.peek,
            fx: false,
            interactive: false,
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.avatar,
    required this.name,
    required this.subtitle,
    required this.pill,
    required this.onAvatarTap,
    required this.onNameTap,
  });

  final Widget avatar;
  final String name;
  final String subtitle;
  final Widget pill;
  final VoidCallback onAvatarTap;
  final VoidCallback onNameTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(child: _DashedSpinRing()),
              Positioned(
                left: 8,
                top: 8,
                child: LenzPressable(
                  onTap: onAvatarTap,
                  semanticLabel: 'Change profile photo',
                  child: Container(
                    width: 116,
                    height: 116,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: LenzColors.mint,
                      boxShadow: LenzShadows.sh2,
                    ),
                    foregroundDecoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 5),
                    ),
                    child: ClipOval(child: avatar),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                bottom: 10,
                child: GestureDetector(
                  onTap: onNameTap,
                  child: const _EditBadge(size: 34, icon: LenzIcons.edit),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onNameTap,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LenzText.display.copyWith(fontSize: 27),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onNameTap,
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LenzText.sub,
          ),
        ),
        const SizedBox(height: 8),
        pill,
      ],
    );
  }
}

class _EditBadge extends StatelessWidget {
  const _EditBadge({required this.size, required this.icon});

  final double size;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: LenzColors.forest,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      alignment: Alignment.center,
      child: LenzIcon(icon, size: size * .44, strokeWidth: 2.4, color: Colors.white),
    );
  }
}

/// The prototype's 3px dashed ring around the avatar, spinning once per 20s
/// (`animation:spin 20s linear infinite`). Static when motion is reduced.
class _DashedSpinRing extends StatefulWidget {
  const _DashedSpinRing();

  @override
  State<_DashedSpinRing> createState() => _DashedSpinRingState();
}

class _DashedSpinRingState extends State<_DashedSpinRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (LenzMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: RotationTransition(
        turns: _c,
        child: const CustomPaint(painter: _DashedCirclePainter()),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final r = size.shortestSide / 2 - stroke / 2;
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = const Color.fromRGBO(18, 47, 36, .2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    // Browser-like dashes: ~9px dash, ~6px gap.
    final circumference = 2 * math.pi * r;
    final n = (circumference / 15).floor();
    final sweep = 2 * math.pi / n;
    final dash = sweep * .6;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < n; i++) {
      canvas.drawArc(rect, i * sweep, dash, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) => false;
}

class _CreditsCard extends StatelessWidget {
  const _CreditsCard({
    required this.pro,
    required this.left,
    required this.allowance,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool pro;
  final int left;
  final int allowance;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = left < 0 ? 0 : left;
    return LenzCard(
      radius: 30,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          LenzRing(
            value: pro ? 1 : (n / allowance).clamp(0.0, 1.0),
            size: 76,
            strokeWidth: 9,
            color: pro ? LenzColors.gold : LenzColors.leaf,
            child: pro
                ? const LenzInfinityGlyph(width: 30)
                : FittedBox(
                    child: AnimatedCount(to: n, style: _ringNumber.copyWith(fontSize: 22)),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: LenzText.family,
                    color: LenzColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(subtitle, style: LenzText.sub.copyWith(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const LenzIcon(LenzIcons.chevR, size: 18, color: LenzColors.ink),
        ],
      ),
    );
  }
}

const TextStyle _ringNumber = TextStyle(
  fontFamily: LenzText.family,
  color: LenzColors.ink,
  fontSize: 24,
  fontWeight: FontWeight.w900,
  height: 1,
);

/// The prototype's dark `.promo` strip (gold hairline + shimmer) for guests:
/// save their scans and get account scans by creating an account.
class _GuestPromoCard extends StatefulWidget {
  const _GuestPromoCard({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_GuestPromoCard> createState() => _GuestPromoCardState();
}

class _GuestPromoCardState extends State<_GuestPromoCard> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (LenzMotion.reduced(context)) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LenzPressable(
      onTap: widget.onTap,
      semanticLabel: 'Sign In / Create Account',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LenzGradients.promo,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color.fromRGBO(212, 175, 55, .45)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _shimmer,
                  builder: (context, _) {
                    // background-size 200%, position 200% -> -200%.
                    final x = 1 - 2 * _shimmer.value;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1 + x * 2, -.4),
                          end: Alignment(1 + x * 2, .4),
                          colors: const [Color(0x00F4D97B), Color(0x47F4D97B), Color(0x00F4D97B)],
                          stops: const [.3, .5, .7],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromRGBO(244, 217, 123, .2),
                        ),
                        alignment: Alignment.center,
                        child: const LenzIcon(LenzIcons.gift, size: 22, color: LenzColors.gold2),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Save your scans with an account',
                              style: TextStyle(
                                fontFamily: LenzText.family,
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Sign in with Google or Email to keep your scans and get your account\'s free scans.',
                              style: TextStyle(
                                fontFamily: LenzText.family,
                                color: Color(0xFFBCD0C4),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LenzButton(
                    label: 'Sign In / Create Account',
                    variant: LenzButtonVariant.light,
                    size: LenzButtonSize.sm,
                    onPressed: widget.onTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return LenzCard(
      radius: LenzRadii.stat,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCount(to: count, style: LenzText.stat),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, maxLines: 1, style: LenzText.statLabel),
          ),
        ],
      ),
    );
  }
}
