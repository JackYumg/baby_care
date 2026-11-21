package com.yuying.baby_care

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 常驻状态栏通知：展示上次喝奶时间与下次提醒倒计时，每分钟刷新一次。
 * 数据由 Flutter 侧通过 MethodChannel 写入 SharedPreferences，App 退出后仍可继续展示。
 */
class FeedStatusService : Service() {
    private val handler = Handler(Looper.getMainLooper())

    private val ticker = object : Runnable {
        override fun run() {
            notifyState()
            handler.postDelayed(this, REFRESH_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            handler.removeCallbacks(ticker)
            stopSelf()
            return START_NOT_STICKY
        }
        persist(intent)
        startForeground(NOTIFICATION_ID, buildNotification())
        handler.removeCallbacks(ticker)
        handler.post(ticker)
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(ticker)
        super.onDestroy()
    }

    private fun persist(intent: Intent?) {
        if (intent == null) return
        val editor = getSharedPreferences(PREFS, MODE_PRIVATE).edit()
        if (intent.hasExtra(EXTRA_LAST)) {
            val last = intent.getLongExtra(EXTRA_LAST, 0L)
            if (last > 0L) editor.putLong(KEY_LAST, last) else editor.remove(KEY_LAST)
        }
        if (intent.hasExtra(EXTRA_NEXT)) {
            val next = intent.getLongExtra(EXTRA_NEXT, 0L)
            if (next > 0L) editor.putLong(KEY_NEXT, next) else editor.remove(KEY_NEXT)
        }
        editor.apply()
    }

    private fun notifyState() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val last = prefs.getLong(KEY_LAST, 0L).takeIf { it > 0L }
        val next = prefs.getLong(KEY_NEXT, 0L).takeIf { it > 0L }
        val text = when {
            last == null -> "还没有喝奶记录，记录后这里显示下次时间"
            next == null -> "上次 ${clock(last)} 喝奶 · 未设置提醒"
            else -> "上次 ${clock(last)} · 下次 ${clock(next)} · ${remainText(next)}"
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_feed)
            .setContentTitle("喝奶状态")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(openAppIntent())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "喝奶状态栏",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "在状态栏与锁屏展示上次喝奶时间和下次提醒倒计时"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(this, 0, intent, flags)
    }

    private fun clock(ms: Long): String {
        val format = SimpleDateFormat("HH:mm", Locale.CHINA)
        format.timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        return format.format(Date(ms))
    }

    private fun remainText(nextMs: Long): String {
        val diff = nextMs - System.currentTimeMillis()
        val minutes = Math.abs(diff) / 60000L
        val label = if (minutes >= 60) {
            val rest = minutes % 60
            if (rest > 0) "${minutes / 60}小时${rest}分" else "${minutes / 60}小时"
        } else {
            "${minutes}分钟"
        }
        return when {
            diff >= 0 && minutes == 0L -> "即将到点"
            diff >= 0 -> "还剩 $label"
            minutes == 0L -> "刚刚到点"
            else -> "已超过 $label"
        }
    }

    companion object {
        private const val CHANNEL_ID = "feed_status"
        private const val NOTIFICATION_ID = 1001
        private const val REFRESH_INTERVAL_MS = 60_000L
        private const val PREFS = "feed_status_prefs"
        private const val KEY_LAST = "last_feed_ms"
        private const val KEY_NEXT = "next_feed_ms"

        const val ACTION_STOP = "com.yuying.baby_care.STOP_FEED_STATUS"
        const val EXTRA_LAST = "last_feed_ms"
        const val EXTRA_NEXT = "next_feed_ms"

        @Volatile
        var running = false
            private set
    }
}
