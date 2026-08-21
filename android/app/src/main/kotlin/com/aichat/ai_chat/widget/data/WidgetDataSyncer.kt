package com.aichat.ai_chat.widget.data

import android.content.Context
import org.json.JSONArray

object WidgetDataSyncer {
    
    // Flutter SharedPreferences 文件名
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    
    // Token 数据 key（Flutter 端会添加 flutter. 前缀）
    private const val KEY_TOKEN_TOTAL = "flutter.widget_data_token_total"
    private const val KEY_TOKEN_SENT = "flutter.widget_data_token_sent"
    private const val KEY_TOKEN_RECEIVED = "flutter.widget_data_token_received"
    private const val KEY_TOKEN_PRIVATE = "flutter.widget_data_token_private"
    private const val KEY_TOKEN_GROUP = "flutter.widget_data_token_group"
    private const val KEY_TOKEN_MOMENT = "flutter.widget_data_token_moment"
    private const val KEY_TOKEN_LAST_UPDATE = "flutter.widget_data_token_last_update"
    
    // 会话数据 key
    private const val KEY_CONVERSATIONS = "flutter.widget_conversations"
    private const val KEY_CONV_LAST_UPDATE = "flutter.widget_conversations_last_update"
    
    fun loadTokenData(context: Context): TokenData {
        return try {
            val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            TokenData(
                total = readNumber(prefs, KEY_TOKEN_TOTAL),
                sent = readNumber(prefs, KEY_TOKEN_SENT),
                received = readNumber(prefs, KEY_TOKEN_RECEIVED),
                privateChat = readNumber(prefs, KEY_TOKEN_PRIVATE),
                groupChat = readNumber(prefs, KEY_TOKEN_GROUP),
                moment = readNumber(prefs, KEY_TOKEN_MOMENT),
                lastUpdate = readNumber(prefs, KEY_TOKEN_LAST_UPDATE)
            )
        } catch (e: Exception) {
            // 读取失败返回空数据
            TokenData(0, 0, 0, 0, 0, 0, 0)
        }
    }

    /** shared_preferences may store Dart ints as Int, Long, or a numeric string. */
    private fun readNumber(prefs: android.content.SharedPreferences, key: String): Long {
        return when (val value = prefs.all[key]) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }
    
    fun loadConversations(context: Context): List<ConversationData> {
        return try {
            val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val jsonStr = prefs.getString(KEY_CONVERSATIONS, null) ?: return emptyList()
            
            val jsonArray = JSONArray(jsonStr)
            (0 until jsonArray.length()).mapNotNull { i ->
                try {
                    val obj = jsonArray.getJSONObject(i)
                    ConversationData(
                        id = obj.getString("id"),
                        characterId = obj.getString("character_id"),
                        characterName = obj.getString("character_name"),
                        lastMessage = obj.optString("last_message", ""),
                        lastMessageTime = obj.optLong("last_message_time", 0),
                        unreadCount = obj.optInt("unread_count", 0),
                        pinned = obj.optBoolean("pinned", false)
                    )
                } catch (e: Exception) {
                    null
                }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
}

/**
 * Token 统计数据
 */
data class TokenData(
    val total: Long,
    val sent: Long,
    val received: Long,
    val privateChat: Long,
    val groupChat: Long,
    val moment: Long,
    val lastUpdate: Long
) {
    fun formatTotal(): String = formatTokenCount(total)
    fun formatSent(): String = formatTokenCount(sent)
    fun formatReceived(): String = formatTokenCount(received)
    fun formatPrivateChat(): String = formatTokenCount(privateChat)
    fun formatGroupChat(): String = formatTokenCount(groupChat)
    fun formatMoment(): String = formatTokenCount(moment)
    
    companion object {
        fun formatTokenCount(count: Long): String {
            return when {
                count >= 1_000_000 -> String.format("%.1fM", count / 1_000_000.0)
                count >= 1_000 -> String.format("%.1fK", count / 1_000.0)
                else -> count.toString()
            }
        }
    }
}

/**
 * 会话数据
 */
data class ConversationData(
    val id: String,
    val characterId: String,
    val characterName: String,
    val lastMessage: String,
    val lastMessageTime: Long,
    val unreadCount: Int,
    val pinned: Boolean
) {
    fun getDisplayName(): String = characterName.take(8)
    
    fun getPreviewMessage(maxLength: Int = 25): String {
        return if (lastMessage.length > maxLength) {
            lastMessage.take(maxLength) + "..."
        } else {
            lastMessage
        }
    }
    
    fun formatRelativeTime(): String {
        if (lastMessageTime == 0L) return ""
        
        val now = System.currentTimeMillis()
        val diff = now - lastMessageTime
        
        return when {
            diff < 0 -> "刚刚"
            diff < 60_000 -> "刚刚"
            diff < 3600_000 -> "${diff / 60_000}分钟前"
            diff < 86400_000 -> "${diff / 3600_000}小时前"
            diff < 172800_000 -> "昨天"
            diff < 604800_000 -> "${diff / 86400_000}天前"
            else -> {
                val cal = java.util.Calendar.getInstance().apply { timeInMillis = lastMessageTime }
                "${cal.get(java.util.Calendar.MONTH) + 1}/${cal.get(java.util.Calendar.DAY_OF_MONTH)}"
            }
        }
    }
}