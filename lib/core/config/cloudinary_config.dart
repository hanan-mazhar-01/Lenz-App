/// Cloudinary storage for scan evidence photos.
///
/// Uploads are *signed*: the app asks the `signCloudinaryUploads` Cloud
/// Function for a per-photo signature, and the cloud name, API key, folder
/// and public_id all come back from the server with it. Nothing that grants
/// upload access (no unsigned preset, no secret) ships in the app binary.
class CloudinaryConfig {
  CloudinaryConfig._();

  /// Callable Cloud Function that signs uploads (functions/index.js).
  static const String signFunctionName = 'signCloudinaryUploads';

  /// Image upload endpoint for [cloudName].
  static String uploadUrl(String cloudName) =>
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload';
}
