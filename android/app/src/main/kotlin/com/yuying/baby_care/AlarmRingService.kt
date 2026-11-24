package com.yuying.baby_care

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/**
 * 持续播放闹钟铃声的前台服务。
 *
 * 铃声走 USAGE_ALARM 通道（受手机闹钟音量控制），循环播放，
 * 用户点击通知「停止响铃」或超过 [MAX_RING_MS] 后自动结束。
 */
class AlarmRingService : Service() {
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStopTask = Runnable { stopSelf() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(AlarmReceiver.EXTRA_TITLE) ?: "提醒"
        val body = intent?.getStringExtra(AlarmReceiver.EXTRA_BODY) ?: ""

        startForegroundCompat(buildNotification(title, body))
        acquireWakeLock()
        startRinging()

        handler.removeCallbacks(autoStopTask)
        handler.postDelayed(autoStopTask, MAX_RING_MS)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStopTask)
        stopRinging()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startRinging() {
        stopRinging()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: return
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(this@AlarmRingService, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Exception) {
            stopRinging()
        }
    }

    private fun stopRinging() {
        try {
            player?.stop()
        } catch (_: Exception) {
            // 未进入播放态时 stop 会抛异常，忽略即可。
        }
        try {
            player?.release()
        } catch (_: Exception) {
            // 释放失败不影响后续流程。
        }
        player = null
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "yuying:alarm_ring").apply {
            setReferenceCounted(false)
            acquire(MAX_RING_MS + 60_000L)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MANIFEST)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun buildNotification(title: String, body: String): Notification {
        ensureChannel()
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
        }
        @Suppress("DEPRECATION")
        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(openAppIntent())
            .addAction(
                android.R.drawable.ic_media_pause,
                "停止响铃",
                stopRingIntent(),
            )
        return builder.build()
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(this, REQ_OPEN, intent, flagImmutable())
    }

    private fun stopRingIntent(): PendingIntent {
        val intent = Intent(this, AlarmRingService::class.java).setAction(ACTION_STOP)
        return PendingIntent.getService(this, REQ_STOP, intent, flagImmutable())
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "闹钟提醒",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "到点持续响铃的喂奶 / 儿保 / 疫苗提醒"
            // 铃声由 MediaPlayer 播放，通知通道静音避免重复。
            setSound(null, null)
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_STOP = "com.yuying.baby_care.ACTION_STOP_RING"
        private const val CHANNEL_ID = "yuying_alarm_ring"
        private const val NOTIF_ID = 9001
        private const val FALLBACK_ID = 9002
        private const val REQ_OPEN = 9101
        private const val REQ_STOP = 9102
        private const val MAX_RING_MS = 5 * 60 * 1000L

        private fun flagImmutable(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

        /** 无法启动前台服务时的兜底普通通知。 */
        fun showFallbackNotification(context: Context, title: String, body: String) {
            try {
                val manager =
                    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                        manager.createNotificationChannel(
                            NotificationChannel(
                                CHANNEL_ID,
                                "闹钟提醒",
                                NotificationManager.IMPORTANCE_HIGH,
                            ).apply {
                                setSound(null, null)
                                enableVibration(true)
                            },
                        )
                    }
                }
                val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(context, CHANNEL_ID)
                } else {
                    @Suppress("DEPRECATION")
                    Notification.Builder(context).setPriority(Notification.PRIORITY_MAX)
                }
                builder
                    .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setCategory(Notification.CATEGORY_ALARM)
                    .setAutoCancel(true)
                manager.notify(FALLBACK_ID, builder.build())
            } catch (_: Exception) {
                // 通知不可用时静默忽略。
            }
        }
    }
}
