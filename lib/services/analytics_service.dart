import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import '../core/errors/app_error.dart';

class AnalyticsService {
  final FirebaseAnalytics? _analytics;
  final FirebaseCrashlytics? _crashlytics;

  AnalyticsService({
    FirebaseAnalytics? analytics,
    FirebaseCrashlytics? crashlytics,
  })  : _analytics = analytics,
        _crashlytics = crashlytics;

  static AnalyticsService? _instance;
  static AnalyticsService get instance {
    if (_instance == null) {
      FirebaseAnalytics? analytics;
      FirebaseCrashlytics? crashlytics;
      try {
        if (!kIsWeb && Firebase.apps.isNotEmpty) {
          analytics = FirebaseAnalytics.instance;
          crashlytics = FirebaseCrashlytics.instance;
        }
      } catch (_) {}
      _instance = AnalyticsService(analytics: analytics, crashlytics: crashlytics);
    }
    return _instance!;
  }

  Future<void> logScanStarted({String? category, String? brand}) async {
    try {
      final params = <String, Object>{};
      if (category != null) params['category'] = category;
      if (brand != null) params['brand'] = brand;
      await _analytics?.logEvent(
        name: 'scan_started',
        parameters: params.isEmpty ? null : params,
      );
    } catch (_) {}
  }

  Future<void> logScanCompleted({
    required String reportId,
    required String verdict,
    required int confidence,
  }) async {
    try {
      await _analytics?.logEvent(
        name: 'scan_completed',
        parameters: {
          'report_id': reportId,
          'verdict': verdict,
          'confidence': confidence,
        },
      );
    } catch (_) {}
  }

  Future<void> logScanFailed({
    required String errorType,
    String? message,
  }) async {
    try {
      final params = <String, Object>{'error_type': errorType};
      if (message != null) params['error_message'] = message;
      await _analytics?.logEvent(
        name: 'scan_failed',
        parameters: params,
      );
    } catch (_) {}
  }

  Future<void> logPremiumScreenViewed() async {
    try {
      await _analytics?.logEvent(name: 'premium_screen_viewed');
    } catch (_) {}
  }

  Future<void> logPurchaseCompleted({
    required String planId,
    double? price,
  }) async {
    try {
      final params = <String, Object>{'plan_id': planId};
      if (price != null) params['price'] = price;
      await _analytics?.logEvent(
        name: 'purchase_completed',
        parameters: params,
      );
    } catch (_) {}
  }

  Future<void> recordError(
    dynamic error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    try {
      await _crashlytics?.recordError(
        error,
        stack,
        reason: reason,
        fatal: fatal,
      );
    } catch (_) {}
  }

  Future<void> recordAppError(AppError error, [StackTrace? stack]) async {
    if (error.type == AppErrorType.serverError ||
        error.type == AppErrorType.unknownError) {
      await recordError(
        error,
        stack,
        reason: 'AppError: ${error.message} (${error.type.name})',
      );
    }
  }
}
