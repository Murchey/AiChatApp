import 'package:flutter/cupertino.dart';
import '../screens/splash_screen.dart';
import '../screens/home_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/character_list_screen.dart';
import '../screens/character_detail_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String home = '/home';
  static const String chat = '/chat';
  static const String characterList = '/characters';
  static const String characterDetail = '/character-detail';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return CupertinoPageRoute(builder: (_) => const SplashScreen());
      case home:
        return CupertinoPageRoute(builder: (_) => const HomeScreen());
      case chat:
        final args = settings.arguments as Map<String, dynamic>;
        return CupertinoPageRoute(
          builder: (_) => ChatScreen(
            conversationId: args['conversationId'],
            characterName: args['characterName'],
            characterAvatar: args['characterAvatar'],
          ),
        );
      case characterList:
        return CupertinoPageRoute(builder: (_) => const CharacterListScreen());
      case characterDetail:
        final characterId = settings.arguments as String;
        return CupertinoPageRoute(
          builder: (_) => CharacterDetailScreen(characterId: characterId),
        );
      default:
        return CupertinoPageRoute(
          builder: (_) => CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(middle: Text('错误')),
            child: Center(child: Text('未找到路由: ${settings.name}')),
          ),
        );
    }
  }
}
