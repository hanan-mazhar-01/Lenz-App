import 'dart:io' show Platform;
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stable id for this phone, used only so the server can give the free scans
/// once per device (and not again for every new e-mail address).
///
/// Android: the system `ANDROID_ID` (kept across reinstalls). iOS: the vendor
/// id. If neither can be read, a random id is created once and kept in the
/// app's storage. The server stores only a hash of it.
class DeviceIdService {
  DeviceIdService({Future<String?> Function()? platformId})
      : _platformId = platformId ?? _readPlatformId;

  static const MethodChannel _channel = MethodChannel('com.veradostudio.lenz/device');
  static const String _fallbackKey = 'device_id_fallback';

  final Future<String?> Function() _platformId;
  String? _cached;

  Future<String> id() async {
    final cached = _cached;
    if (cached != null) return cached;

    String? value;
    try {
      value = await _platformId();
    } catch (e) {
      if (kDebugMode) debugPrint('[DeviceId] platform id unavailable: $e');
    }
    // Some devices report a blank or a well-known placeholder id.
    if (value == null || value.length < 8 || _knownBadIds.contains(value)) {
      value = await _fallbackId();
    }
    if (kDebugMode) debugPrint('[DeviceId] id=$value');
    return _cached = value;
  }

  static const Set<String> _knownBadIds = {
    '9774d56d682e549c', // the notorious shared ANDROID_ID of some old builds
    '00000000-0000-0000-0000-000000000000',
  };

  static Future<String?> _readPlatformId() async {
    if (Platform.isAndroid) {
      return _channel.invokeMethod<String>('androidId');
    }
    if (Platform.isIOS) {
      return (await DeviceInfoPlugin().iosInfo).identifierForVendor;
    }
    return null;
  }

  Future<String> _fallbackId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_fallbackKey);
    if (id == null || id.length < 8) {
      final rnd = Random.secure();
      id = 'app-${List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join()}';
      await prefs.setString(_fallbackKey, id);
    }
    return id;
  }
}
