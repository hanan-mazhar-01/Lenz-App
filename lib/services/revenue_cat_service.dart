import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../core/config/revenue_cat_config.dart';

class RevenueCatService {
  RevenueCatService._();

  static final ValueNotifier<bool> isPremiumNotifier = ValueNotifier<bool>(false);
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

  /// Restores previous purchases for App Store Guideline 3.1.1 compliance.
  /// Returns `true` if any active premium entitlement was restored.
  static Future<bool> restorePurchases() async {
    if (!_initialized) return false;
    try {
      final customerInfo = await Purchases.restorePurchases();
      final hasPremium = _hasActiveEntitlement(customerInfo);
      isPremiumNotifier.value = hasPremium;
      return hasPremium;
    } catch (e) {
      if (kDebugMode) debugPrint('[RevenueCatService] restorePurchases error: $e');
      rethrow;
    }
  }

  /// Checks if any entitlement is active (either 'pro', 'premium', or any active).
  static bool _hasActiveEntitlement(CustomerInfo info) {
    final proEntitlement = info.entitlements.all[RevenueCatConfig.entitlementId];
    final premiumFallback = info.entitlements.all['premium'];
    return (proEntitlement?.isActive ?? false) ||
        (premiumFallback?.isActive ?? false) ||
        info.entitlements.active.isNotEmpty;
  }

  static void _updatePremiumStatus(CustomerInfo customerInfo) {
    final isPro = _hasActiveEntitlement(customerInfo);
    isPremiumNotifier.value = isPro;
    if (kDebugMode) {
      debugPrint('[RevenueCatService] Premium status updated: $isPro');
    }
  }
}
