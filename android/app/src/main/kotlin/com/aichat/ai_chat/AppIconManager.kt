package com.aichat.ai_chat

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build

/** Precompiled launcher aliases; arbitrary bitmaps are used only by pinned shortcuts. */
object AppIconManager {
    private const val SHORTCUT_ID = "aichat-custom-icon"
    fun apply(activity: Activity, mode: String) {
        require(mode in listOf("system", "light", "dark")) { "Unknown icon mode" }
        val selected = when (mode) {
            "dark" -> "Dark"
            "light" -> "Light"
            else -> "System"
        }
        val pm = activity.packageManager
        // Enable first so that the package always has a launcher entry.
        pm.setComponentEnabledSetting(ComponentName(activity, "${activity.packageName}.Launcher$selected"), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        for (name in listOf("System", "Light", "Dark")) {
            if (name != selected) pm.setComponentEnabledSetting(ComponentName(activity, "${activity.packageName}.Launcher$name"), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
        }
        activity.getSharedPreferences("app_icons",0).edit().putString("mode",mode).apply()
    }
    private fun shortcut(activity: Activity, path: String): ShortcutInfo {
        val bitmap = BitmapFactory.decodeFile(path) ?: error("无法读取快捷方式图片")
        // Icon retains the bitmap until Android parcels the ShortcutInfo.
        // Recycling here would invalidate the pending pin/update request.
        return ShortcutInfo.Builder(activity, SHORTCUT_ID).setShortLabel("AiChat")
                .setIcon(Icon.createWithBitmap(bitmap))
                .setIntent(Intent(activity, MainActivity::class.java).setAction(Intent.ACTION_VIEW))
                .build()
    }
    fun pin(activity: Activity, path: String): String {
        if (Build.VERSION.SDK_INT < 26) return "unsupported"
        val manager = activity.getSystemService(ShortcutManager::class.java)
        if (!manager.isRequestPinShortcutSupported) return "unsupported"
        val accepted = manager.requestPinShortcut(shortcut(activity,path), null)
        return if (accepted) "requested" else "failed"
    }
    fun status(activity: Activity): String {
        if (Build.VERSION.SDK_INT < 26) return "unsupported"
        return if (activity.getSystemService(ShortcutManager::class.java).pinnedShortcuts.any { it.id == SHORTCUT_ID }) "pinned" else "not_pinned"
    }
    fun refresh(activity: Activity, path: String?): String {
        if (Build.VERSION.SDK_INT < 26 || path == null) return "success"
        val manager = activity.getSystemService(ShortcutManager::class.java)
        if (manager.pinnedShortcuts.none { it.id == SHORTCUT_ID }) return "not_pinned"
        return if (manager.updateShortcuts(listOf(shortcut(activity,path)))) "success" else "failed"
    }
}
