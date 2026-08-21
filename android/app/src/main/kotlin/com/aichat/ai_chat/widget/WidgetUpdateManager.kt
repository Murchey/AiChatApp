package com.aichat.ai_chat.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * 小组件更新管理器
 * 负责在数据变化时触发小组件刷新
 */
object WidgetUpdateManager {
    
    /**
     * 更新所有 Token 小组件
     */
    fun updateTokenWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, TokenWidgetReceiver::class.java)
        )
        ids.forEach { TokenWidget.update(context, manager, it) }
    }
    
    /**
     * 更新所有会话小组件
     */
    fun updateConversationWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, ConversationWidgetReceiver::class.java)
        )
        ids.forEach { ConversationWidget.update(context, manager, it) }
    }
    
    /**
     * 更新所有小组件
     */
    fun updateAllWidgets(context: Context) {
        updateTokenWidgets(context)
        updateConversationWidgets(context)
    }
}