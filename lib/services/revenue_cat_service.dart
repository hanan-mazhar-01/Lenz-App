import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../core/config/revenue_cat_config.dart';

class RevenueCatService {
  RevenueCatService._();

  static final ValueNotifier<bool> isPremiumNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> activePlanNotifier = ValueNotifier<String?>(null);
  static bool _initialized = false;

  /// Initializes the RevenueCat SDK with the Apple Public API Key.
  static Future<void> init() async {
    if (_initialized) return;

    if (!Platform.isIOS && !Platform.isMacOS) {
      if (kDebugMode) {
        debugPrint('[RevenueCatService] Skipping init on non-Apple platform');
      }
      return;
    }

    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);

      final configuration = PurchasesConfiguration(RevenueCatConfig.appleApiKey);
      await Purchases.configure(configuration);

      // Listen for background subscription updates
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        _updatePremiumStatus(customerInfo);
      });

      // Initial entitlement check
      final customerInfo = await Purchases.getCustomerInfo();
      _updatePremiumStatus(customerInfo);

      _initialized = true;
      if (kDebugMode) {
        debugPrint('[RevenueCatService] Initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCatService] Init failed: $e');
      }
    }
  }

  /// Identifies the authenticated Firebase user in RevenueCat.
  static Future<void> logIn(String appUserId) async {
    if (!_initialized) return;
    try {
      final logInResult = await Purchases.logIn(appUserId);
      _updatePremiumStatus(logInResult.customerInfo);
      if (kDebugMode) {
        debugPrint('[RevenueCatService] Logged in user: $appUserId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCatService] LogIn error: $e');
      }
    }
  }

  /// Logs out of RevenueCat (resets to anonymous app user id).
  static Future<void> logOut() async {
    if (!_initialized) return;
    try {
      final customerInfo = await Purchases.logOut();
      _updatePremiumStatus(customerInfo);
      if (kDebugMode) {
        debugPrint('[RevenueCatService] Logged out');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCatService] LogOut error: $e');
      }
    }
  }

  /// Fetches offerings configured in the RevenueCat dashboard.
  static Future<Offerings?> getOfferings() async {
    if (!_initialized) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCatService] getOfferings error: $e');
      }
      return null;
    }
  }

  /// Purchases a selected package (e.g. Monthly or Annual).
  /// Returns `true` if purchase completed and user has active premium.
  static Future<bool> purchasePackage(Package package) async {
    if (!_initialized) return false;
    try {
      final purchaseResult = await Purchases.purchasePackage(package);
      final hasPremium = _hasActiveEntitlement(purchaseResult.customerInfo);
      final planName = package.packageType == PackageType.annual ? 'Yearly Pro' : 'Monthly Pro';
      if (hasPremium) activePlanNotifier.value = planName;
      isPremiumNotifier.value = hasPremium;
      return hasPremium;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        if (kDebugMode) debugPrint('[RevenueCatService] Purchase was cancelled by user');
      } else {
        if (kDebugMode) debugPrint('[RevenueCatService] Purchase failed: $e');
        rethrow;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[RevenueCatService] Unexpected purchase error: $e');
      rethrow;
    }
  }

  /// Purchases directly by Apple Product ID (fallback if offerings packages are empty).
  /// Returns `true` if purchase completed and user has active premium.
  static Future<bool> purchaseProduct(String productId) async {
    if (!_initialized) return false;
    try {
      final purchaseResult = await Purchases.purchaseProduct(productId);
      final hasPremium = _hasActiveEntitlement(purchaseResult.customerInfo);
      final planName = productId == RevenueCatConfig.yearlySubscriptionId ? 'Yearly Pro' : 'Monthly Pro';
      if (hasPremium) activePlanNotifier.value = planName;
      isPremiumNotifier.value = hasPremium;
      return hasPremium;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        if (kDebugMode) debugPrint('[RevenueCatService] Direct purchase cancelled by user');
      } else {
        if (kDebugMode) debugPrint('[RevenueCatService] Direct purchase failed: $e');
        rethrow;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[RevenueCatService] Direct purchase error: $e');
      rethrow;
    }
  }

  /// Restores previous purchases for App Store Guideline 3.1.1 compliance.
  /// Returns `true` if any active premium entitlement was restored.
  static Future<bool> restorePurchases() async {
    if (!_initialized) return false;
    try {
      final customerInfo = await Purchases.restorePurchases();
      final hasPremium = _hasActiveEntitlement(customerInfo);
      activePlanNotifier.value = _resolvePlanName(customerInfo);
      isPremiumNotifier.value = hasPremium;
      return hasPremium;
    } catch (e) {
      if (kDebugMode) debugPrint('[RevenueCatService] restorePurchases error: $e');
      rethrow;
    }
  }

  /// Refreshes and returns the current premium status.
  static Future<bool> checkPremiumStatus() async {
    if (!_initialized) return false;
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final hasPremium = _hasActiveEntitlement(customerInfo);
      activePlanNotifier.value = _resolvePlanName(customerInfo);
      isPremiumNotifier.value = hasPremium;
      return hasPremium;
    } catch (e) {
      if (kDebugMode) debugPrint('[RevenueCatService] checkPremiumStatus error: $e');
      return isPremiumNotifier.value;
    }
  }

  /// Checks if any entitlement or subscription is active.
  /// Robust against dashboard misconfigurations, case differences, and direct StoreKit products.
  static bool _hasActiveEntitlement(CustomerInfo info) {
    // 1. Primary configured entitlement ID
    final proEntitlement = info.entitlements.all[RevenueCatConfig.entitlementId];
    if (proEntitlement?.isActive ?? false) return true;

    // 2. Case-insensitive / common entitlement identifiers
    const fallbacks = [
      'pro', 'Pro', 'PRO',
      'premium', 'Premium', 'PREMIUM',
      'lenz_pro', 'pro_plan', 'membership', 'all_features'
    ];
    for (final key in fallbacks) {
      if (info.entitlements.all[key]?.isActive ?? false) return true;
    }

    // 3. Any active entitlement present in the customer info
    if (info.entitlements.active.isNotEmpty) return true;

    // 4. Any active StoreKit subscription product identifier matching monthly/yearly
    final hasActiveSub = info.activeSubscriptions.any((id) {
      final lower = id.toLowerCase();
      return id == RevenueCatConfig.monthlySubscriptionId ||
          id == RevenueCatConfig.yearlySubscriptionId ||
          lower.contains('monthly') ||
          lower.contains('yearly') ||
          lower.contains('subscription') ||
          lower.contains('pro') ||
          lower.contains('lenz');
    });
    if (hasActiveSub) return true;

    // 5. Expiration check on all entitlements (covers timezone/grace periods)
    for (final ent in info.entitlements.all.values) {
      if (ent.isActive) return true;
      final exp = ent.expirationDate;
      if (exp != null) {
        final expDate = DateTime.tryParse(exp);
        if (expDate != null && expDate.isAfter(DateTime.now())) return true;
      }
    }

    return false;
  }

  static String? _resolvePlanName(CustomerInfo customerInfo) {
    if (!_hasActiveEntitlement(customerInfo)) return null;

    final activeSubs = customerInfo.activeSubscriptions;
    if (activeSubs.contains(RevenueCatConfig.yearlySubscriptionId) ||
        activeSubs.any((s) => s.toLowerCase().contains('yearly') || s.toLowerCase().contains('annual'))) {
      return 'Yearly Pro';
    }
    if (activeSubs.contains(RevenueCatConfig.monthlySubscriptionId) ||
        activeSubs.any((s) => s.toLowerCase().contains('monthly'))) {
      return 'Monthly Pro';
    }

    for (final ent in customerInfo.entitlements.active.values) {
      final pid = ent.productIdentifier.toLowerCase();
      if (pid.contains('yearly') || pid.contains('annual')) return 'Yearly Pro';
      if (pid.contains('monthly')) return 'Monthly Pro';
    }

    return 'Lenz Pro';
  }

  static void _updatePremiumStatus(CustomerInfo customerInfo) {
    final isPro = _hasActiveEntitlement(customerInfo);
    activePlanNotifier.value = _resolvePlanName(customerInfo);
    isPremiumNotifier.value = isPro;
    if (kDebugMode) {
      debugPrint('[RevenueCatService] Premium status updated: $isPro (Plan: ${activePlanNotifier.value})');
      debugPrint('[RevenueCatService] Active subscriptions: ${customerInfo.activeSubscriptions}');
      debugPrint('[RevenueCatService] Active entitlements: ${customerInfo.entitlements.active.keys}');
      debugPrint('[RevenueCatService] All entitlements: ${customerInfo.entitlements.all.keys}');
    }
  }
}
