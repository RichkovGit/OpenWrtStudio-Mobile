package com.cogwheel.LuCIMobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.net.Uri
import android.provider.Settings
import android.content.pm.PackageManager
import android.content.ClipData
import java.io.File
import androidx.core.content.FileProvider
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.openwrt.studio/notifications"
    private val NOTIF_CHANNEL_ID = "router_alerts_channel"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        setupEdgeToEdge()
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Оповещения о неполадках роутера"
            val descriptionText = "Уведомления о сбоях интернета, прокси ForkOP, перегреве и безопасности"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(NOTIF_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableVibration(true)
                enableLights(true)
            }
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val id = call.argument<Int>("id") ?: (System.currentTimeMillis() % 100000).toInt()
                    val title = call.argument<String>("title") ?: "OpenWrt Studio"
                    val message = call.argument<String>("message") ?: ""

                    val intent = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    }
                    val pendingIntent = PendingIntent.getActivity(
                        this, id, intent,
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
                    )

                    val builder = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
                        .setSmallIcon(R.mipmap.ic_launcher)
                        .setContentTitle(title)
                        .setContentText(message)
                        .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setContentIntent(pendingIntent)
                        .setAutoCancel(true)

                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(id, builder.build())
                    result.success(true)
                }
                "cancelNotification" -> {
                    val id = call.argument<Int>("id")
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    if (id != null) {
                        notificationManager.cancel(id)
                    } else {
                        notificationManager.cancelAll()
                    }
                    result.success(true)
                }
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_ERROR", e.message, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file not found at: $filePath", null)
                            return@setMethodCallHandler
                        }

                        // Check unknown sources installation permission on Android 8.0+
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                            try {
                                val manageIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                    data = Uri.parse("package:$packageName")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(manageIntent)
                            } catch (_: Exception) {}
                            result.error("PERMISSION_DENIED", "Unknown source installation permission required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                FileProvider.getUriForFile(
                                    this@MainActivity,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                            } else {
                                Uri.fromFile(file)
                            }

                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                                clipData = ClipData.newRawUri("OpenWrtStudioUpdate", uri)
                            }

                            // Explicitly grant URI read permissions to resolving activities (critical for EMUI/MIUI)
                            val resInfoList = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                            for (resolveInfo in resInfoList) {
                                val pkgName = resolveInfo.activityInfo.packageName
                                grantUriPermission(pkgName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }

                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", "Failed to launch installer: ${e.message}", null)
                        }
                    } else {
                        result.error("INVALID_PATH", "filePath cannot be null", null)
                    }
                }
                "getDownloadDir" -> {
                    // Use internal cache directory "updates" subdirectory.
                    // This bypasses Android 11+ Scoped Storage blocks on /Android/data,
                    // requires no storage permissions, and is fully accessible to FileProvider via <cache-path>.
                    val dir = File(cacheDir, "updates")
                    if (!dir.exists()) {
                        dir.mkdirs()
                    }
                    result.success(dir.absolutePath)
                }
                "getDeviceAbi" -> {
                    val abi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
                    } else {
                        @Suppress("DEPRECATION")
                        Build.CPU_ABI ?: "armeabi-v7a"
                    }
                    result.success(abi)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun setupEdgeToEdge() {
        // Enable edge-to-edge layout
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        // Use WindowInsetsController instead of deprecated window flags
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller?.let {
            // Make status bar and navigation bar transparent without deprecated APIs
            it.isAppearanceLightStatusBars = false
            it.isAppearanceLightNavigationBars = false
        }
        
        // For Android 15+ (API 35+), use the modern EdgeToEdge API
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            enableModernEdgeToEdge()
        }
    }
    
    private fun enableModernEdgeToEdge() {
        try {
            // Use reflection to call EdgeToEdge.enable() for Android 15+
            val edgeToEdgeClass = Class.forName("androidx.activity.EdgeToEdge")
            val enableMethod = edgeToEdgeClass.getMethod("enable", androidx.activity.ComponentActivity::class.java)
            enableMethod.invoke(null, this)
        } catch (e: Exception) {
            // Fallback is already handled by setupEdgeToEdge()
        }
    }
}
