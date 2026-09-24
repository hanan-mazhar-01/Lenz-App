class CloudinaryConfig {
  /// Cloudinary Cloud Name.
  /// Override with: --dart-define=CLOUDINARY_CLOUD_NAME=your_cloud_name
  static const String cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'vz6euzlq',
  );

  /// Unsigned upload preset configured in Cloudinary console.
  /// Override with: --dart-define=CLOUDINARY_UPLOAD_PRESET=your_preset
  static const String uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'vericheck_scans',
  );

  /// Root folder all uploads are nested under in the Cloudinary media library.
  static const String rootFolder = 'lenz_replica_detector';

  /// Base API URL for image uploads.
  static String get uploadUrl =>
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload';

  /// Whether Cloudinary is configured with non-empty values.
  static bool get isConfigured =>
      cloudName.trim().isNotEmpty && uploadPreset.trim().isNotEmpty;
}

