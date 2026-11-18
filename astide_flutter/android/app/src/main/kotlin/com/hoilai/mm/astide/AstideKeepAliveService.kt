package com.hoilai.mm.astide

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground keep-alive service allowing 星汐 Astide to remain active in the background
 * for autonomous companion messaging and local notifications.
 */
class AstideKeepAliveService : Service() {

    companion object {
        const val CHANNEL_KEEPALIVE = "astide_keepalive"
        const val CHANNEL_MESSAGES = "astide_messages"
        const val NOTIFICATION_ID_KEEPALIVE = 1001

        @Volatile
        var isRunning: Boolean = false

        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val keepAliveChannel = NotificationChannel(
                CHANNEL_KEEPALIVE,
                "后台常驻守护",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持星汐在后台运行，以便 AI 根据时间与情境主动给你发消息"
                setShowBadge(false)
            }
            manager.createNotificationChannel(keepAliveChannel)

            val messagesChannel = NotificationChannel(
                CHANNEL_MESSAGES,
                "星汐新消息提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "AI 角色主动发送微信消息时的提醒通知"
                enableVibration(true)
            }
            manager.createNotificationChannel(messagesChannel)
        }
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        ensureChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannels(this)
        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_KEEPALIVE)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notification = builder
            .setContentTitle("星汐 Astide 陪伴模式运行中")
            .setContentText("已开启后台常驻，人物可根据时间主动给你发消息")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID_KEEPALIVE,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID_KEEPALIVE, notification)
        }

        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
