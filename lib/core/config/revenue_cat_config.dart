class RevenueCatConfig {
  RevenueCatConfig._();

  /// Public Apple API key from RevenueCat dashboard
  static const String appleApiKey = 'appl_bQdCMdBLLkLKnTOKAxBwIEvikhF';

  /// RevenueCat App ID
  static const String appId = 'appc2e7ef1260';

  /// Primary entitlement identifier configured in RevenueCat
  static const String entitlementId = 'pro';

  /// Apple App Store Connect Product IDs
  static const String monthlySubscriptionId = 'lenz_subscription_monthly';
  static const String yearlySubscriptionId = 'lenz_subscription_yearly';

  /// Legal URLs required by Apple App Store Guideline 3.1.2
  static const String termsOfServiceUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
  static const String privacyPolicyUrl =
      'https://www.apple.com/legal/privacy/';
}
