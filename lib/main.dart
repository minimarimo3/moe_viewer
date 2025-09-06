import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/core/providers/settings_provider.dart';
import 'src/core/services/ai_service.dart';
import 'src/core/services/nsfw_service.dart';
import 'src/core/utils/pixiv_utils.dart';
import 'src/features/dispatch/dispatch_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // デフォルトの別名を初期化
  await ReservedTags.initializeDefaultAliases();

  // 既存のNSFW判定データを特殊タグに移行（開発時の一回限りの処理）
  try {
    await NsfwService.instance.migrateExistingNsfwRatings();
  } catch (e) {
    log('NSFW移行処理でエラーが発生しましたが、継続します: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        Provider(
          create: (_) => AiService(),
          dispose: (_, aiService) => aiService.dispose(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          title: 'Moe Viewer',
          theme: ThemeData(
            brightness: Brightness.light,
            fontFamily: 'NotoSansJP',
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'NotoSansJP',
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: settings.themeMode,
          home: const DispatchScreen(),
        );
      },
    );
  }
}
