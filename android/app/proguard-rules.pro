# ============================================
# ProGuard / R8 rules for AiChat
# ============================================

# ---------- Widget classes (AppWidgetProvider + data models) ----------
# R8 必须保留这些类：系统通过 AndroidManifest.xml 按全限定名实例化它们，
# 一旦被混淆或删除，小组件创建时直接 ClassNotFoundException → 闪退。
-keep class com.aichat.ai_chat.widget.TokenWidget { *; }
-keep class com.aichat.ai_chat.widget.TokenWidgetReceiver { *; }
-keep class com.aichat.ai_chat.widget.ConversationWidget { *; }
-keep class com.aichat.ai_chat.widget.ConversationWidgetReceiver { *; }
-keep class com.aichat.ai_chat.widget.WidgetUpdateManager { *; }
-keep class com.aichat.ai_chat.widget.data.** { *; }

# ---------- MainActivity ----------
# FlutterActivity 子类，系统通过 manifest 实例化
-keep class com.aichat.ai_chat.MainActivity { *; }

# ---------- FileProvider ----------
# AndroidManifest 中按全限定名引用
-keep class androidx.core.content.FileProvider { *; }
-keep class android.support.v4.content.FileProvider { *; }
