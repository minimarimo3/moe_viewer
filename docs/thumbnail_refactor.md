# サムネイル最適化リファクタリング概要

このドキュメントは、ギャラリーのサムネイル生成・キャッシュ・表示の最適化についての変更点と意図を簡潔にまとめたものです。

## 目的

- 大量の画像（数千〜数万）を扱う際のスクロール詰まり・UIフリーズの解消
- Isolate/computeの乱立、setStateの氾濫、メモリスパイクを防ぎ、スムーズなスクロール体験を提供

## 主な変更点

- ThumbnailProvider を新規追加（`lib/src/core/providers/thumbnail_provider.dart`）
  - ChangeNotifier を継承し、サムネイル生成要求をキューで集中管理。
  - 既存の `thumbnail_pool` を利用し、バックグラウンド実行の並列数を制御。
  - メモリLRUキャッシュ（デフォルト200枚）と既存フォーマットのディスクキャッシュへ保存。
  - 可視範囲と前後 N 件のプリフェッチを行い、遠方の要求はデプリオライズ/間引き。

- FileThumbnail を Stateless 化（`lib/src/common_widgets/file_thumbnail.dart`）
  - 内部で compute を呼ばず、Provider のキャッシュを参照して描画のみ担当。
  - Provider の Selector を使用し、対象バイト列の変化時のみ再描画。

- グリッド/リストでの優先度制御（`gallery_grid_widget_new.dart`, `gallery_list_widget.dart`）
  - VisibilityDetector で 50%以上可視になったタイミングで Provider へ高優先度リクエスト。
  - 非表示になったら要求をデプリオライズ（キャンセル/優先度低下）。
  - スクロール末端付近や可視通知でプリフェッチ範囲を更新。

- Provider の注入（`gallery_screen.dart`）
  - 画面 State で `ThumbnailProvider` を保持し、`ChangeNotifierProvider.value` で配下に供給。
  - これにより画面のライフサイクル中はキャッシュとキューが維持される。

## 動作の流れ（簡略）

1. グリッド/リストのアイテムが可視化 → Provider に高優先度リクエスト。
2. Provider はメモリ/ディスクキャッシュを照会。なければキュー投入。
3. `thumbnail_pool` の並列数制御下でサムネイルを生成→メモリ/ディスクへ保存し、`notifyListeners()`。
4. FileThumbnail は Selector で該当キーのバイト列を購読しており、利用可能になった時だけ再描画。
5. スクロールに応じて前後 20〜30 件を低優先度で先読み。

## 期待効果

- 各アイテムが個別に compute を起動しないため、Isolate生成・破棄のスパイクを抑制。
- setState の乱発を解消し、リスト/グリッド全体の再描画を極小化。
- 可視領域優先でスルスル表示。先読みでグレー埋め時間を短縮。

## 移行上の注意

- FileThumbnail は生成を行わないため、必ず上位ツリーで `ThumbnailProvider` を注入してください（本変更で `gallery_screen.dart` に追加済み）。
- サムネイルのキャッシュキーやディスクファイル命名は既存ロジック（`thumbnail_service.dart`）に合わせています。

## 今後の拡張候補

- メモリキャッシュの動的サイズ調整（端末メモリに応じて）
- より厳密な可視範囲推定（MasonryGrid での正確な first/last 可視 index 取得）
- 世代別キャッシュ（表示解像度の世代を上げた際に旧世代を間引き）
