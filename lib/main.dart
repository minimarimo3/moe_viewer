import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/core/providers/ui_settings_provider.dart';
import 'src/core/providers/folder_settings_provider.dart';
import 'src/core/providers/model_provider.dart';
import 'src/core/providers/analysis_provider.dart';
import 'src/core/services/ai_service.dart';
import 'src/features/dispatch/dispatch_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        // 新Provider群
        ChangeNotifierProvider(create: (_) => UiSettingsProvider()),
        ChangeNotifierProvider(create: (_) => FolderSettingsProvider()),
        ChangeNotifierProvider(create: (_) => ModelProvider()),
        ChangeNotifierProvider(create: (_) => AnalysisProvider()),
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
    return Consumer<UiSettingsProvider>(
      builder: (context, ui, child) {
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
          themeMode: ui.themeMode,
          home: const DispatchScreen(),
        );
      },
    );
  }
}
