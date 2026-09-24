import 'package:flutter/services.dart';
import 'storage_service.dart';

/// Drop-in replacement for [HapticFeedback] that respects the user's
/// "Haptic Feedback" setting (Settings sheet). Call [Haptics.attach] once at
/// app startup (see main.dart) so every tap-handler across the app - most of
/// which are plain widgets with no direct route to StorageService at the
/// point of the call - can honor the toggle without threading StorageService
/// through dozens of files individually. Falls back to "haptics on" if
/// never attached (e.g. in a widget test), matching the setting's own
/// documented default.
class Haptics {
  Haptics._();

  static StorageService? _storage;

  static void attach(StorageService storage) {
    _storage = storage;
  }

  static bool get _enabled => _storage?.getBool('haptics_enabled', defaultValue: true) ?? true;

  static void lightImpact() {
    if (_enabled) HapticFeedback.lightImpact();
  }

  static void mediumImpact() {
    if (_enabled) HapticFeedback.mediumImpact();
  }

  static void heavyImpact() {
    if (_enabled) HapticFeedback.heavyImpact();
  }

  static void selectionClick() {
    if (_enabled) HapticFeedback.selectionClick();
  }
}
