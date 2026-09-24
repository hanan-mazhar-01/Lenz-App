import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/config/cloudinary_config.dart';

class CloudinaryService {
  final http.Client _client;

  CloudinaryService({http.Client? client}) : _client = client ?? http.Client();

  /// Uploads a single local image file to Cloudinary.
  /// Returns the HTTPS secure URL on success, or null if skipped/failed.
  Future<String?> uploadImage(
    File file, {
    String? folder,
    String? publicId,
  }) async {
    if (!CloudinaryConfig.isConfigured || !file.existsSync()) {
      return null;
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(CloudinaryConfig.uploadUrl),
      );

      request.fields['upload_preset'] = CloudinaryConfig.uploadPreset;
      if (folder != null && folder.isNotEmpty) {
        request.fields['folder'] = folder;
      }
      if (publicId != null && publicId.isNotEmpty) {
        request.fields['public_id'] = publicId;
      }

      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        if (kDebugMode) {
          debugPrint('[CloudinaryService] Upload succeeded: $secureUrl');
        }
        return secureUrl;
      } else {
        if (kDebugMode) {
          debugPrint(
            '[CloudinaryService] Upload failed (${response.statusCode}): ${response.body}',
          );
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CloudinaryService] Upload error: $e');
      }
      return null;
    }
  }

  /// Uploads evidence images in the background and returns a map of {evidenceId: secureUrl}.
  /// This executes asynchronously without blocking the UI or the local scan flow.
  ///
  /// All images go directly into [CloudinaryConfig.rootFolder] - no
  /// per-user/per-scan subfolders. Since that flattens everything into one
  /// folder, the public_id carries the uniqueness instead (userId + scanId +
  /// evidenceId), so two users' images - or two scans by the same user -
  /// never collide or overwrite each other.
  Future<Map<String, String>> uploadEvidencePhotos({
    required String userId,
    required String scanId,
    required Map<String, String> localImages,
  }) async {
    final results = <String, String>{};

    for (final entry in localImages.entries) {
      final evidenceId = entry.key;
      final localPath = entry.value;

      if (localPath.isEmpty || localPath.startsWith('http://') || localPath.startsWith('https://')) {
        continue;
      }

      final file = File(localPath);
      if (!file.existsSync()) continue;

      final url = await uploadImage(
        file,
        folder: CloudinaryConfig.rootFolder,
        publicId: '${userId}_${scanId}_$evidenceId',
      );

      if (url != null && url.isNotEmpty) {
        results[evidenceId] = url;
      }
    }

    return results;
  }

  void close() {
    _client.close();
  }
}

