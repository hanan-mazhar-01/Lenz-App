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

  /// Whether RevenueCat is actually wired up on this platform. Callers that
  /// want to treat RC as the authoritative premium signal need to know when
  /// it genuinely has nothing to say (no API key configured for this store),
  /// rather than reading `false` as "no active subscription".
  static bool get isSupportedPlatform =>
      (Platform.isIOS || Platform.isMacOS) ||
      (Platform.isAndroid && RevenueCatConfig.googleApiKey.isNotEmpty);

  /// Initializes the RevenueCat SDK with the store-appropriate public API key.
  static Future<void> init() async {
    if (_initialized) return;

    final String apiKey;
    if (Platform.isIOS || Platform.isMacOS) {
      apiKey = RevenueCatConfig.appleApiKey;
    } else if (Platform.isAndroid && RevenueCatConfig.googleApiKey.isNotEmpty) {
      apiKey = RevenueCatConfig.googleApiKey;
    } else {
      if (kDebugMode) {
        debugPrint('[RevenueCatService] Skipping init: no API key configured for this platform');
      }
      return;
    }

    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);

      final configuration = PurchasesConfiguration(apiKey);
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

  /// Checks whether the single configured entitlement is active.
  ///
  /// This intentionally checks only [RevenueCatConfig.entitlementId] — an
  /// app-wide "grant premium for any active entitlement/product" fallback
  /// would silently paper over a dashboard misconfiguration (wrong
  /// entitlement id, an unrelated future product) instead of surfacing it.
  static bool _hasActiveEntitlement(CustomerInfo info) {
    final proEntitlement = info.entitlements.all[RevenueCatConfig.entitlementId];
    final isActive = proEntitlement?.isActive ?? false;

    if (kDebugMode && !isActive && info.entitlements.active.isNotEmpty) {
      // The customer has *some* active entitlement, just not the configured
      // one — almost always means entitlementId in RevenueCatConfig doesn't
      // match the RevenueCat dashboard. Surfaced in debug only.
      debugPrint(
        '[RevenueCatService] Configured entitlementId '
        '"${RevenueCatConfig.entitlementId}" is not active, but '
        '${info.entitlements.active.keys} is/are. Check RevenueCatConfig.entitlementId.',
      );
    }

    return isActive;
  }

  /// Returns true when [productId] is eligible for its configured
  /// introductory offer (free trial / intro price) for this Apple ID.
  ///
  /// Used so paywall copy only ever promises a trial the user can actually
  /// get — never a hardcoded assumption. Android always reports `unknown`
  /// (per RevenueCat), which this treats as "don't promise a trial".
  static Future<bool> isEligibleForIntroOffer(String productId) async {
    if (!_initialized) return false;
    try {
      final result = await Purchases.checkTrialOrIntroductoryPriceEligibility([productId]);
      return result[productId]?.status == IntroEligibilityStatus.introEligibilityStatusEligible;
    } catch (e) {
      if (kDebugMode) debugPrint('[RevenueCatService] Eligibility check error: $e');
      return false;
    }
  }

  /// Returns the best URL to send the user to for managing/cancelling their
  /// subscription: RevenueCat's reported management URL (App Store
  /// subscriptions page on iOS) when available, otherwise Apple's generic
  /// subscriptions page.
  static Future<String> getManagementUrl() async {
    if (_initialized) {
      try {
        final info = await Purchases.getCustomerInfo();
        if (info.managementURL != null && info.managementURL!.isNotEmpty) {
          return info.managementURL!;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[RevenueCatService] getManagementUrl error: $e');
      }
    }
    return 'https://apps.apple.com/account/subscriptions';
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

  /// Turns a purchase/restore failure into short, specific copy instead of
  /// surfacing the raw platform exception to the user.
  static String friendlyErrorMessage(Object error) {
    if (error is PlatformException) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      switch (code) {
        case PurchasesErrorCode.purchaseCancelledError:
          return 'Purchase cancelled.';
        case PurchasesErrorCode.networkError:
        case PurchasesErrorCode.offlineConnectionError:
          return 'No internet connection. Check your connection and try again.';
        case PurchasesErrorCode.productAlreadyPurchasedError:
          return 'You already own this plan. Try Restore Purchases instead.';
        case PurchasesErrorCode.productNotAvailableForPurchaseError:
        case PurchasesErrorCode.purchaseInvalidError:
          return 'This plan isn\'t available for purchase right now. Please try again shortly.';
        case PurchasesErrorCode.paymentPendingError:
          return 'Your payment is pending approval. Check back shortly.';
        case PurchasesErrorCode.storeProblemError:
        case PurchasesErrorCode.unknownBackendError:
        case PurchasesErrorCode.unexpectedBackendResponseError:
          return 'The App Store is having trouble right now. Please try again later.';
        case PurchasesErrorCode.receiptAlreadyInUseError:
          return 'This subscription is already linked to a different account.';
        case PurchasesErrorCode.invalidCredentialsError:
        case PurchasesErrorCode.configurationError:
          return 'Subscriptions aren\'t available right now. Please try again later.';
        default:
          return 'Something went wrong. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
