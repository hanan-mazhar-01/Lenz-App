import 'dart:async';
import 'dart:io';

enum AppErrorType {
  noInternet,
  serviceUnreachable,
  timeout,
  apiUnauthorized,
  quotaLimit,
  serverError,
  invalidResponse,
  cameraError,
  unknownError,
}

class AppError implements Exception {
  final AppErrorType type;
  final String title;
  final String message;
  final String? recoveryAction;
  final Object? originalException;

  const AppError({
    required this.type,
    required this.title,
    required this.message,
    this.recoveryAction,
    this.originalException,
  });

  factory AppError.noInternet({Object? original}) => AppError(
        type: AppErrorType.noInternet,
        title: 'Connection Lost',
        message: "You're offline. Connect to the internet and try again.",
        recoveryAction: 'Check Wi-Fi or cellular data and retry.',
        originalException: original,
      );

  /// Distinct from [noInternet]: the device has working connectivity but the
  /// Cloud Function itself couldn't be reached (transient server/transport
  /// failure). Telling a user with fine Wi-Fi to "check your connection" is
  /// actively misleading, so this gets its own honest copy.
  factory AppError.serviceUnreachable({Object? original}) => AppError(
        type: AppErrorType.serviceUnreachable,
        title: 'Server Unreachable',
        message: "We couldn't reach Lenz's servers. Your connection looks fine — this is usually temporary.",
        recoveryAction: 'Please try again in a few seconds.',
        originalException: original,
      );

  factory AppError.timeout({Object? original}) => AppError(
        type: AppErrorType.timeout,
        title: 'Request Timed Out',
        message: 'The AI took too long to respond. Try again.',
        recoveryAction: 'Please retry your scan.',
        originalException: original,
      );

  factory AppError.apiUnauthorized({Object? original}) => AppError(
        type: AppErrorType.apiUnauthorized,
        title: 'Service Unauthorized',
        message: 'AI service authentication is unavailable.',
        recoveryAction: 'Verify your API key or contact support.',
        originalException: original,
      );

  factory AppError.quotaLimit({Object? original}) => AppError(
        type: AppErrorType.quotaLimit,
        title: 'AI Usage Limit',
        message: 'AI usage limit reached. Try again later.',
        recoveryAction: 'Please wait a short while or upgrade plan.',
        originalException: original,
      );

  factory AppError.serverError({int? code, Object? original}) => AppError(
        type: AppErrorType.serverError,
        title: 'Service Unavailable',
        message: 'The AI service is temporarily unavailable.',
        recoveryAction: code != null ? 'HTTP $code. Please try again shortly.' : 'Please try again shortly.',
        originalException: original,
      );

  factory AppError.invalidResponse({Object? original}) => AppError(
        type: AppErrorType.invalidResponse,
        title: 'Invalid AI Response',
        message: "We couldn't understand the AI response. Please retry.",
        recoveryAction: 'Retake the photo or retry the inspection.',
        originalException: original,
      );

  factory AppError.cameraError({String? detail, Object? original}) => AppError(
        type: AppErrorType.cameraError,
        title: 'Camera Unavailable',
        message: detail ?? 'Unable to access device camera.',
        recoveryAction: 'Ensure camera permissions are enabled in Settings.',
        originalException: original,
      );

  factory AppError.unknown({String? detail, Object? original}) => AppError(
        type: AppErrorType.unknownError,
        title: 'Analysis Unavailable',
        message: detail ?? 'Something went wrong. Please try again.',
        recoveryAction: 'Please retry.',
        originalException: original,
      );

  /// Classifies any caught exception into a typed AppError
  factory AppError.fromException(dynamic error) {
    if (error is AppError) return error;

    if (error is SocketException) {
      return AppError.noInternet(original: error);
    }

    if (error is TimeoutException) {
      return AppError.timeout(original: error);
    }

    if (error is FormatException) {
      return AppError.invalidResponse(original: error);
    }

    final str = error.toString().toLowerCase();

    // Check specific HTTP / API conditions
    if (str.contains('429') || str.contains('quota') || str.contains('resource_exhausted')) {
      return AppError.quotaLimit(original: error);
    }

    if (str.contains('401') || str.contains('403') || str.contains('unauthorized') || str.contains('api_key')) {
      return AppError.apiUnauthorized(original: error);
    }

    if (str.contains('503') || str.contains('500') || str.contains('service unavailable')) {
      return AppError.serverError(original: error);
    }

    if (str.contains('timeout') || str.contains('deadline')) {
      return AppError.timeout(original: error);
    }

    if (str.contains('camera') || str.contains('permission')) {
      return AppError.cameraError(original: error);
    }

    // Only classify as noInternet if genuinely network connection lost
    if (str.contains('network is unreachable') ||
        str.contains('connection refused') ||
        str.contains('failed host lookup') ||
        str.contains('no address associated with hostname')) {
      return AppError.noInternet(original: error);
    }

    return AppError.unknown(
      detail: error.toString().replaceAll('Exception: ', '').replaceAll('GeminiApiException: ', ''),
      original: error,
    );
  }

  @override
  String toString() => '$title: $message';
}

