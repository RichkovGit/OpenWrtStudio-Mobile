package com.cogwheel.LuCIMobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.net.Uri
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
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val file = File(filePath)
                        if (file.exists()) {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    FileProvider.getUriForFile(
                                        this@MainActivity,
                                        "${applicationContext.packageName}.fileprovider",
                                        file
                                    )
                                } else {
                                    Uri.fromFile(file)
                                }
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("FILE_NOT_FOUND", "APK file not found at: $filePath", null)
                        }
                    } else {
                        result.error("INVALID_PATH", "filePath cannot be null", null)
                    }
                }
                "getDownloadDir" -> {
                    val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: cacheDir
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
