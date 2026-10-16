package dev.artha.artha

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands artha:// links to Dart (lib/app/links.dart): the camera app opens
 * them when it scans a pairing QR code. Also tells Dart the device's name
 * for the pairing request.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = linkOf(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.artha.artha/links").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLink" -> {
                        result.success(pending)
                        pending = null
                    }
                    "deviceName" -> result.success(deviceName())
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        linkOf(intent)?.let { channel?.invokeMethod("link", it) }
    }

    private fun linkOf(intent: Intent?): String? =
        intent?.takeIf { it.action == Intent.ACTION_VIEW }?.data?.takeIf { it.scheme == "artha" }?.toString()

    private fun deviceName(): String {
        val maker = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        val model = Build.MODEL
        return if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model"
    }
}
