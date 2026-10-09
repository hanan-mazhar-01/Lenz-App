import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../services/revenue_cat_service.dart';

class ProfileViewModel extends ChangeNotifier {
  static const String _keyName = 'user_profile_name';
  static const String _keyEmail = 'user_profile_email';
  static const String _keyAvatar = 'user_profile_avatar';
  static const String _keyIsPremium = 'user_profile_is_premium';
  static const String _keyPlanName = 'user_profile_plan_name';
  static const String _keyScansRemaining = 'user_profile_scans_remaining';

  StreamSubscription<DocumentSnapshot>? _firestoreSub;
  StreamSubscription<User?>? _authSub;
  VoidCallback? _revenueCatListener;

  UserProfile _user = const UserProfile(
    name: 'Collector',
    email: '',
    planName: 'Free Plan',
    scansRemaining: 3,
    isPremium: false,
  );

  UserProfile get user {
    final rcActive = RevenueCatService.isPremiumNotifier.value;
    if (rcActive && !_user.isPremium) {
      final rcPlan = RevenueCatService.activePlanNotifier.value ?? 'Lenz Pro';
      return _user.copyWith(
        isPremium: true,
        planName: rcPlan,
      );
    }
    return _user;
  }

  bool get isPremium => _user.isPremium || RevenueCatService.isPremiumNotifier.value;

  ProfileViewModel() {
    _loadProfile();
    _listenToAuthAndFirestore();
    _listenToRevenueCat();
  }

  void _listenToRevenueCat() {
    _revenueCatListener = () {
      final isRcPro = RevenueCatService.isPremiumNotifier.value;
      final rcPlan = RevenueCatService.activePlanNotifier.value ?? 'Lenz Pro';
      if (isRcPro) {
        _user = _user.copyWith(
          isPremium: true,
          planName: rcPlan,
        );
        _persistPremium(true, rcPlan);
        notifyListeners();
      } else if (!isRcPro && _user.isPremium && (_user.planName.contains('Pro') || _user.planName.contains('Premium'))) {
        _user = _user.copyWith(
          isPremium: false,
          planName: 'Free Plan',
        );
        _persistPremium(false, 'Free Plan');
        notifyListeners();
      }
    };
    RevenueCatService.isPremiumNotifier.addListener(_revenueCatListener!);

    // Where RevenueCat is actually wired up (Apple platforms), it's
    // authoritative: sync to its live value in both directions at startup.
    // Only ever upgrading a stale cached "false" (and never correcting a
    // stale cached "true") is how a lapsed subscription on a device RC
    // hasn't refreshed yet can keep showing Premium indefinitely. On
    // platforms RC isn't configured for, leave the cached/Firestore value
    // alone instead of forcing it to "not premium".
    if (RevenueCatService.isSupportedPlatform) {
      final isRcPro = RevenueCatService.isPremiumNotifier.value;
      if (isRcPro) {
        final rcPlan = RevenueCatService.activePlanNotifier.value ?? 'Lenz Pro';
        _user = _user.copyWith(isPremium: true, planName: rcPlan);
        _persistPremium(true, rcPlan);
      } else if (_user.isPremium) {
        _user = _user.copyWith(isPremium: false, planName: 'Free Plan');
        _persistPremium(false, 'Free Plan');
      }
    }
  }

  void _listenToAuthAndFirestore() {
    try {
      if (Firebase.apps.isEmpty) return;
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        _firestoreSub?.cancel();
        if (user != null) {
          final authName = user.displayName?.trim();
          if (authName != null &&
              authName.isNotEmpty &&
              authName != 'Collector' &&
              authName != 'Guest Collector') {
            _user = _user.copyWith(name: authName);
            notifyListeners();
          }

          _firestoreSub = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots()
              .listen((snapshot) {
            if (snapshot.exists) {
              final data = snapshot.data();
              if (data != null) {
                final firestoreName = (data['name'] as String?)?.trim();
                final currentAuthUser = FirebaseAuth.instance.currentUser;
                final currentAuthName = currentAuthUser?.displayName?.trim();

                final email = (data['email'] as String?) ?? currentAuthUser?.email ?? '';
                final isPrivateRelay = email.toLowerCase().contains('privaterelay.appleid.com');
                final emailPrefix = email.contains('@') ? email.split('@').first.trim().toLowerCase() : '';

                String resolvedName;
                if (firestoreName != null &&
                    firestoreName.isNotEmpty &&
                    firestoreName != 'Collector' &&
                    firestoreName != 'Guest Collector' &&
                    (!isPrivateRelay || firestoreName.toLowerCase() != emailPrefix)) {
                  resolvedName = firestoreName;
                } else if (currentAuthName != null &&
                    currentAuthName.isNotEmpty &&
                    currentAuthName != 'Collector' &&
                    currentAuthName != 'Guest Collector' &&
                    (!isPrivateRelay || currentAuthName.toLowerCase() != emailPrefix)) {
                  resolvedName = currentAuthName;
                  _syncFirestoreProfile({'name': currentAuthName});
                } else if (currentAuthUser != null &&
                    !currentAuthUser.isAnonymous &&
                    currentAuthUser.email != null &&
                    currentAuthUser.email!.contains('@') &&
                    !isPrivateRelay) {
                  final prefix = currentAuthUser.email!.split('@').first.trim();
                  resolvedName = prefix.isNotEmpty
                      ? (prefix[0].toUpperCase() + prefix.substring(1))
                      : _user.name;
                  _syncFirestoreProfile({'name': resolvedName});
                } else {
                  final isApple = currentAuthUser?.providerData.any((p) => p.providerId == 'apple.com') == true;
                  resolvedName = user.isAnonymous
                      ? 'Guest Collector'
                      : (isApple ? 'Apple User' : 'Collector');
                  if (firestoreName != null && isPrivateRelay && firestoreName.toLowerCase() == emailPrefix) {
                    _syncFirestoreProfile({'name': resolvedName});
                  }
                }

                final firestoreIsPremium = data['isPremium'] as bool? ?? false;
                final isProActive = firestoreIsPremium || RevenueCatService.isPremiumNotifier.value;
                final rcPlan = RevenueCatService.activePlanNotifier.value;

                _user = _user.copyWith(
                  name: resolvedName,
                  email: (data['email'] as String?)?.isNotEmpty == true
                      ? data['email'] as String
                      : (currentAuthUser?.email ?? _user.email),
                  planName: isProActive
                      ? (rcPlan ?? (data['planName'] as String?) ?? 'Lenz Pro')
                      : (data['planName'] as String? ?? _user.planName),
                  isPremium: isProActive,
                  scansRemaining: (data['scansRemaining'] as num?)?.toInt() ??
                      _user.scansRemaining,
                  avatarPath: data['avatarUrl'] as String? ?? _user.avatarPath,
                );
                notifyListeners();
              }
            }
          }, onError: (e) {
            if (kDebugMode) debugPrint('[ProfileViewModel] Firestore listen error: $e');
          });
        }
      });
    } catch (_) {
      // Ignored for tests where Firebase is not initialized
    }
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString(_keyName);
      final savedEmail = prefs.getString(_keyEmail);
      final savedAvatar = prefs.getString(_keyAvatar);
      final savedIsPremium = prefs.getBool(_keyIsPremium) ?? false;
      final savedPlanName = prefs.getString(_keyPlanName);
      final savedScans = prefs.getInt(_keyScansRemaining);
      // Where RevenueCat is wired up, it's the sole authority on premium
      // access — OR-ing in the local cache here would mean a lapsed
      // subscription that was last synced as "premium" keeps showing
      // Premium forever on a device RC hasn't refreshed yet, since OR
      // never lets a live "false" override a stale cached "true". Where
      // RC isn't configured (non-Apple platforms), fall back to the cache.
      final effectiveIsPremium = RevenueCatService.isSupportedPlatform
          ? RevenueCatService.isPremiumNotifier.value
          : savedIsPremium;
      final rcPlan = RevenueCatService.activePlanNotifier.value;

      _user = _user.copyWith(
        name: (savedName != null && savedName.trim().isNotEmpty) ? savedName : _user.name,
        email: (savedEmail != null && savedEmail.trim().isNotEmpty) ? savedEmail : _user.email,
        avatarPath: savedAvatar,
        scansRemaining: savedScans ?? _user.scansRemaining,
        isPremium: effectiveIsPremium,
        planName: effectiveIsPremium ? (rcPlan ?? savedPlanName ?? 'Lenz Pro') : _user.planName,
      );
      notifyListeners();
    } catch (_) {}
  }

  void _syncFirestoreProfile(Map<String, dynamic> fields) {
    try {
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      // Exclude isPremium and scansRemaining from client writes to obey Firestore rules
      fields.remove('isPremium');
      fields.remove('scansRemaining');
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(fields, SetOptions(merge: true))
          .catchError((e) {
        if (kDebugMode) debugPrint('[ProfileViewModel] Sync error: $e');
      });
    } catch (_) {}
  }

  /// Clears the cached name/email/avatar this device remembers for whoever
  /// was last signed in. Called on sign-out AND account deletion, so the
  /// next account to sign in on this device never briefly (or permanently,
  /// if Firestore sync is slow/offline) shows the previous user's cached
  /// profile info instead of its own.
  Future<void> clearCachedProfile() async {
    _user = const UserProfile(
      name: 'Collector',
      email: '',
      planName: 'Free Plan',
      scansRemaining: 3,
      isPremium: false,
    );
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyName);
      await prefs.remove(_keyEmail);
      await prefs.remove(_keyAvatar);
      await prefs.remove(_keyIsPremium);
      await prefs.remove(_keyPlanName);
      await prefs.remove(_keyScansRemaining);
    } catch (_) {}
  }

  /// Sets premium status locally and persists it.
  void setPremiumStatus(bool isPremium, {String? planName}) {
    final effectivePlan = planName ?? (isPremium ? 'Lenz Pro' : 'Free Plan');
    _user = _user.copyWith(
      isPremium: isPremium,
      planName: effectivePlan,
    );
    _persistPremium(isPremium, effectivePlan);
    RevenueCatService.isPremiumNotifier.value = isPremium;
    notifyListeners();
  }

  /// Updates the plan name display (e.g. 'Free Plan', 'Monthly Pro', 'Yearly Pro').
  void setPlanName(String planName) {
    _user = _user.copyWith(planName: planName);
    notifyListeners();
  }

  /// Updates the available free scans remaining.
  void setScansRemaining(int count) {
    _user = _user.copyWith(scansRemaining: count);
    _persistScansRemaining(count);
    notifyListeners();
  }

  /// Decrements one scan credit when a non-premium scan completes.
  void decrementScanCount() {
    if (isPremium) return;
    final updated = (_user.scansRemaining - 1).clamp(0, 9999);
    _user = _user.copyWith(scansRemaining: updated);
    _persistScansRemaining(updated);
    notifyListeners();
  }

  Future<void> _persistScansRemaining(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyScansRemaining, count);
    } catch (_) {}
  }

  Future<void> _persistPremium(bool isPremium, String planName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsPremium, isPremium);
      await prefs.setString(_keyPlanName, planName);
    } catch (_) {}
  }

  Future<void> updateAvatar(String? path) async {
    _user = _user.copyWith(
      avatarPath: path,
      clearAvatar: path == null,
    );
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (path != null && path.isNotEmpty) {
        await prefs.setString(_keyAvatar, path);
        _syncFirestoreProfile({'avatarUrl': path});
      } else {
        await prefs.remove(_keyAvatar);
        _syncFirestoreProfile({'avatarUrl': ''});
      }
    } catch (_) {}
  }

  Future<void> updateProfile({
    String? name,
    String? email,
    String? avatarPath,
    bool clearAvatar = false,
  }) async {
    String? updatedName;
    if (name != null && name.trim().isNotEmpty) {
      updatedName = name.trim();
    }
    String? updatedEmail;
    if (email != null && email.trim().isNotEmpty) {
      updatedEmail = email.trim();
    }

    _user = _user.copyWith(
      name: updatedName ?? _user.name,
      email: updatedEmail ?? _user.email,
      avatarPath: clearAvatar ? null : (avatarPath ?? _user.avatarPath),
      clearAvatar: clearAvatar,
    );
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final mapToSync = <String, dynamic>{};
      if (updatedName != null) {
        await prefs.setString(_keyName, updatedName);
        mapToSync['name'] = updatedName;
      }
      if (updatedEmail != null) {
        await prefs.setString(_keyEmail, updatedEmail);
        mapToSync['email'] = updatedEmail;
      }
      if (clearAvatar) {
        await prefs.remove(_keyAvatar);
        mapToSync['avatarUrl'] = '';
      } else if (avatarPath != null) {
        await prefs.setString(_keyAvatar, avatarPath);
        mapToSync['avatarUrl'] = avatarPath;
      }

      if (mapToSync.isNotEmpty) {
        _syncFirestoreProfile(mapToSync);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_revenueCatListener != null) {
      RevenueCatService.isPremiumNotifier.removeListener(_revenueCatListener!);
    }
    _firestoreSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
