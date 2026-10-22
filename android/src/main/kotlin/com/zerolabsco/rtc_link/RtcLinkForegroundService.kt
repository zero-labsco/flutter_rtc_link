package com.zerolabsco.rtc_link

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Microphone foreground service.
 * 麦克风前台服务。
 *
 * Android 14+ (API 34+) kills background recording with a `SecurityException`
 * unless a foreground service with type `microphone` is running. This service
 * is the only way to keep publishing / voice intercom alive while the app is
 * backgrounded.
 * Android 14+（API 34+）在没有运行 `microphone` 类型前台服务时会以
 * `SecurityException` 杀掉后台录音。该服务是应用退到后台后仍能继续推流 /
 * 语音对讲的唯一手段。
 */
class RtcLinkForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "rtc_link_recording"
        const val NOTIFICATION_ID = 0x5254 // 'RT'
        const val ACTION_START = "com.zerolabsco.rtc_link.action.START"
        const val ACTION_STOP = "com.zerolabsco.rtc_link.action.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        @Volatile
        private var running = false

        /** Whether the service is currently running. / 服务当前是否正在运行。 */
        fun isRunning(): Boolean = running

        /** Starts the service (idempotent). / 启动服务（幂等）。 */
        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, RtcLinkForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** Stops the service. / 停止服务。 */
        fun stop(context: Context) {
            val intent = Intent(context, RtcLinkForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.action) {
            ACTION_STOP -> {
                running = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                START_NOT_STICKY
            }

            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "RTC Link"
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Recording in progress"
                startForegroundWithType(title, text)
                running = true
                START_STICKY
            }
        }
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Declares the `microphone` foreground-service type where the platform
     * supports it (API 29+). On API 34+ this is mandatory; older versions
     * simply start the service without a typed contract.
     * 在平台支持处（API 29+）声明 `microphone` 前台服务类型。API 34+ 上这是
     * 强制的；更早版本直接以无类型方式启动服务。
     */
    private fun startForegroundWithType(title: String, text: String) {
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.presence_audio_online)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "RTC Link recording",
            // Low importance: no sound, still visible in the status bar.
            // 低重要性：无声音，仍显示在状态栏。
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Ongoing audio/video publishing and voice intercom."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }
}
