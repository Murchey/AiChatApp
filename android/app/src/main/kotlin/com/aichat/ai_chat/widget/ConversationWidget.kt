package com.aichat.ai_chat.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import com.aichat.ai_chat.MainActivity
import com.aichat.ai_chat.R
import com.aichat.ai_chat.widget.data.ConversationData
import com.aichat.ai_chat.widget.data.WidgetDataSyncer

class ConversationWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    companion object {
        private data class Row(
            val containerId: Int,
            val nameId: Int,
            val previewId: Int,
            val timeId: Int,
        )

        private val rows = listOf(
            Row(R.id.conversation_row_1, R.id.conversation_name_1, R.id.conversation_preview_1, R.id.conversation_time_1),
            Row(R.id.conversation_row_2, R.id.conversation_name_2, R.id.conversation_preview_2, R.id.conversation_time_2),
            Row(R.id.conversation_row_3, R.id.conversation_name_3, R.id.conversation_preview_3, R.id.conversation_time_3),
        )

        fun update(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_conversations)
            val conversations = WidgetDataSyncer.loadConversations(context).take(rows.size)
            views.setOnClickPendingIntent(R.id.conversation_root, openApp(context))
            rows.forEachIndexed { index, row ->
                val conversation = conversations.getOrNull(index)
                views.setViewVisibility(row.containerId, if (conversation == null) View.GONE else View.VISIBLE)
                if (conversation != null) {
                    views.setTextViewText(row.nameId, nameText(conversation))
                    views.setTextViewText(row.previewId, previewText(conversation))
                    views.setTextViewText(row.timeId, conversation.formatRelativeTime())
                    views.setOnClickPendingIntent(row.containerId, openConversation(context, conversation.id, index))
                }
            }
            manager.updateAppWidget(widgetId, views)
        }

        private fun nameText(conversation: ConversationData): String {
            val unread = if (conversation.unreadCount > 0) "  (${conversation.unreadCount})" else ""
            return conversation.getDisplayName() + unread
        }

        private fun previewText(conversation: ConversationData): String {
            val message = conversation.getPreviewMessage(28)
            return if (conversation.lastMessageTime > 0) "$message  ·  ${conversation.formatRelativeTime()}" else message
        }

        private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context, 2000, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        private fun openConversation(context: Context, id: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "OPEN_CHAT"
                putExtra("conversation_id", id)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context, 2100 + requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}

class ConversationWidgetReceiver : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { ConversationWidget.update(context, manager, it) }
    }
}