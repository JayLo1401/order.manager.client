package org.lotzapp.order_manager_client

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Nach "Beenden erzwingen" ist der Dienst aus – mit adb-Berechtigung selbst wieder einschalten.
        ServiceEnabler.ensureEnabled(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "order_manager_client/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isServiceEnabled" -> result.success(OrderOverlayService.instance != null)

                    "canAutoEnable" -> result.success(ServiceEnabler.canWriteSecureSettings(this))

                    "openAccessibilitySettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                        }
                        result.success(null)
                    }

                    "reloadOverlayConfig" -> {
                        OrderOverlayService.instance?.reloadConfig()
                        result.success(null)
                    }

                    "previewOverlay" -> {
                        val service = OrderOverlayService.instance
                        service?.preview()
                        result.success(service != null)
                    }

                    "testPickup" -> {
                        val service = OrderOverlayService.instance
                        service?.testPickup()
                        result.success(service != null)
                    }

                    "setKeepScreenOn" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }

                    "playChime" -> {
                        Chime.play(this, volume = (call.argument<Double>("volume") ?: 1.0).toFloat())
                        result.success(null)
                    }

                    "openUrl" -> {
                        val ok = try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, android.net.Uri.parse(call.argument<String>("url")))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            true
                        } catch (_: Exception) {
                            false // z. B. kein Browser auf dem TV
                        }
                        result.success(ok)
                    }

                    "deviceInfo" -> result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "osVersion" to Build.VERSION.RELEASE,
                            "appVersion" to packageManager.getPackageInfo(packageName, 0).versionName,
                        )
                    )

                    else -> result.notImplemented()
                }
            }
    }
}
