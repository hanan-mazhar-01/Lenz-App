import 'env_secrets.dart';

class GeminiConfig {
  /// Centralized Gemini model identifier.
  /// Change here to swap the model application-wide without rewriting any other files.
  static String modelName = 'gemini-3.1-flash-lite';
  static String get model => modelName;
  static set model(String val) => modelName = val;

  /// Generation temperature. 0 = always pick the most likely token, so the
  /// same photos produce the same findings as far as the model allows.
  /// Mirrors the value hard-set in functions/index.js.
  static double temperature = 0.0;

  /// Maximum tokens per response.
  static int maxOutputTokens = 2048;

  /// Network timeout for each Gemini API call.
  static Duration timeout = const Duration(seconds: 60);

  /// Maximum retries for transient errors.
  static int retryCount = 2;

  /// Retrieves the configured API key without logging or exposing it.
  static String get apiKey => EnvSecrets.geminiApiKey;

  /// Whether the backend service is configured. Since Gemini calls are routed
  /// through Firebase Cloud Functions, the backend proxies all requests securely.
  static bool get hasValidKey => true;
}
