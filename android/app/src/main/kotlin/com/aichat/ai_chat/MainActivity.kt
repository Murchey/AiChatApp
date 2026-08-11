package com.aichat.ai_chat

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.aichat.ai_chat/files"
        private const val REQUEST_PICK_FILE = 0x1101
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFile" -> {
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "*/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        try {
                            startActivityForResult(intent, REQUEST_PICK_FILE)
                        } catch (e: Exception) {
                            pendingResult = null
                            result.error("LAUNCH_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PICK_FILE) {
            val pending = pendingResult
            pendingResult = null
            if (resultCode == RESULT_OK) {
                val uri = data?.data
                if (uri != null) {
                    try {
                        val (path, name) = copyUriToCache(uri)
                        pending?.success(mapOf("path" to path, "name" to name))
                    } catch (e: Exception) {
                        pending?.error("COPY_FAILED", e.message, null)
                    }
                } else {
                    // 未返回数据视为取消
                    pending?.success(null)
                }
            } else {
                // 用户取消选择
                pending?.success(null)
            }
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    /// 把 content:// URI 拷贝到应用缓存目录，返回 (绝对路径, 文件名)
    private fun copyUriToCache(uri: Uri): Pair<String, String> {
        var displayName = "file"
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx)?.let { displayName = it }
            }
        }
        val dir = File(cacheDir, "picked_files").apply { mkdirs() }
        val target = File(dir, displayName)
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        }
        return target.absolutePath to displayName
    }
}
