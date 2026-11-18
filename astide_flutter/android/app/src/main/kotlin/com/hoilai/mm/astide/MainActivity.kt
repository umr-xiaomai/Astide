package com.hoilai.mm.astide

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.hoilai.mm.astide/background"
        private const val REQ_NOTIFICATIONS = 4102
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AstideKeepAliveService.ensureChannels(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startKeepAlive" -> {
                        val intent = Intent(this, AstideKeepAliveService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopKeepAlive" -> {
                        stopService(Intent(this, AstideKeepAliveService::class.java))
                        result.success(true)
                    }
                    "isKeepAliveRunning" -> {
                        result.success(AstideKeepAliveService.isRunning)
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                                PackageManager.PERMISSION_GRANTED
                            ) {
                                result.success(true)
                            } else {
                                pendingPermissionResult?.success(false)
                                pendingPermissionResult = result
                                requestPermissions(
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    REQ_NOTIFICATIONS
                                )
                            }
                        } else {
                            result.success(true)
                        }
                    }
                    "showMessageNotification" -> {
                        val title = call.argument<String>("title") ?: "星汐 Astide"
                        val body = call.argument<String>("body") ?: ""
                        val notifId = call.argument<Int>("notificationId")
                            ?: (System.currentTimeMillis() and 0x7FFFFFFF).toInt()
                        showMessageNotification(title, body, notifId)
                        result.success(true)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                            }
                            result.success(true)
                        } catch (_: Throwable) {
                            try {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                result.success(true)
                            } catch (_: Throwable) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun showMessageNotification(title: String, body: String, notifId: Int) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        AstideKeepAliveService.ensureChannels(this)

        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            notifId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, AstideKeepAliveService.CHANNEL_MESSAGES)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notification = builder
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notifId, notification)
    }
}
