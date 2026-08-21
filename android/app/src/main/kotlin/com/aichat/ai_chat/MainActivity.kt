package com.aichat.ai_chat

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.aichat.ai_chat.widget.WidgetUpdateManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.aichat.ai_chat/files"
        private const val NAV_CHANNEL = "com.aichat.ai_chat/navigation"
        private const val WIDGET_CHANNEL = "com.aichat.ai_chat/widget"
        private const val REQUEST_PICK_FILE = 0x1101
        private const val REQUEST_SAVE_FILE = 0x1102
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingSaveName: String = ""
    private var pendingSaveBytes: ByteArray? = null
    private var navigationChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }

    private fun handleWidgetIntent(intent: Intent?) {
        if (intent?.action == "OPEN_CHAT") {
            val conversationId = intent.getStringExtra("conversation_id")
            if (conversationId != null) {
                // 延迟发送，等待 Flutter 引擎准备就绪
                navigationChannel?.invokeMethod("openChat", conversationId)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 初始化导航通道
        navigationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAV_CHANNEL)
        
        // 小组件更新通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidgets" -> {
                        WidgetUpdateManager.updateAllWidgets(this)
                        result.success(true)
                    }
                    "updateTokenWidget" -> {
                        WidgetUpdateManager.updateTokenWidgets(this)
                        result.success(true)
                    }
                    "updateConversationWidget" -> {
                        WidgetUpdateManager.updateConversationWidgets(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        
        // 文件操作通道
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
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("NO_PATH", "apk path is null", null)
                        } else {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "apk not found: $path", null)
                            } else {
                                installApk(file)
                                result.success(true)
                            }
                        }
                    }
                    "saveFile" -> {
                        val suggestedName = call.argument<String>("suggestedName") ?: "export.zip"
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("NO_DATA", "no data provided", null)
                        } else {
                            pendingResult = result
                            pendingSaveName = suggestedName
                            pendingSaveBytes = bytes
                            // 系统"保存文件"选择器：让用户自选保存位置与文件名
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = mimeType
                                putExtra(Intent.EXTRA_TITLE, suggestedName)
                            }
                            try {
                                startActivityForResult(intent, REQUEST_SAVE_FILE)
                            } catch (e: Exception) {
                                pendingResult = null
                                pendingSaveBytes = null
                                result.error("LAUNCH_FAILED", e.message, null)
                            }
                        }
                    }
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("NO_PATH", "file path is null", null)
                        } else {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "file not found: $path", null)
                            } else {
                                try {
                                    openFileWithSystem(file)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.error("OPEN_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 通过 FileProvider 共享 APK 并触发系统安装
    private fun installApk(file: File) {
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
        }
    }

    /// 通过 FileProvider 共享文件并调用系统"打开方式"
    private fun openFileWithSystem(file: File) {
        val uri = getShareableUri(file)
        val ext = file.extension.lowercase()
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        // 直接交给系统解析"打开方式"：有可处理的应用则打开，
        // 没有则捕获 ActivityNotFoundException 提示用户
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            throw Exception("没有应用可以打开该类型的文件")
        }
    }

    /// 获取可共享的 content:// URI：
    /// FileProvider 仅映射 picked_files（cache）与 updates（external-files）目录；
    /// 文件在其他位置（如聊天导入目录 app_flutter/chat_import_*）时，
    /// 先复制到缓存共享目录再打开，避免 FileUriExposedException。
    private fun getShareableUri(file: File): Uri {
        try {
            return FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
        } catch (e: IllegalArgumentException) {
            val sharedDir = File(cacheDir, "picked_files")
            if (!sharedDir.exists()) sharedDir.mkdirs()
            val copy = File(sharedDir, file.name)
            file.copyTo(copy, overwrite = true)
            return FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                copy
            )
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
        } else if (requestCode == REQUEST_SAVE_FILE) {
            val pending = pendingResult
            pendingResult = null
            val bytes = pendingSaveBytes
            val name = pendingSaveName
            pendingSaveBytes = null
            if (resultCode == RESULT_OK && bytes != null) {
                val uri = data?.data
                if (uri != null) {
                    try {
                        // 写入用户选择的保存位置
                        contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                        pending?.success(mapOf("name" to name))
                    } catch (e: Exception) {
                        pending?.error("WRITE_FAILED", e.message, null)
                    }
                } else {
                    pending?.success(null)
                }
            } else {
                // 用户取消保存
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
