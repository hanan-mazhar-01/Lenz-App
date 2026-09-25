// Template for lib/core/config/env_secrets.dart, which is gitignored and
// does NOT exist on a fresh clone - that's why the project fails to build
// with "Target of URI doesn't exist: 'env_secrets.dart'" right after
// cloning. Copy this file to env_secrets.dart in this same folder to fix it:
//
//   cp lib/core/config/env_secrets.example.dart lib/core/config/env_secrets.dart
//
// You do NOT need to put a real key in it for the app to run: Gemini calls
// are proxied through the `generateStructuredContent` Cloud Function
// (see functions/index.js), which holds the real key in Firebase Secret
// Manager. This local value is only a fallback for direct/offline testing
// and is never committed - never hardcode a real key here.

class EnvSecrets {
  /// Priority:
  /// 1. Compile-time flag: --dart-define=GEMINI_API_KEY=your_key
  /// 2. Development secret constant for local prototype testing
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );
}
