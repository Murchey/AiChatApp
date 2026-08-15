import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/api_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/auto_moment_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/chat_settings_provider.dart';
import 'providers/character_provider.dart';
import 'providers/group_chat_provider.dart';
import 'providers/memory_point_provider.dart';
import 'providers/moment_notification_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/token_usage_provider.dart';
import 'providers/workshop_provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => CharacterProvider()),
        ChangeNotifierProvider(create: (_) => GroupChatProvider()),
        ChangeNotifierProvider(create: (_) => ApiProvider()),
        ChangeNotifierProvider(create: (_) => ChatSettingsProvider()),
        ChangeNotifierProvider(create: (_) => MomentNotificationProvider()),
        ChangeNotifierProvider(create: (_) => MemoryPointProvider()),
        ChangeNotifierProvider(create: (_) => AutoMomentProvider()),
        ChangeNotifierProvider(create: (_) => WorkshopProvider()),
        ChangeNotifierProvider.value(value: TokenUsageProvider.instance),
      ],
      child: const AiChatApp(),
    ),
  );
}
