import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final GoogleSignIn _googleSignIn;

  StreamSubscription<User?>? _authStateSubscription;
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _authError;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn() {
    _init();
  }

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get authError => _authError;
  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  bool get isAuthenticated => _auth.currentUser != null;
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  void _init() {
    _authStateSubscription = _auth.authStateChanges().listen((user) async {
      _isInitialized = true;
      if (user != null) {
        await _ensureUserDocumentExists(user);
      }
      notifyListeners();
    });

    // If no user is logged in, automatically start anonymous session as fallback
    // so guests can immediately scan with their initial credits without blocking.
    if (_auth.currentUser == null) {
      signInAnonymously();
    }
  }

  /// Resolves the best-known name/email/photo for [user].
  ///
  /// Firebase Auth only populates the top-level `User.displayName` /
  /// `photoURL` fields when an account is *created* directly via a
  /// provider. Linking a credential onto an existing account - which is
  /// what happens on essentially every sign-in here, since every guest is
  /// auto-signed-in anonymously first - does NOT sync those fields. The
  /// provider's real profile still exists, just on the matching entry in
  /// `user.providerData` instead of the top level, so that's checked as a
  /// fallback. This is the actual root cause of "Google name/email/photo
  /// don't show up after signing in": the code was reading only the
  /// top-level fields, which stay null after linking.
  ///
  /// [knownName]/[knownEmail]/[knownPhotoUrl] let a caller pass in values it
  /// obtained directly from the sign-in provider's own SDK (e.g. the
  /// `google_sign_in` plugin's `GoogleSignInAccount`, which reliably carries
  /// displayName/photoUrl independently of whatever Firebase itself ends up
  /// recording) - these win over everything else, since they're the most
  /// direct, freshest source available.
  ({String? name, String? email, String? photoUrl}) _resolveProfile(
    User user, {
    String? knownName,
    String? knownEmail,
    String? knownPhotoUrl,
  }) {
    String? name = (knownName != null && knownName.isNotEmpty) ? knownName : user.displayName;
    String? email = (knownEmail != null && knownEmail.isNotEmpty) ? knownEmail : user.email;
    String? photoUrl =
        (knownPhotoUrl != null && knownPhotoUrl.isNotEmpty) ? knownPhotoUrl : user.photoURL;

    if (kDebugMode) {
      debugPrint(
        '[AuthService] resolveProfile top-level: displayName=${user.displayName}, '
        'email=${user.email}, photoURL=${user.photoURL}, '
        'providers=${user.providerData.map((p) => p.providerId).toList()}',
      );
    }

    for (final info in user.providerData) {
      if (info.providerId == 'firebase' || info.providerId == 'anonymous') continue;
      if (kDebugMode) {
        debugPrint(
          '[AuthService] resolveProfile providerData[${info.providerId}]: '
          'displayName=${info.displayName}, email=${info.email}, photoURL=${info.photoURL}',
        );
      }
      name = (name != null && name.isNotEmpty) ? name : info.displayName;
      email = (email != null && email.isNotEmpty) ? email : info.email;
      photoUrl = (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : info.photoURL;
    }

    if (kDebugMode) {
      debugPrint('[AuthService] resolveProfile RESULT: name=$name, email=$email, photoUrl=$photoUrl');
    }

    return (name: name, email: email, photoUrl: photoUrl);
  }

  /// Best-effort sync of the resolved profile back onto the FirebaseAuth
  /// user itself (not just Firestore), so `currentUser.displayName` reads
  /// correctly elsewhere too, and so Cloud Functions' ID-token claims
  /// (`context.auth.token.name`/`email`) are populated for anyone reading
  /// them server-side.
  Future<void> _syncAuthProfile(
    User user,
    ({String? name, String? email, String? photoUrl}) resolved,
  ) async {
    try {
      if ((user.displayName == null || user.displayName!.isEmpty) &&
          resolved.name != null &&
          resolved.name!.isNotEmpty) {
        await user.updateDisplayName(resolved.name);
      }
      if ((user.photoURL == null || user.photoURL!.isEmpty) &&
          resolved.photoUrl != null &&
          resolved.photoUrl!.isNotEmpty) {
        await user.updatePhotoURL(resolved.photoUrl);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] sync auth profile error: $e');
    }
  }

  Future<void> _ensureUserDocumentExists(
    User user, {
    String? knownName,
    String? knownEmail,
    String? knownPhotoUrl,
  }) async {
    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        final isAnon = user.isAnonymous;
        final resolved = _resolveProfile(
          user,
          knownName: knownName,
          knownEmail: knownEmail,
          knownPhotoUrl: knownPhotoUrl,
        );
        await docRef.set({
          'name': resolved.name?.isNotEmpty == true
              ? resolved.name
              : (isAnon ? 'Guest Collector' : 'Collector'),
          'email': resolved.email ?? '',
          'planName': isAnon ? 'Guest Plan' : 'Free Plan',
          'isPremium': false,
          'scansRemaining': isAnon ? 3 : 5,
          'avatarUrl': resolved.photoUrl ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (!user.isAnonymous && knownName != null && knownName.trim().isNotEmpty) {
        final data = snapshot.data();
        final currentName = (data?['name'] as String?)?.trim();
        if (currentName == null ||
            currentName.isEmpty ||
            currentName == 'Collector' ||
            currentName == 'Guest Collector') {
          await docRef.set({'name': knownName.trim()}, SetOptions(merge: true));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthService] Ensure profile doc error: $e');
      }
    }
  }

  /// Upgrades a guest to a permanent Free Plan account.
  ///
  /// Name/email/avatar are safe to write directly from the client. The
  /// credit bump and plan-name change, however, go through a secure Cloud
  /// Function - Firestore rules correctly forbid clients from writing
  /// `scansRemaining`/`isPremium` directly, so attempting that here would
  /// silently fail (and previously did: see finalizeAccountUpgrade).
  Future<void> _upgradeToPermanentUser(
    User user, {
    String? knownName,
    String? knownEmail,
    String? knownPhotoUrl,
  }) async {
    final resolved = _resolveProfile(
      user,
      knownName: knownName,
      knownEmail: knownEmail,
      knownPhotoUrl: knownPhotoUrl,
    );
    await _syncAuthProfile(user, resolved);

    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final updates = <String, dynamic>{};
      if (resolved.name != null && resolved.name!.isNotEmpty) {
        updates['name'] = resolved.name;
      }
      if (resolved.email != null && resolved.email!.isNotEmpty) {
        updates['email'] = resolved.email;
      }
      if (resolved.photoUrl != null && resolved.photoUrl!.isNotEmpty) {
        updates['avatarUrl'] = resolved.photoUrl;
      }
      if (kDebugMode) {
        debugPrint('[AuthService] upgradeToPermanentUser writing to users/${user.uid}: $updates');
      }
      if (updates.isNotEmpty) {
        await docRef.set(updates, SetOptions(merge: true));
        if (kDebugMode) debugPrint('[AuthService] upgradeToPermanentUser Firestore write succeeded');
      } else if (kDebugMode) {
        debugPrint('[AuthService] upgradeToPermanentUser: nothing resolved to write (all empty)');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] upgrade profile error: $e');
    }

    try {
      await _functions.httpsCallable('finalizeAccountUpgrade').call();
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] finalizeAccountUpgrade error: $e');
    }
  }

  /// Signs into [credential], preferring to link it onto the current
  /// anonymous session so locally-cached guest reports/collections carry
  /// over. If that identity already belongs to a different, existing real
  /// account, falls back to signing directly into that account instead of
  /// leaving the user stuck on a "credential already in use" dead end -
  /// the common case of someone reinstalling the app (getting a fresh guest
  /// session) and then signing back in with the Google/Apple ID they
  /// already used before.
  Future<UserCredential> _linkOrSignIn(
    AuthCredential credential, {
    String? knownName,
    String? knownEmail,
    String? knownPhotoUrl,
  }) async {
    if (isAnonymous && currentUser != null) {
      try {
        final result = await currentUser!.linkWithCredential(credential);
        if (kDebugMode) debugPrint('[AuthService] linkOrSignIn: linked onto anonymous session');
        await _upgradeToPermanentUser(
          result.user!,
          knownName: knownName,
          knownEmail: knownEmail,
          knownPhotoUrl: knownPhotoUrl,
        );
        return result;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' &&
            e.code != 'email-already-in-use' &&
            e.code != 'provider-already-linked') {
          rethrow;
        }
        if (kDebugMode) {
          debugPrint('[AuthService] linkOrSignIn: link failed (${e.code}), falling back to plain sign-in');
        }
        // Falls through: sign into the pre-existing real account below.
      }
    }

    final result = await _auth.signInWithCredential(credential);
    if (kDebugMode) debugPrint('[AuthService] linkOrSignIn: plain signInWithCredential succeeded');
    await _ensureUserDocumentExists(
      result.user!,
      knownName: knownName,
      knownEmail: knownEmail,
      knownPhotoUrl: knownPhotoUrl,
    );
    // Also true for a pre-existing account reached via the fallback above:
    // its Firestore profile may be stale or was never fully populated (e.g.
    // created before this resolution logic existed), so always refresh it
    // from the current provider data rather than only on first creation.
    // finalizeAccountUpgrade is safely idempotent - it no-ops once the
    // account is already a non-guest plan.
    await _upgradeToPermanentUser(
      result.user!,
      knownName: knownName,
      knownEmail: knownEmail,
      knownPhotoUrl: knownPhotoUrl,
    );
    return result;
  }

  /// Guest / Anonymous sign-in fallback.
  Future<UserCredential?> signInAnonymously() async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final credential = await _auth.signInAnonymously();
      return credential;
    } catch (e) {
      _authError = 'Guest sign-in failed: $e';
      if (kDebugMode) debugPrint(_authError);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Email & Password Sign In
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final wasAnon = isAnonymous;
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (credential.user != null) {
        await _ensureUserDocumentExists(credential.user!);
        if (wasAnon) {
          await _upgradeToPermanentUser(credential.user!);
        }
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      _authError = _mapAuthException(e);
      return null;
    } catch (e) {
      _authError = 'Sign in failed. Please try again.';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Email & Password Sign Up
  Future<UserCredential?> signUpWithEmail(
    String email,
    String password, {
    String? displayName,
  }) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    final trimmedEmail = email.trim();

    try {
      UserCredential credential;
      if (isAnonymous && currentUser != null) {
        // Link existing guest account to preserve all local reports & collection items
        final emailAuthCred = EmailAuthProvider.credential(
          email: trimmedEmail,
          password: password,
        );
        try {
          credential = await currentUser!.linkWithCredential(emailAuthCred);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use' || e.code == 'credential-already-in-use') {
            // They already have a real account under this email - try the
            // password they just typed against it instead of a dead end.
            // If it's wrong, this throws and is mapped to a clear error below.
            credential = await _auth.signInWithEmailAndPassword(
              email: trimmedEmail,
              password: password,
            );
            final resolvedFallbackName = (displayName != null && displayName.trim().isNotEmpty)
                ? displayName.trim()
                : (credential.user?.displayName?.isNotEmpty == true
                    ? credential.user!.displayName
                    : (trimmedEmail.contains('@') ? trimmedEmail.split('@').first : null));
            await _ensureUserDocumentExists(
              credential.user!,
              knownName: resolvedFallbackName,
              knownEmail: trimmedEmail,
            );
            await _upgradeToPermanentUser(
              credential.user!,
              knownName: resolvedFallbackName,
              knownEmail: trimmedEmail,
            );
            return credential;
          }
          rethrow;
        }
      } else {
        credential = await _auth.createUserWithEmailAndPassword(
          email: trimmedEmail,
          password: password,
        );
      }
      final trimmedName = displayName?.trim();
      if (trimmedName != null && trimmedName.isNotEmpty) {
        try {
          await credential.user?.updateDisplayName(trimmedName);
          await credential.user?.reload();
        } catch (_) {}
      }
      final resolvedName = (trimmedName != null && trimmedName.isNotEmpty)
          ? trimmedName
          : (trimmedEmail.contains('@') ? trimmedEmail.split('@').first : null);

      if (credential.user != null) {
        await _ensureUserDocumentExists(
          credential.user!,
          knownName: resolvedName,
          knownEmail: trimmedEmail,
        );
        await _upgradeToPermanentUser(
          credential.user!,
          knownName: resolvedName,
          knownEmail: trimmedEmail,
        );
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      _authError = _mapAuthException(e);
      return null;
    } catch (e) {
      _authError = 'Sign up failed. Please try again.';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      if (kDebugMode) {
        debugPrint(
          '[AuthService] GoogleSignInAccount: displayName=${googleUser.displayName}, '
          'email=${googleUser.email}, photoUrl=${googleUser.photoUrl}',
        );
      }

      // Pass the plugin's own account info through directly - it reliably
      // carries displayName/photoUrl independently of whatever ends up (or
      // doesn't end up) on the Firebase User/providerData after linking.
      return await _linkOrSignIn(
        credential,
        knownName: googleUser.displayName,
        knownEmail: googleUser.email,
        knownPhotoUrl: googleUser.photoUrl,
      );
    } on FirebaseAuthException catch (e) {
      _authError = _mapAuthException(e);
      return null;
    } catch (e) {
      _authError = 'Google Sign-In failed: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Apple Sign In
  Future<UserCredential?> signInWithApple() async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthProvider oAuthProvider = OAuthProvider('apple.com');
      final AuthCredential credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final result = await _linkOrSignIn(credential);

      // Apple hands over the user's name only on the very first-ever
      // authorization for this app - never again, and never through
      // providerData like Google's name does. Capture it here while we
      // still can, and persist it since this is our only chance to.
      final appleName = [appleCredential.givenName, appleCredential.familyName]
          .where((s) => s != null && s.trim().isNotEmpty)
          .join(' ')
          .trim();
      if (appleName.isNotEmpty && result.user != null) {
        await result.user!.updateDisplayName(appleName);
        await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .set({'name': appleName}, SetOptions(merge: true));
      }

      return result;
    } on FirebaseAuthException catch (e) {
      _authError = _mapAuthException(e);
      return null;
    } catch (e) {
      _authError = 'Apple Sign-In failed: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sends a password-reset email. Returns true on success.
  Future<bool> sendPasswordResetEmail(String email) async {
    _authError = null;
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return true;
    } on FirebaseAuthException catch (e) {
      _authError = _mapAuthException(e);
      return false;
    } catch (e) {
      _authError = 'Could not send reset email. Please try again.';
      return false;
    } finally {
      notifyListeners();
    }
  }

  /// True if the signed-in Google identity is still linked to this account -
  /// checked before signing out, since `currentUser` is gone afterward.
  bool get _signedInWithGoogle =>
      currentUser?.providerData.any((p) => p.providerId == 'google.com') ?? false;

  /// Best-effort only: clears Google's cached session so a later "Continue
  /// with Google" prompts fresh instead of silently re-authenticating the
  /// same account. Deliberately swallows its own errors - the plugin can
  /// throw (e.g. "not signed in" when the session was only ever restored
  /// from Firebase's persisted auth state, never established through a
  /// fresh native google_sign_in flow in this app run) and that must never
  /// block the actual, critical `_auth.signOut()` that follows it.
  Future<void> _signOutOfGoogle() async {
    final wasGoogle = _signedInWithGoogle;
    try {
      await _googleSignIn.signOut();
      if (wasGoogle) await _googleSignIn.disconnect();
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] Google sign-out/disconnect error (ignored): $e');
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _signOutOfGoogle();
      await _auth.signOut();
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] Sign out error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Permanently deletes the signed-in user's account: Firestore data,
  /// Cloudinary-hosted images, and the Firebase Auth account itself.
  ///
  /// Required by Apple Guideline 5.1.1(v) - any app that lets a user create
  /// an account must also let them delete it. Everything happens inside the
  /// `deleteAccount` Cloud Function using Admin privileges, specifically so
  /// this never hits Firebase Auth's client-side "requires recent login"
  /// error (Admin SDK deletion has no such restriction). Returns null on
  /// success, or an error message to show the user on failure.
  Future<String?> deleteAccount() async {
    if (currentUser == null) return 'No account is currently signed in.';
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      await _functions.httpsCallable('deleteAccount').call();
      // The Auth user no longer exists server-side; sign out locally to
      // clear the (now-invalid) cached session and route back to sign-in.
      // Also clear Google's cached session (see _signOutOfGoogle) - otherwise
      // "Continue with Google" silently re-authenticates the just-deleted
      // identity instead of prompting for a (possibly different) account.
      await _signOutOfGoogle();
      await _auth.signOut();
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Could not delete account. Please try again.';
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] deleteAccount error: $e');
      return 'Could not delete account. Please check your connection and try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _mapAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'network-request-failed':
        return 'Network connection error. Please check your internet.';
      case 'credential-already-in-use':
        return 'This account is already linked to another user.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}

