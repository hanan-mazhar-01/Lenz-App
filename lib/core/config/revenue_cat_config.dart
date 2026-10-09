class RevenueCatConfig {
  RevenueCatConfig._();

  /// Public Apple API key from RevenueCat dashboard
  static const String appleApiKey = 'appl_bQdCMdBLLkLKnTOKAxBwIEvikhF';

  /// Public Google Play API key from RevenueCat dashboard (Project Settings
  /// -> API Keys -> Google Play Store). Empty until supplied — Android
  /// purchases stay disabled (see RevenueCatService.isSupportedPlatform)
  /// until this is filled in AND the matching Play Console setup is done.
  static const String googleApiKey = '';

  /// RevenueCat App ID
  static const String appId = 'appc2e7ef1260';

  /// Primary entitlement identifier configured in RevenueCat
  static const String entitlementId = 'pro';

  /// Apple App Store Connect Product IDs
  static const String monthlySubscriptionId = 'lenz_subscription_monthly';
  static const String yearlySubscriptionId = 'lenz_subscription_yearly';

  /// Legal URLs required by App Store Guidelines
  static const String termsOfServiceUrl =
      'https://lenz-privacy-policy.blogspot.com/2026/09/lenz-terms-of-service.html';
  static const String privacyPolicyUrl =
      'https://lenz-privacy-policy.blogspot.com/2026/09/lenz-privacy-policy.html';
}
