package com.yuying.baby_care

import android.app.Activity
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * 仅负责 Android Storage Access Framework 的文档选择与流式读写。
 * 备份内容的结构校验与业务处理全部由 Dart 侧完成。
 */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickSaveLocation" -> pickDocument(
                        action = Intent.ACTION_CREATE_DOCUMENT,
                        fileName = call.argument<String>("fileName"),
                        result = result
                    )
                    "pickOpenFile" -> pickDocument(
                        action = Intent.ACTION_OPEN_DOCUMENT,
                        fileName = null,
                        result = result
                    )
                    "readText" -> readText(call.argument<String>("uri"), result)
                    "writeText" -> writeText(
                        call.argument<String>("uri"),
                        call.argument<String>("content"),
                        result
                    )
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FEED_STATUS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, FeedStatusService::class.java)
                        putMillisArg(intent, call, "lastFeedMs", FeedStatusService.EXTRA_LAST)
                        putMillisArg(intent, call, "nextFeedMs", FeedStatusService.EXTRA_NEXT)
                        startFeedStatusService(intent)
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, FeedStatusService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RINGTONE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDefaultAlarmUri" -> {
                        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        result.success(uri?.toString())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val ok = AlarmScheduler.schedule(
                            context = this,
                            id = call.argument<Int>("id") ?: 0,
                            atMs = call.argument<Number>("atMs")?.toLong() ?: 0L,
                            title = call.argument<String>("title") ?: "提醒",
                            body = call.argument<String>("body") ?: "",
                            tag = call.argument<String>("tag") ?: ""
                        )
                        result.success(ok)
                    }
                    "cancel" -> {
                        AlarmScheduler.cancel(this, call.argument<Int>("id") ?: 0)
                        result.success(null)
                    }
                    "cancelTagged" -> {
                        AlarmScheduler.cancelTagged(this, call.argument<String>("tag") ?: "")
                        result.success(null)
                    }
                    "cancelAll" -> {
                        AlarmScheduler.cancelAll(this)
                        result.success(null)
                    }
                    "scheduledIds" -> {
                        result.success(AlarmScheduler.load(this).map { it.id })
                    }
                    "stopRinging" -> {
                        stopService(Intent(this, AlarmRingService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun putMillisArg(
        intent: Intent,
        call: MethodCall,
        name: String,
        extra: String,
    ) {
        if (!call.hasArgument(name)) return
        intent.putExtra(extra, call.argument<Number>(name)?.toLong() ?: 0L)
    }

    private fun startFeedStatusService(intent: Intent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
            // Android 12+ 在后台启动前台服务可能被系统拒绝，忽略即可。
        }
    }

    private fun pickDocument(action: String, fileName: String?, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "已有文件选择正在进行", null)
            return
        }
        pendingResult = result
        val intent = Intent(action).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            if (fileName != null) {
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
        }
        try {
            startActivityForResult(intent, REQUEST_PICK)
        } catch (e: Exception) {
            pendingResult = null
            result.error("unavailable", "无法打开系统文件选择器", e.message)
        }
    }

    @Deprecated("FlutterActivity 仍以 onActivityResult 返回系统文件选择结果")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK) return
        val result = pendingResult
        pendingResult = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri: Uri? = data?.data
        if (uri == null) {
            result.success(null)
        } else {
            result.success(uri.toString())
        }
    }

    private fun readText(uriString: String?, result: MethodChannel.Result) {
        if (uriString.isNullOrEmpty()) {
            result.error("invalid_uri", "文件地址为空", null)
            return
        }
        try {
            val uri = Uri.parse(uriString)
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val buffer = ByteArrayOutputStream()
                val chunk = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val read = input.read(chunk)
                    if (read <= 0) break
                    total += read
                    if (total > MAX_BACKUP_BYTES) {
                        throw IllegalArgumentException("文件超过 20MB 限制")
                    }
                    buffer.write(chunk, 0, read)
                }
                buffer.toByteArray()
            } ?: throw IllegalStateException("无法读取所选文件")
            result.success(String(bytes, Charsets.UTF_8))
        } catch (e: Exception) {
            result.error("read_failed", e.message ?: "读取文件失败", null)
        }
    }

    private fun writeText(uriString: String?, content: String?, result: MethodChannel.Result) {
        if (uriString.isNullOrEmpty() || content == null) {
            result.error("invalid_args", "写入参数不完整", null)
            return
        }
        try {
            val uri = Uri.parse(uriString)
            contentResolver.openOutputStream(uri, "wt")?.use { output ->
                output.write(content.toByteArray(Charsets.UTF_8))
                output.flush()
            } ?: throw IllegalStateException("无法写入所选文件")
            result.success(true)
        } catch (e: Exception) {
            result.error("write_failed", e.message ?: "写入文件失败", null)
        }
    }

    companion object {
        private const val CHANNEL = "yuying/documents"
        private const val FEED_STATUS_CHANNEL = "yuying/feed_status"
        private const val RINGTONE_CHANNEL = "yuying/ringtone"
        private const val ALARM_CHANNEL = "yuying/alarm"
        private const val REQUEST_PICK = 4102
        private const val MAX_BACKUP_BYTES = 20 * 1024 * 1024
    }
}
