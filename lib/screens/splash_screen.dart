import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/splash_icon_view.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    await authProvider.init();

    if (!mounted) return;

    if (authProvider.isLoggedIn) {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else {
      _showLoginDialog();
    }
  }

  void _showLoginDialog() {
    final controller = TextEditingController();

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('欢迎使用 AiChat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text('请输入你的昵称开始聊天'),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: controller,
              placeholder: '你的昵称',
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final nickname = controller.text.trim();
              if (nickname.isNotEmpty) {
                await context.read<AuthProvider>().login(nickname);
                if (mounted) {
                  Navigator.pushReplacementNamed(context, AppRoutes.home);
                }
              }
            },
            child: const Text('开始'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return CupertinoPageScaffold(
      backgroundColor:
          context.isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      child: SizedBox.expand(
        child: SplashIconView(imagePath: settings.splashIconPath),
      ),
    );
  }
}
