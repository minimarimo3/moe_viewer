import 'dart:developer' show log;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/core/providers/settings_provider.dart';
import 'src/core/providers/thumbnail_provider.dart';
import 'src/core/services/ai_service.dart';
import 'src/core/services/duplicate_service.dart';
import 'src/core/ui/app_themes.dart';
import 'src/core/utils/pixiv_utils.dart';
import 'src/features/dispatch/dispatch_screen.dart';

void main() async {
  log('App started');
  WidgetsFlutterBinding.ensureInitialized();

  // デフォルトの別名を初期化
  await ReservedTags.initializeDefaultAliases();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ThumbnailProvider()),
        Provider(
          create: (_) => AiService(),
          dispose: (_, aiService) => aiService.dispose(),
        ),
        Provider(create: (_) => DuplicateService()),
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
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: settings.themeMode,
          home: const DispatchScreen(),
        );
      },
    );
  }
}
