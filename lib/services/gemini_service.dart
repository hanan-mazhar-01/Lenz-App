import 'dart:async';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../core/config/gemini_config.dart';
import '../core/errors/app_error.dart';

class GeminiService {
  final FirebaseFunctions _functions;

  GeminiService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Executes an inference request via the secure Firebase Cloud Function proxy.
  /// Enforces authentication and server-side rate limits/quotas.
  Future<Map<String, dynamic>> generateStructuredContent({
    required String prompt,
    List<Map<String, dynamic>>? inlineImages,
    String? requestTypeLabel,
    int? maxOutputTokens,
    Duration? timeout,
  }) async {
    final label = requestTypeLabel ?? 'inference';
    final startTime = DateTime.now();

    int attempts = 0;
    final maxAttempts = 1 + GeminiConfig.retryCount;
    String currentPrompt = prompt;

    while (attempts < maxAttempts) {
      attempts++;
      if (kDebugMode) {
        debugPrint(
          '[GeminiService] CloudFunction request started: label=$label, attempt=$attempts',
        );
      }

      try {
        final result = await _executeCallableCall(
          currentPrompt,
          inlineImages,
          label,
          maxOutputTokens ?? GeminiConfig.maxOutputTokens,
          timeout ?? GeminiConfig.timeout,
        );
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        if (kDebugMode) {
          debugPrint(
            '[GeminiService] Request succeeded: label=$label in ${elapsed}ms',
          );
        }
        return result;
      } on AppError catch (e) {
        if (e.type == AppErrorType.apiUnauthorized || attempts >= maxAttempts) {
          rethrow;
        }
        if (e.type == AppErrorType.quotaLimit) {
          if (kDebugMode) {
            debugPrint(
              '[GeminiService] Quota limit encountered. Backing off for ${3000 * attempts}ms...',
            );
          }
          await Future.delayed(Duration(milliseconds: 3000 * attempts));
        } else if (e.type == AppErrorType.serviceUnreachable) {
          // UNAVAILABLE from a Cloud Function is most often a cold container
          // still spinning up (Admin SDK + Secret Manager init can take
          // several seconds, worse right after a redeploy). A short fixed
          // delay rarely outlasts that, so back off longer than other
          // transient errors before retrying.
          if (kDebugMode) {
            debugPrint(
              '[GeminiService] Cloud Function unreachable (likely cold start). Backing off for ${2500 * attempts}ms...',
            );
          }
          await Future.delayed(Duration(milliseconds: 2500 * attempts));
        } else {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      } on SocketException catch (e) {
        if (attempts >= maxAttempts) {
          throw AppError.noInternet(original: e);
        }
        await Future.delayed(const Duration(milliseconds: 1500));
      } on TimeoutException catch (e) {
        if (attempts >= maxAttempts) {
          throw AppError.timeout(original: e);
        }
        await Future.delayed(const Duration(milliseconds: 1500));
      } on FormatException catch (e) {
        if (attempts >= maxAttempts) {
          throw AppError.invalidResponse(original: e);
        }
        currentPrompt =
            '$prompt\n\nCRITICAL: Output ONLY valid, raw RFC-8259 JSON. Do not include markdown codeblocks or text wrappers.';
        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (e) {
        if (attempts >= maxAttempts) {
          throw AppError.fromException(e);
        }
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    }

    throw AppError.unknown(detail: 'Something went wrong while analyzing the item.');
  }

  Future<Map<String, dynamic>> _executeCallableCall(
    String prompt,
    List<Map<String, dynamic>>? inlineImages,
    String requestTypeLabel,
    int maxOutputTokens,
    Duration timeout,
  ) async {
    try {
      final callable = _functions.httpsCallable(
        'generateStructuredContent',
        options: HttpsCallableOptions(timeout: timeout),
      );

      final payload = <String, dynamic>{
        'prompt': prompt,
        'requestTypeLabel': requestTypeLabel,
        'maxOutputTokens': maxOutputTokens,
      };

      if (inlineImages != null && inlineImages.isNotEmpty) {
        payload['inlineImages'] = inlineImages;
      }

      final result = await callable.call<dynamic>(payload).timeout(timeout);

      final data = result.data;
      if (data is Map<String, dynamic>) {
        return data;
      } else if (data is Map) {
        return Map<String, dynamic>.from(data);
      } else {
        throw const FormatException('Expected JSON object root from Cloud Function');
      }
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[GeminiService] FirebaseFunctionsException: code=${e.code}, message=${e.message}',
        );
      }
      switch (e.code) {
        case 'resource-exhausted':
          throw AppError.quotaLimit();
        case 'unauthenticated':
        case 'permission-denied':
          throw AppError.apiUnauthorized();
        case 'deadline-exceeded':
          throw AppError.timeout(original: e);
        case 'unavailable':
          // The Firebase SDK reports UNAVAILABLE for any failed request to
          // the Cloud Function, whether the device is genuinely offline or
          // the call just couldn't complete for a transient/server-side
          // reason. Probe real connectivity before blaming the user's Wi-Fi.
          throw await _isDeviceOnline()
              ? AppError.serviceUnreachable(original: e)
              : AppError.noInternet(original: e);
        case 'invalid-argument':
          throw AppError.invalidResponse(original: e);
        default:
          throw AppError.fromException(e.message ?? 'Analysis failed');
      }
    } on TimeoutException catch (e) {
      throw AppError.timeout(original: e);
    } on SocketException catch (e) {
      throw AppError.noInternet(original: e);
    }
  }

  /// A cheap, direct DNS+socket probe independent of the Firebase SDK, used
  /// only to tell a genuinely offline device apart from a reachable one whose
  /// Cloud Function call failed for some other reason.
  Future<bool> _isDeviceOnline() async {
    try {
      final result = await InternetAddress.lookup('firebase.google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void close() {}
}
