package com.aichat.ai_chat.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.aichat.ai_chat.MainActivity
import com.aichat.ai_chat.R
import com.aichat.ai_chat.widget.data.WidgetDataSyncer

class TokenWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    companion object {
        fun update(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val data = WidgetDataSyncer.loadTokenData(context)
            val views = RemoteViews(context.packageName, R.layout.widget_token)
            views.setTextViewText(R.id.token_total, data.formatTotal())
            views.setTextViewText(R.id.token_private, data.formatPrivateChat())
            views.setTextViewText(R.id.token_group, data.formatGroupChat())
            views.setTextViewText(R.id.token_moment, data.formatMoment())
            views.setTextViewText(R.id.token_updated, updateText(data.lastUpdate))
            views.setOnClickPendingIntent(R.id.token_root, openApp(context))
            manager.updateAppWidget(widgetId, views)
        }

        private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context, 1001, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        private fun updateText(timestamp: Long): String {
            if (timestamp <= 0) return "暂无数据"
            val diff = System.currentTimeMillis() - timestamp
            return when {
                diff < 60_000 -> "更新于刚刚"
                diff < 3_600_000 -> "更新于 ${diff / 60_000}分钟前"
                diff < 86_400_000 -> "更新于 ${diff / 3_600_000}小时前"
                else -> "更新于今天"
            }
        }
    }
}

class TokenWidgetReceiver : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { TokenWidget.update(context, manager, it) }
    }
}