import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:provider/provider.dart';

import 'package:moe_viewer/src/features/albums/albums_screen.dart';
import 'package:moe_viewer/src/core/models/album.dart';
import 'package:moe_viewer/src/core/services/albums_service.dart';
import 'package:moe_viewer/src/core/services/favorites_service.dart';
import 'package:moe_viewer/src/core/providers/settings_provider.dart';

import 'albums_screen_test.mocks.dart';

// Mock classes generation
@GenerateMocks([AlbumsService, FavoritesService])
void main() {
  group('AlbumsScreen Error Handling Tests', () {
    late MockAlbumsService mockAlbumsService;
    late MockFavoritesService mockFavoritesService;
    late SettingsProvider settingsProvider;

    setUp(() {
      mockAlbumsService = MockAlbumsService();
      mockFavoritesService = MockFavoritesService();
      settingsProvider = SettingsProvider();
      
      // Configure default mock responses
      when(mockAlbumsService.listAlbums()).thenAnswer((_) async => [
        Album(
          id: 1,
          name: 'Test Album',
          createdAt: DateTime.now(),
          sortMode: 'name_asc',
        ),
      ]);
    });

    testWidgets('E1: 例外発生時のプレースホルダー表示テスト', (WidgetTester tester) async {
      // Arrange: ファイル取得で例外を発生させる
      when(mockAlbumsService.getAlbumFiles(any, sortMode: anyNamed('sortMode')))
          .thenThrow(Exception('Network error'));
      when(mockFavoritesService.listFavoriteFiles())
          .thenAnswer((_) async => <File>[]);

      // Act: アプリを構築
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: settingsProvider,
            child: const AlbumsScreen(),
          ),
        ),
      );

      // Wait for initial load
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Assert: スピナーが表示されないことを確認（エラー時の適切な処理）
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('E2: お気に入りアルバムが空の場合のプレースホルダー表示テスト', (WidgetTester tester) async {
      // Arrange: お気に入りが空
      when(mockFavoritesService.listFavoriteFiles())
          .thenAnswer((_) async => <File>[]);
      when(mockAlbumsService.getAlbumFiles(any, sortMode: anyNamed('sortMode')))
          .thenAnswer((_) async => <File>[]);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: settingsProvider,
            child: const AlbumsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Assert: 適切にプレースホルダーが表示される
      expect(find.text('お気に入り'), findsOneWidget);
    });

    testWidgets('E3: 複数アルバムのエラー時のUIの独立性テスト', (WidgetTester tester) async {
      // Arrange: 複数のアルバムを用意し、一部でエラーを発生させる
      when(mockAlbumsService.listAlbums()).thenAnswer((_) async => [
        Album(id: 1, name: 'Working Album', createdAt: DateTime.now(), sortMode: 'name_asc'),
        Album(id: 2, name: 'Error Album', createdAt: DateTime.now(), sortMode: 'name_asc'),
      ]);
      
      when(mockAlbumsService.getAlbumFiles(1, sortMode: anyNamed('sortMode')))
          .thenAnswer((_) async => <File>[]);
      when(mockAlbumsService.getAlbumFiles(2, sortMode: anyNamed('sortMode')))
          .thenThrow(Exception('Album 2 error'));
      when(mockFavoritesService.listFavoriteFiles())
          .thenAnswer((_) async => <File>[]);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: settingsProvider,
            child: const AlbumsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Assert: 正常なアルバムは表示され、エラーのアルバムも適切に処理される
      expect(find.text('Working Album'), findsOneWidget);
      expect(find.text('Error Album'), findsOneWidget);
      // スピナーが残り続けることがないことを確認
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}