package com.example.fyp

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "smart_bakery/report_exports").setMethodCallHandler { call, result ->
            if (call.method != "saveToDownloads") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val filename = call.argument<String>("filename")
            val mimeType = call.argument<String>("mimeType")
            val bytes = call.argument<ByteArray>("bytes")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                filename == null || !filename.matches(Regex("[A-Za-z0-9_.-]{1,120}")) ||
                mimeType !in setOf("application/pdf", "text/csv") ||
                bytes == null || bytes.isEmpty) {
                result.error("INVALID_EXPORT", "Invalid Android report export.", null)
                return@setMethodCallHandler
            }
            Thread {
                var uri: android.net.Uri? = null
                try {
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                        put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                        put(MediaStore.MediaColumns.RELATIVE_PATH,
                            Environment.DIRECTORY_DOWNLOADS + "/Smart Bakery")
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    val created = contentResolver.insert(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("Unable to create report file.")
                    uri = created
                    contentResolver.openOutputStream(created)?.use { it.write(bytes) }
                        ?: throw IllegalStateException("Unable to write report file.")
                    contentResolver.update(created, ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }, null, null)
                    runOnUiThread { result.success(filename) }
                } catch (error: Exception) {
                    uri?.let { runCatching { contentResolver.delete(it, null, null) } }
                    runOnUiThread {
                        result.error("EXPORT_FAILED", "Unable to save report to Downloads.", null)
                    }
                }
            }.start()
        }
    }
}
