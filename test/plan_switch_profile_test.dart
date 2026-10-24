import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/services/revenue_cat_service.dart';
import 'package:replica_detector/viewmodels/profile_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RevenueCatService.isPremiumNotifier.value = false;
    RevenueCatService.activePlanNotifier.value = null;
  });
  tearDown(() {
    RevenueCatService.isPremiumNotifier.value = false;
    RevenueCatService.activePlanNotifier.value = null;
  });

  test('buying a plan, switching plan and lapsing all show up on the profile', () async {
    final vm = ProfileViewModel();
    expect(vm.user.planName, 'Free Plan');
    expect(vm.isPremium, isFalse);

    // Monthly bought (the service sets the plan first, then premium).
    RevenueCatService.activePlanNotifier.value = 'Monthly Pro';
    RevenueCatService.isPremiumNotifier.value = true;
    expect(vm.isPremium, isTrue);
    expect(vm.user.planName, 'Monthly Pro');

    // Switched to yearly: premium stays true, only the plan changes.
    RevenueCatService.activePlanNotifier.value = 'Yearly Pro';
    expect(vm.isPremium, isTrue);
    expect(vm.user.planName, 'Yearly Pro');

    // Subscription lapses.
    RevenueCatService.activePlanNotifier.value = null;
    RevenueCatService.isPremiumNotifier.value = false;
    expect(vm.isPremium, isFalse);
    expect(vm.user.planName, 'Free Plan');
  });
}
