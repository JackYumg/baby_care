package com.yuying.baby_care

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** 闹钟到点时拉起前台响铃服务。 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "提醒"
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""
        AlarmScheduler.remove(context, id)

        val serviceIntent = Intent(context, AlarmRingService::class.java).apply {
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (_: Exception) {
            // 系统限制后台启动前台服务时，至少发一条普通通知。
            AlarmRingService.showFallbackNotification(context, title, body)
        }
    }

    companion object {
        const val ACTION_RING = "com.yuying.baby_care.ACTION_RING"
        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
    }
}
