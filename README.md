# replica_detector

A new Flutter project.

## Setup after cloning

`lib/core/config/env_secrets.dart` is gitignored and won't exist on a fresh
clone, which breaks the build (`Target of URI doesn't exist: 'env_secrets.dart'`).
Fix it once with:

```bash
cp lib/core/config/env_secrets.example.dart lib/core/config/env_secrets.dart
```

No real key is required in it - Gemini calls go through a Cloud Function that
holds the real key server-side (see `functions/index.js`).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
