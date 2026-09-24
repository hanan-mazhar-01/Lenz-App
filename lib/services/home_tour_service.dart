import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether a given account has already seen the Home screen's
/// first-time coach-mark walkthrough.
///
/// Scoped per Firebase Auth uid (same pattern as
/// `DataMigrationService.migrateOfflineDataIfNeeded`'s per-uid migration
/// flag) so one account finishing/skipping the tour never suppresses it for
/// a different account signed into the same device.
class HomeTourService {
  static String _key(String uid) => 'home_tour_seen_$uid';

  /// True once [uid] has completed or skipped the tour at least once.
  /// Fails "seen" (never shows) rather than "unseen" on any storage error,
  /// so a transient read failure can't repeatedly interrupt the user with
  /// an unwanted walkthrough.
  static Future<bool> hasSeenTour(String uid) async {
    if (uid.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key(uid)) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markTourSeen(String uid) async {
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(uid), true);
    } catch (_) {}
  }
}
