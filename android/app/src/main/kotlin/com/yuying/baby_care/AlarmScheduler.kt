package com.yuying.baby_care

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * 闹钟调度与持久化。
 *
 * 何时提醒由 Dart 侧决定，这里只负责用 AlarmManager 精确唤醒，
 * 并把待响闹钟写入 SharedPreferences，供重启后重排。
 */
object AlarmScheduler {
    private const val PREFS = "yuying_alarms"
    private const val KEY_ITEMS = "items"
    private const val MAX_ITEMS = 128

    data class Item(
        val id: Int,
        val atMs: Long,
        val title: String,
        val body: String,
        val tag: String,
    )

    fun schedule(
        context: Context,
        id: Int,
        atMs: Long,
        title: String,
        body: String,
        tag: String,
    ): Boolean {
        if (atMs <= System.currentTimeMillis()) {
            remove(context, id)
            return false
        }
        val item = Item(id, atMs, title, body, tag)
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = pendingIntent(context, item)
        val ok = try {
            setAlarm(manager, atMs, pending, exact = true)
            true
        } catch (_: SecurityException) {
            // 未授予精确闹钟权限时退化为非精确，仍能在稍后触发。
            try {
                setAlarm(manager, atMs, pending, exact = false)
                true
            } catch (_: Exception) {
                false
            }
        } catch (_: Exception) {
            false
        }
        if (ok) {
            save(context, item)
        } else {
            remove(context, id)
        }
        return ok
    }

    fun cancel(context: Context, id: Int) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(AlarmReceiver.ACTION_RING)
        val pending = PendingIntent.getBroadcast(context, id, intent, flagImmutable())
        manager.cancel(pending)
        pending.cancel()
        remove(context, id)
    }

    /** 按类型取消，例如只清掉喂奶提醒而保留儿保 / 疫苗。 */
    fun cancelTagged(context: Context, tag: String) {
        for (item in load(context)) {
            if (item.tag == tag) cancel(context, item.id)
        }
    }

    fun cancelAll(context: Context) {
        for (item in load(context)) {
            cancel(context, item.id)
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun remove(context: Context, id: Int) {
        val remain = load(context).filterNot { it.id == id }
        write(context, remain)
    }

    /** 开机或应用更新后重排尚未到点的闹钟。 */
    fun rescheduleAll(context: Context) {
        val now = System.currentTimeMillis()
        val remain = ArrayList<Item>()
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (item in load(context)) {
            if (item.atMs <= now) continue
            try {
                setAlarm(manager, item.atMs, pendingIntent(context, item), exact = true)
                remain.add(item)
            } catch (_: Exception) {
                try {
                    setAlarm(manager, item.atMs, pendingIntent(context, item), exact = false)
                    remain.add(item)
                } catch (_: Exception) {
                    // 重排失败则丢弃，避免无限累积无效条目。
                }
            }
        }
        write(context, remain)
    }

    fun load(context: Context): List<Item> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ITEMS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val obj = array.optJSONObject(index) ?: return@mapNotNull null
                Item(
                    id = obj.optInt("id"),
                    atMs = obj.optLong("atMs"),
                    title = obj.optString("title"),
                    body = obj.optString("body"),
                    tag = obj.optString("tag"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun setAlarm(
        manager: AlarmManager,
        atMs: Long,
        pending: PendingIntent,
        exact: Boolean,
    ) {
        val canExact = exact && canScheduleExact(manager)
        if (canExact) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pending)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pending)
        }
    }

    private fun canScheduleExact(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()

    private fun save(context: Context, item: Item) {
        val items = load(context).filterNot { it.id == item.id } + item
        write(context, items.takeLast(MAX_ITEMS))
    }

    private fun write(context: Context, items: List<Item>) {
        val array = JSONArray()
        for (item in items) {
            array.put(
                JSONObject().apply {
                    put("id", item.id)
                    put("atMs", item.atMs)
                    put("title", item.title)
                    put("body", item.body)
                    put("tag", item.tag)
                },
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ITEMS, array.toString())
            .apply()
    }

    private fun pendingIntent(context: Context, item: Item): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_RING
            putExtra(AlarmReceiver.EXTRA_ID, item.id)
            putExtra(AlarmReceiver.EXTRA_TITLE, item.title)
            putExtra(AlarmReceiver.EXTRA_BODY, item.body)
        }
        return PendingIntent.getBroadcast(context, item.id, intent, flagImmutable())
    }

    private fun flagImmutable(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
}
