package app.ibada

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class HomeActivity : FlutterActivity() {
    private var notificationReply: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PrayerAlarm.BRIDGE)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(PrayerAlarm.status(this))
                        "replace" -> {
                            PrayerAlarm.replace(this, call.arguments as Map<*, *>)
                            result.success(null)
                        }
                        "request" -> request(call.arguments as String, result)
                        "test" -> {
                            PrayerAlarm.test(this, call.arguments as? Boolean ?: true)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("PRAYER_ALARM", error.message, null)
                }
            }
    }

    private fun request(permission: String, result: MethodChannel.Result) {
        val app = Uri.parse("package:$packageName")
        when (permission) {
            "notifications", "startupNotifications" -> {
                if (Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                ) {
                    val preferences = getPreferences(MODE_PRIVATE)
                    val asked = preferences.getBoolean("askedForNotifications", false)
                    if (!asked || shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
                        preferences.edit().putBoolean("askedForNotifications", true).apply()
                        notificationReply = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1403)
                        return
                    }
                }
                if (permission == "notifications") {
                    val intent = if (PrayerAlarm.notificationAllowed(this)) {
                        channelSettings()
                    } else {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                    startActivity(intent)
                }
            }
            "exact" -> if (Build.VERSION.SDK_INT >= 31 && !PrayerAlarm.exact(this)) {
                startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, app))
            }
            "fullScreen" -> {
                val intent = if (Build.VERSION.SDK_INT >= 34 && !PrayerAlarm.fullScreen(this)) {
                    Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, app)
                } else {
                    channelSettings()
                }
                startActivity(intent)
            }
        }
        result.success(null)
    }

    private fun channelSettings(): Intent =
        Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            .putExtra(Settings.EXTRA_CHANNEL_ID, PrayerAlarm.channelSettings(this))

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1403) {
            notificationReply?.success(null)
            notificationReply = null
        }
    }
}
