# サムネイル最適化リファクタリング概要

このドキュメントでは、flutter_cache_manager: ^3.4.1への移行により行われたサムネイルキャッシュシステムの改善についてまとめています。

## 主な変更点

- ThumbnailProvider (ChangeNotifier) を使用したサムネイル生成の集中管理
  - 既存の `thumbnail_pool` を利用し、バックグラウンド実行の並列数を制御
  - メモリLRUキャッシュ（デフォルト200枚）は維持
  - **ディスクキャッシュを flutter_cache_manager に統一**
  - 可視範囲と前後 N 件のプリフェッチ機能は維持
  - 優先度ベースのキューシステムは維持

- FileThumbnail を Stateless 化
  - ThumbnailProvider からの Selector による効率的な更新
  - 表示時点で ThumbnailProvider にサムネイル生成を依頼

- **ディスクキャッシュの完全移行**
  - path_provider による自前キャッシュファイル管理を廃止
  - flutter_cache_manager による統一されたキャッシュ管理
  - 古いキャッシュファイル削除機能を設定画面に追加

## 新機能

- **古いキャッシュファイル削除機能**: 設定画面から手動で古い自前キャッシュファイルを削除可能
- **自動キャッシュ管理**: flutter_cache_manager による効率的なストレージ管理
- **統一されたキャッシュキー**: 一貫性のあるキャッシュキー命名規則

## 動作の流れ（簡略）

1. グリッド/リストのアイテムが可視化 → Provider に高優先度リクエスト
2. Provider はメモリキャッシュを照会、次に flutter_cache_manager でディスクキャッシュを確認
3. キャッシュがなければキュー投入し、`thumbnail_pool` の並列数制御下でサムネイルを生成
4. 生成されたサムネイルをメモリキャッシュと flutter_cache_manager に保存し、`notifyListeners()`
5. FileThumbnail は Selector で該当キーのバイト列を購読しており、利用可能になった時だけ再描画
6. スクロールに応じて前後 20〜30 件を低優先度で先読み

## 移行上の注意

- FileThumbnail は生成を行わないため、必ず上位ツリーで `ThumbnailProvider` を注入してください
- **古いキャッシュファイルは設定画面から手動削除が必要**（自動削除はしません）
- キャッシュキーやファイル命名は既存ロジックとの互換性を保持

## 今後の拡張候補

- メモリキャッシュの動的サイズ調整（端末メモリに応じて）
- より厳密な可視範囲推定（MasonryGrid での正確な first/last 可視 index 取得）
- 世代別キャッシュ（表示解像度の世代を上げた際に旧世代を間引き）

## 削除された機能

- **precacheBaseThumbnail**: ベースサムネイル事前生成機能（flutter_cache_manager のオンデマンド生成で代替）
- **path_provider ベースのディスクキャッシュ**: flutter_cache_manager に統一
- **自前ディスクキャッシュファイル管理**: サイズ制限やファイル削除ロジック
