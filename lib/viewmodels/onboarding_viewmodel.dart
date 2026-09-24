import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';

/// Tracks whether the user has completed onboarding (the welcome screen).
///
/// This used to also drive a guided first-scan flow (step navigation,
/// evidence capture, analysis) but that was never wired to any screen - the
/// actual onboarding UI is just the static welcome carousel in
/// FirstScreenView. That dead ~90% of this class was removed; this now only
/// tracks the one thing main.dart actually reads.
class OnboardingViewModel extends ChangeNotifier {
  final StorageService? _storageService;

  bool _isCompleted = false;

  OnboardingViewModel({StorageService? storageService})
      : _storageService = storageService {
    _isCompleted =
        _storageService?.getBool('onboarding_completed', defaultValue: false) ?? false;
  }

  bool get isCompleted => _isCompleted;

  void finishOnboarding() {
    _isCompleted = true;
    _storageService?.setBool('onboarding_completed', true);
    notifyListeners();
  }
}
