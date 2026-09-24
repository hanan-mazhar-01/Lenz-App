import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around `local_auth` backing the "Require Face ID /
/// Biometrics" privacy setting. Fails open (returns true / "allow") on any
/// platform error or when no biometric hardware is enrolled, rather than
/// permanently locking a user out of their own reports because of a
/// hardware/OS quirk - the setting is a privacy nicety, not a security
/// boundary the app's core function depends on.
class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  Future<bool> get isAvailable async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (e) {
      if (kDebugMode) debugPrint('[BiometricService] availability check failed: $e');
      return false;
    }
  }

  /// Prompts for Face ID / fingerprint / device PIN. Returns true if the
  /// user authenticated, if biometrics aren't available/enrolled on this
  /// device, or if the check itself errors - only an explicit user
  /// cancellation or failed attempt returns false.
  Future<bool> authenticate({required String reason}) async {
    try {
      final available = await isAvailable;
      if (!available) return true;

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[BiometricService] authenticate error: $e');
      return true;
    }
  }
}
