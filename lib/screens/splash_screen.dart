import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';

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
    return CupertinoPageScaffold(
      backgroundColor: context.accentColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(
                CupertinoIcons.chat_bubble_2_fill,
                size: 56,
                color: context.accentColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'AiChat',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '与AI角色畅聊无限',
              style: TextStyle(fontSize: 16, color: Color(0xB3FFFFFF)),
            ),
            const SizedBox(height: 48),
            const CupertinoActivityIndicator(
              color: CupertinoColors.white,
              radius: 12,
            ),
          ],
        ),
      ),
    );
  }
}
