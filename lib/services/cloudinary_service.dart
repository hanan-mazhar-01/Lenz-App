import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/cloudinary_config.dart';

/// Asks the server to sign uploads for [evidenceIds] of [scanId]. Returns
/// the callable's response map, or null if signing isn't available.
typedef CloudinaryUploadSigner = Future<Map<String, dynamic>?> Function(
  String scanId,
  List<String> evidenceIds,
);

class CloudinaryService {
  final http.Client _client;
  final CloudinaryUploadSigner _signer;

  CloudinaryService({http.Client? client, CloudinaryUploadSigner? signer})
      : _client = client ?? http.Client(),
        _signer = signer ?? _callSignFunction;

  static Future<Map<String, dynamic>?> _callSignFunction(
    String scanId,
    List<String> evidenceIds,
  ) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(CloudinaryConfig.signFunctionName)
        .call<Map<String, dynamic>>({'scanId': scanId, 'evidenceIds': evidenceIds});
    return Map<String, dynamic>.from(result.data);
  }

  /// Uploads one local image with server-issued signed parameters.
  /// Returns the HTTPS secure URL on success, or null on failure.
  Future<String?> _uploadSigned(
    File file, {
    required String cloudName,
    required String apiKey,
    required String folder,
    required int timestamp,
    required String publicId,
    required String signature,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(CloudinaryConfig.uploadUrl(cloudName)))
        ..fields['api_key'] = apiKey
        ..fields['timestamp'] = '$timestamp'
        ..fields['folder'] = folder
        ..fields['public_id'] = publicId
        ..fields['signature'] = signature
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await http.Response.fromStream(await _client.send(request));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['secure_url'] as String?;
      }
      if (kDebugMode) {
        debugPrint('[CloudinaryService] Upload failed (${response.statusCode}): ${response.body}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[CloudinaryService] Upload error: $e');
      return null;
    }
  }

  /// Uploads evidence images in the background and returns a map of
  /// {evidenceId: secureUrl}. Runs without blocking the UI or the local scan
  /// flow; any photo that can't be uploaded simply stays local.
  ///
  /// The server decides where each photo goes: `lenz_replica_detector/`
  /// `{uid}_{scanId}_{evidenceId}`, so two users' images - or two scans by
  /// the same user - never collide, and account/scan deletion can remove
  /// them by prefix. [userId] is kept for callers; the server uses the
  /// signed-in uid.
  Future<Map<String, String>> uploadEvidencePhotos({
    required String userId,
    required String scanId,
    required Map<String, String> localImages,
  }) async {
    final results = <String, String>{};

    final files = <String, File>{};
    for (final entry in localImages.entries) {
      final localPath = entry.value;
      if (localPath.isEmpty || localPath.startsWith('http://') || localPath.startsWith('https://')) {
        continue;
      }
      final file = File(localPath);
      if (file.existsSync()) files[entry.key] = file;
    }
    if (files.isEmpty) return results;

    final Map<String, dynamic>? signed;
    try {
      signed = await _signer(scanId, files.keys.toList());
    } catch (e) {
      if (kDebugMode) debugPrint('[CloudinaryService] Signing failed: $e');
      return results;
    }
    if (signed == null) return results;

    final cloudName = signed['cloudName'] as String?;
    final apiKey = signed['apiKey'] as String?;
    final folder = signed['folder'] as String?;
    final timestamp = (signed['timestamp'] as num?)?.toInt();
    final uploads = signed['uploads'];
    if (cloudName == null || apiKey == null || folder == null || timestamp == null || uploads is! Map) {
      return results;
    }

    for (final entry in files.entries) {
      final u = uploads[entry.key];
      if (u is! Map) continue;
      final publicId = u['publicId'] as String?;
      final signature = u['signature'] as String?;
      if (publicId == null || signature == null) continue;

      final url = await _uploadSigned(
        entry.value,
        cloudName: cloudName,
        apiKey: apiKey,
        folder: folder,
        timestamp: timestamp,
        publicId: publicId,
        signature: signature,
      );
      if (url != null && url.isNotEmpty) results[entry.key] = url;
    }

    return results;
  }

  void close() {
    _client.close();
  }
}
