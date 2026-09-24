# VeriCheck Backend Deployment & Configuration Guide

This guide outlines how to configure, deploy, and manage the Firebase backend (Cloud Functions, Firestore Security Rules) and Cloudinary image storage for VeriCheck.

---

## 1. Firebase Cloud Functions & Secrets Setup

### Set Gemini API Key Secret
In Firebase Cloud Functions, the Gemini API key is stored securely in Firebase Secret Manager:
```bash
firebase functions:secrets:set GEMINI_API_KEY
```
When prompted, enter your active Gemini API key:
`YOUR_GCP_API_KEY`

### Deploy Backend Functions & Security Rules
Deploy both the Cloud Functions and Firestore Security Rules to your Firebase project (`lenz-ade22`):
```bash
firebase deploy --only functions,firestore,storage
```

---

## 2. Functions Architecture

The backend consists of three main services in `functions/index.js`:

1. **`generateStructuredContent` (`https.onCall`)**:
   - Proxies inference requests to Gemini 3.1 Flash Lite securely behind Firebase.
   - Enforces user authentication (`context.auth`).
   - For `multi_image_forensic_observations` (the final forensic scan), atomically checks that the user has credits (`scansRemaining > 0` or `isPremium == true`) inside a Firestore transaction.
   - Decrements `scansRemaining` by 1 for non-premium users, or throws `resource-exhausted` when out of credits.
   - Runs with `minInstances: 1` to keep one container permanently warm, avoiding cold-start failures (surfaced to users as "Server Unreachable") right after idle periods or a redeploy. This adds a small fixed idle cost (roughly $5-15/month for a 512MB instance, depending on region) on top of normal per-invocation billing — check the [GCP pricing calculator](https://cloud.google.com/products/calculator) for a current estimate.

2. **`onUserCreated` (Auth Trigger)**:
   - When any user signs up (or opens the app as an anonymous guest), this trigger provisions `users/{uid}` with:
     ```json
     {
       "name": "Collector",
       "email": "",
       "planName": "Free Plan",
       "isPremium": false,
       "scansRemaining": 5,
       "avatarUrl": "",
       "createdAt": "SERVER_TIMESTAMP"
     }
     ```

3. **`revenueCatWebhook` (HTTPS Webhook Endpoint)**:
   - Endpoint URL: `https://<region>-lenz-ade22.cloudfunctions.net/revenueCatWebhook`
   - Listens for `INITIAL_PURCHASE`, `RENEWAL`, and `CANCELLATION` events from RevenueCat.
   - Automatically upgrades matching `users/{app_user_id}` doc to `isPremium: true` and `planName: "VeriCheck Premium"`.

---

## 3. Firestore Security Rules

Defined in `firestore.rules`:
- Every user can only read and write documents under their own `users/{uid}` path.
- Top-level fields `isPremium` and `scansRemaining` on `users/{uid}` can **never** be updated directly by client-side code; only the Cloud Functions Admin SDK can modify them.
- Subcollections `reports`, `collection`, and `categories` allow full read/write for the authenticated owner.

---

## 4. Cloudinary Image Storage

Evidence photos are uploaded to Cloudinary asynchronously in the background after analysis completes, without blocking UI navigation or offline access.

### Configuration
In `lib/core/config/cloudinary_config.dart`, customize:
- `CLOUDINARY_CLOUD_NAME` (e.g. `your_cloud_name`)
- `CLOUDINARY_UPLOAD_PRESET` (an unsigned upload preset configured in Cloudinary Settings -> Upload Presets)

You can pass them during run/build:
```bash
flutter run --dart-define=CLOUDINARY_CLOUD_NAME=your_cloud --dart-define=CLOUDINARY_UPLOAD_PRESET=vericheck_scans
```

---

## 5. Offline Tolerance & Data Migration

- **Offline-First**: All reports, collections, and custom categories are saved immediately to `SharedPreferences` locally. If offline, the app continues to function 100% locally.
- **One-time Migration**: When a user signs in, `DataMigrationService` reads existing local reports from `SharedPreferences` and uploads them to Firestore if their remote account subcollections are empty, ensuring existing scans are never lost.

