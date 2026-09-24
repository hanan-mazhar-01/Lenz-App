import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/authentication_result.dart';
import '../../repositories/history_repository.dart';
import '../../services/auth_service.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../../widgets/animations/bounce_button.dart';
import '../../widgets/animations/fade_slide_transition.dart';
import '../../widgets/common/app_image.dart';
import '../paywall/guest_paywall_screen.dart';
import '../../services/haptics.dart';

class ProfileScreen extends StatelessWidget {
  final VoidCallback onOpenPremium;
  final VoidCallback onOpenCollection;
  final VoidCallback? onOpenSettings;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenHelp;
  final VoidCallback onOpenCredits;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSaved;
  final VoidCallback? onOpenGuestPaywall;

  const ProfileScreen({
    super.key,
    required this.onOpenPremium,
    required this.onOpenCollection,
    this.onOpenSettings,
    required this.onOpenPrivacy,
    required this.onOpenHelp,
    required this.onOpenCredits,
    this.onOpenHistory,
    this.onOpenSaved,
    this.onOpenGuestPaywall,
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
      final avatarFile = File(
        '${appDir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(picked.path).copy(avatarFile.path);

      await profileVm.updateAvatar(avatarFile.path);

      if (context.mounted) {
        Haptics.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated successfully!'),
            duration: Duration(seconds: 2),
            backgroundColor: AppColors.deepForestGreen,
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
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.warmIvory,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppColors.nearBlack.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Profile Photo',
              style: TextStyle(
                color: AppColors.nearBlack,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select an image from camera or gallery',
              style: TextStyle(
                color: AppColors.charcoalGray,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 18),

            // Camera
            _buildActionSheetOption(
              icon: CupertinoIcons.camera_fill,
              label: 'Take Photo',
              onTap: () async {
                Navigator.of(ctx).pop();
                await _pickAvatar(context, profileVm, ImageSource.camera);
              },
            ),
            const SizedBox(height: 10),

            // Gallery
            _buildActionSheetOption(
              icon: CupertinoIcons.photo_fill,
              label: 'Choose from Gallery',
              onTap: () async {
                Navigator.of(ctx).pop();
                await _pickAvatar(context, profileVm, ImageSource.gallery);
              },
            ),

            // Remove Custom Photo
            if (profileVm.user.avatarPath != null) ...[
              const SizedBox(height: 10),
              _buildActionSheetOption(
                icon: CupertinoIcons.trash,
                label: 'Use Default Mascot',
                isDestructive: true,
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
            const SizedBox(height: 14),

            // Cancel
            BounceButton(
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.veryLightWarmGray,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.nearBlack.withOpacity(0.06)),
                ),
                child: const Center(
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppColors.nearBlack,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
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
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
            decoration: const BoxDecoration(
              color: AppColors.warmIvory,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: AppColors.nearBlack.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Profile',
                          style: TextStyle(
                            color: AppColors.nearBlack,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded, color: AppColors.charcoalGray),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Avatar Preview with Change Photo tap
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.veryLightWarmGray,
                              border: Border.all(
                                color: AppColors.nearBlack.withOpacity(0.08),
                                width: 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: _buildAvatarImage(profileVm.user.avatarPath),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _showAvatarPickerSheet(context, profileVm);
                              },
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: AppColors.deepForestGreen,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.warmIvory,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showAvatarPickerSheet(context, profileVm);
                        },
                        child: const Text(
                          'Change Profile Photo',
                          style: TextStyle(
                            color: AppColors.deepForestGreen,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Full Name Field
                    const Text(
                      'Full Name',
                      style: TextStyle(
                        color: AppColors.charcoalGray,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.veryLightWarmGray,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.nearBlack.withOpacity(0.08)),
                      ),
                      child: TextField(
                        controller: nameController,
                        style: const TextStyle(
                          color: AppColors.nearBlack,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter your name',
                          hintStyle: TextStyle(color: AppColors.softGray),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          border: InputBorder.none,
                          prefixIcon: Icon(CupertinoIcons.person, color: AppColors.deepForestGreen, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    BounceButton(
                      onTap: () async {
                        final newName = nameController.text.trim();
                        if (newName.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Name cannot be empty')),
                          );
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
                              backgroundColor: AppColors.deepForestGreen,
                            ),
                          );
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: AppColors.deepForestGreen,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.deepForestGreen.withOpacity(0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Save Changes',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    Haptics.heavyImpact();
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Log Out'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Are you sure you want to log out and clear your active session?',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Log Out'),
            onPressed: () {
              Navigator.of(ctx).pop();
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
          ),
        ],
      ),
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
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Account'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'This permanently deletes your account, scan reports, and collection. This cannot be undone.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete Account'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _handleDeleteAccount(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    final authService = context.read<AuthService>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CupertinoActivityIndicator(radius: 16, color: CupertinoColors.white),
      ),
    );

    final error = await authService.deleteAccount();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading indicator

    if (error != null) {
      Haptics.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 3)),
      );
      return;
    }

    Haptics.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account deleted.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileVm = context.watch<ProfileViewModel>();
    final historyRepo = context.watch<HistoryRepository>();
    final authService = context.watch<AuthService>();
    final user = profileVm.user;
    final isGuest = authService.isAnonymous;

    final allReports = historyRepo.allReports;
    final totalReports = allReports.length;
    final authenticReports = allReports.where((r) => r.verdict == Verdict.likelyAuthentic).length;
    final replicaReports = allReports.where((r) => r.verdict == Verdict.likelyReplica).length;

    final remainingGuestScans = 3 - (totalReports > 3 ? 3 : totalReports);

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // ─── 1. Header: Avatar + User Info + Edit
              FadeSlideTransition(
                delay: const Duration(milliseconds: 40),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar with edit badge
                    BounceButton(
                      onTap: () => _showAvatarPickerSheet(context, profileVm),
                      child: Stack(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.veryLightWarmGray,
                              border: Border.all(
                                color: AppColors.nearBlack.withValues(alpha: 0.08),
                                width: 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: _buildAvatarImage(user.avatarPath),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: AppColors.deepForestGreen,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.warmIvory,
                                  width: 2,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.camera_alt,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Name, Email, and Guest/Verified Status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BounceButton(
                            onTap: () => _showEditProfileSheet(context, profileVm),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    isGuest
                                        ? (user.name.isNotEmpty && user.name != 'Collector' && user.name != 'Guest Collector'
                                            ? user.name
                                            : 'Guest Collector')
                                        : (user.name.isNotEmpty && user.name != 'Collector' && user.name != 'Guest Collector'
                                            ? user.name
                                            : (authService.currentUser?.displayName?.isNotEmpty == true && authService.currentUser!.displayName != 'Collector'
                                                ? authService.currentUser!.displayName!
                                                : (authService.currentUser?.email?.contains('@') == true
                                                    ? (authService.currentUser!.email!.split('@').first.isNotEmpty
                                                        ? authService.currentUser!.email!.split('@').first[0].toUpperCase() + authService.currentUser!.email!.split('@').first.substring(1)
                                                        : 'Collector')
                                                    : 'Collector'))),
                                    style: const TextStyle(
                                      color: AppColors.nearBlack,
                                      fontSize: 19.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.all(3.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.veryLightWarmGray,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.nearBlack.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    size: 11,
                                    color: AppColors.charcoalGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (isGuest) ...[
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.nearBlack.withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.person_outline_rounded,
                                        size: 11,
                                        color: AppColors.charcoalGray,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Guest Account',
                                        style: TextStyle(
                                          color: AppColors.charcoalGray,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$remainingGuestScans left of 3',
                                  style: const TextStyle(
                                    color: AppColors.charcoalGray,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            GestureDetector(
                              onTap: () => _showEditProfileSheet(context, profileVm),
                              child: Text(
                                user.email.isNotEmpty ? user.email : 'No email added',
                                style: const TextStyle(
                                  color: AppColors.charcoalGray,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Guest Call-to-Action Banner Card ───
              if (isGuest) ...[
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 60),
                  child: Container(
                    margin: const EdgeInsets.only(top: 18),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.veryLightWarmGray,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.deepForestGreen.withValues(alpha: 0.16),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.nearBlack.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.deepForestGreen.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.verified_user_outlined,
                                size: 19,
                                color: AppColors.deepForestGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Save Scans & Get 5 Checks',
                                    style: TextStyle(
                                      color: AppColors.nearBlack,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Sign in with Google or Email to save your 3 scans and unlock more checks.',
                                    style: TextStyle(
                                      color: AppColors.charcoalGray,
                                      fontSize: 11.5,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        BounceButton(
                          onTap: () {
                            if (onOpenGuestPaywall != null) {
                              onOpenGuestPaywall!();
                            } else {
                              GuestPaywallScreen.show(context);
                            }
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.deepForestGreen,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.deepForestGreen.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'Sign In / Create Account',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // ─── 2. Stats Row Card (Reports | Authentic | Replica)
              FadeSlideTransition(
                delay: const Duration(milliseconds: 80),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.veryLightWarmGray,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.nearBlack.withOpacity(0.06),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.nearBlack.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Reports
                      Expanded(
                        child: _buildStatItem(
                          count: '$totalReports',
                          label: 'Reports',
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: AppColors.nearBlack.withOpacity(0.08),
                      ),
                      // Authentic
                      Expanded(
                        child: _buildStatItem(
                          count: '$authenticReports',
                          label: 'Authentic',
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: AppColors.nearBlack.withOpacity(0.08),
                      ),
                      // Replica
                      Expanded(
                        child: _buildStatItem(
                          count: '$replicaReports',
                          label: 'Replica',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ─── 3. Menu List Cards
              FadeSlideTransition(
                delay: const Duration(milliseconds: 120),
                child: Column(
                  children: [
                    // 1. Scan History
                    _buildMenuCard(
                      icon: Icons.history_rounded,
                      title: 'Scan History',
                      subtitle: 'View your past scans',
                      onTap: onOpenHistory ?? onOpenCollection,
                    ),

                    // 2. Saved Reports
                    _buildMenuCard(
                      icon: Icons.bookmark_border_rounded,
                      title: 'Saved Reports',
                      subtitle: 'Keep track of important results',
                      onTap: onOpenSaved ?? onOpenCollection,
                    ),

                    // 3. Help & Support
                    _buildMenuCard(
                      icon: Icons.help_outline_rounded,
                      title: 'Help & Support',
                      subtitle: 'Get help or contact us',
                      onTap: onOpenHelp,
                    ),

                    // 4. Privacy & Security
                    _buildMenuCard(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy & Security',
                      subtitle: 'Learn how your data is protected',
                      onTap: onOpenPrivacy,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ─── 4. Log Out Button
              FadeSlideTransition(
                delay: const Duration(milliseconds: 160),
                child: BounceButton(
                  onTap: () => _showLogoutDialog(context),
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.deepForestGreen,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.deepForestGreen.withOpacity(0.22),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.logout_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Log Out',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ─── 5. Delete Account (Guideline 5.1.1(v))
              FadeSlideTransition(
                delay: const Duration(milliseconds: 180),
                child: Center(
                  child: TextButton(
                    onPressed: () => _showDeleteAccountDialog(context),
                    child: const Text(
                      'Delete Account',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  /// Single Stat column (Count + Label)
  Widget _buildStatItem({required String count, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: const TextStyle(
            color: AppColors.nearBlack,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.charcoalGray,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Single card menu item
  Widget _buildMenuCard({
    required IconData icon,
    bool isIconAccent = false,
    required String title,
    required String subtitle,
    Color? subtitleColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.veryLightWarmGray,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.nearBlack.withOpacity(0.05),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Circular icon container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isIconAccent ? const Color(0xFFE2EDE6) : AppColors.softWarmGray,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 20,
                      color: isIconAccent ? AppColors.deepForestGreen : AppColors.nearBlack,
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // Title + Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.nearBlack,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2.5),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: subtitleColor ?? AppColors.charcoalGray,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Trailing Chevron
                const Icon(
                  CupertinoIcons.chevron_right,
                  size: 15,
                  color: AppColors.softGray,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Renders the user's avatar. Handles a network URL (Google profile photo,
  /// Cloudinary-hosted photo) as well as a local file path (camera/gallery
  /// pick) via the shared AppImage widget - a plain local-file check alone
  /// (the old implementation here) always failed for a network URL, since
  /// `File('https://...').existsSync()` is never true, silently falling
  /// back to the default mascot for every signed-in provider photo.
  Widget _buildAvatarImage(String? avatarPath) {
    if (avatarPath != null && avatarPath.isNotEmpty) {
      return AppImage(
        imagePath: avatarPath,
        fit: BoxFit.cover,
        placeholder: Image.asset('assets/images/mascot_home.png', fit: BoxFit.cover),
      );
    }
    return Image.asset(
      'assets/images/mascot_home.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        CupertinoIcons.person_fill,
        size: 38,
        color: AppColors.deepForestGreen,
      ),
    );
  }

  Widget _buildActionSheetOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Material(
      color: AppColors.veryLightWarmGray,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.nearBlack.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: isDestructive ? Colors.redAccent : AppColors.deepForestGreen,
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: isDestructive ? Colors.redAccent : AppColors.nearBlack,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
