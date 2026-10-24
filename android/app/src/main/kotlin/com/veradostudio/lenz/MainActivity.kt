package com.veradostudio.lenz

import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth's
// Android biometric prompt implementation.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The device id the server uses to give the free scans once per device.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.veradostudio.lenz/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "androidId") {
                    result.success(Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
                } else {
                    result.notImplemented()
                }
            }
    }
}
