import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class ProfileViewModel extends ChangeNotifier {
  static const String _keyName = 'user_profile_name';
  static const String _keyEmail = 'user_profile_email';
  static const String _keyAvatar = 'user_profile_avatar';

  StreamSubscription<DocumentSnapshot>? _firestoreSub;
  StreamSubscription<User?>? _authSub;

  UserProfile _user = const UserProfile(
    name: 'Collector',
    email: '',
    planName: 'Free Plan',
    scansRemaining: 5,
    isPremium: false,
  );

  UserProfile get user => _user;
  bool get isPremium => _user.isPremium;

  ProfileViewModel() {
    _loadProfile();
    _listenToAuthAndFirestore();
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

                _user = _user.copyWith(
                  name: resolvedName,
                  email: (data['email'] as String?)?.isNotEmpty == true
                      ? data['email'] as String
                      : (currentAuthUser?.email ?? _user.email),
                  planName: data['planName'] as String? ?? _user.planName,
                  isPremium: data['isPremium'] as bool? ?? _user.isPremium,
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

      _user = _user.copyWith(
        name: (savedName != null && savedName.trim().isNotEmpty) ? savedName : _user.name,
        email: (savedEmail != null && savedEmail.trim().isNotEmpty) ? savedEmail : _user.email,
        avatarPath: savedAvatar,
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
      scansRemaining: 5,
      isPremium: false,
    );
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyName);
      await prefs.remove(_keyEmail);
      await prefs.remove(_keyAvatar);
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

  // Real premium status only ever comes from Firestore (via the listener
  // above), which itself is only ever written server-side (Cloud Functions -
  // see finalizeAccountUpgrade / revenueCatWebhook in functions/index.js).
  // There used to be an upgradeToPremium()/restorePurchases() pair here that
  // flipped `isPremium` locally with no real purchase behind it - a
  // guaranteed App Store rejection (Guideline 3.1.1) and something the
  // Firestore listener would silently overwrite on the next snapshot
  // anyway, since clients can never legally write isPremium themselves.
  // When real purchasing (RevenueCat) is implemented, add real
  // purchase()/restorePurchases() methods here that call the RevenueCat SDK
  // and let the resulting webhook/entitlement update Firestore - never set
  // isPremium locally again.

  @override
  void dispose() {
    _firestoreSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
