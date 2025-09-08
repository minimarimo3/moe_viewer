import 'dart:async';
import 'dart:collection' show LinkedHashMap, MapBase;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../services/thumbnail_pool.dart';
import '../services/thumbnail_service.dart';

/// サムネイルの優先度。
/// 値が小さいほど優先度が高い。
class ThumbnailPriority {
  static const int high = 0;
  static const int normal = 5;
  static const int low = 10;
}

class _QueueEntry {
  final String key;
  final String filePath;
  final int width;
  final int? height;
  final bool highQuality;
  int priority;
  DateTime enqueuedAt;
  bool canceled = false;

  _QueueEntry({
    required this.key,
    required this.filePath,
    required this.width,
    required this.height,
    required this.highQuality,
    required this.priority,
  }) : enqueuedAt = DateTime.now();
}

/// LRU風に先頭が最も古いエントリになる LinkedHashMap を利用
class _LruMap<K, V> extends MapBase<K, V> {
  _LruMap({required this.maxEntries}) : _inner = LinkedHashMap<K, V>();
  final int maxEntries;
  final LinkedHashMap<K, V> _inner;

  @override
  V? operator [](Object? key) => _inner[key as K];

  @override
  void operator []=(K key, V value) {
    if (_inner.length >= maxEntries && !_inner.containsKey(key)) {
      _inner.remove(_inner.keys.first);
    }
    if (_inner.containsKey(key)) _inner.remove(key);
    _inner[key] = value;
  }

  @override
  void clear() => _inner.clear();

  @override
  Iterable<K> get keys => _inner.keys;

  @override
  V? remove(Object? key) => _inner.remove(key);
}

class ThumbnailProvider extends ChangeNotifier {
  ThumbnailProvider({int memoryCacheSize = 200})
    : _memoryCache = _LruMap<String, Uint8List>(maxEntries: memoryCacheSize);

  // メモリキャッシュ（LRU）
  final _LruMap<String, Uint8List> _memoryCache;

  // flutter_cache_managerによるディスクキャッシュ
  final BaseCacheManager _cacheManager = DefaultCacheManager();

  // キューと進行中
  final Map<String, _QueueEntry> _queued = {}; // key -> entry
  final Map<String, _QueueEntry> _inFlight = {}; // key -> entry

  // 待機者（UIがFutureで待ちたい場合に使用可能）
  final Map<String, List<Completer<Uint8List?>>> _waiters = {};

  // 可視ウィンドウ追跡（プリフェッチ制御用）
  Set<int> _visibleIndices = <int>{};

  // 自動スクロール状態の追跡
  bool _isAutoScrolling = false;

  /// 自動スクロール状態を設定
  void setAutoScrolling(bool isScrolling) {
    if (_isAutoScrolling != isScrolling) {
      _isAutoScrolling = isScrolling;
      if (!_isAutoScrolling) {
        // スクロール完了時にキューを再開
        _pumpQueue();
      }
    }
  }

  /// 自動スクロール中かどうかを取得
  bool get isAutoScrolling => _isAutoScrolling;

  // キャッシュキー生成
  static String makeKey(String filePath, int width, int? height, bool hq) {
    final h = height?.toString() ?? 'auto';
    final q = hq ? 'hq' : 'std';
    return '${filePath}_w${width}_h${h}_$q';
  }

  Uint8List? getCachedByKey(String key) => _memoryCache[key];

  Uint8List? getCached(
    String filePath,
    int width, {
    int? height,
    bool highQuality = false,
  }) {
    return _memoryCache[makeKey(filePath, width, height, highQuality)];
  }

  /// UIが個別に待ちたい場合用。通常は Selector で監視すれば十分。
  Future<Uint8List?> waitFor(String key) {
    final c = Completer<Uint8List?>();
    _waiters.putIfAbsent(key, () => []).add(c);
    return c.future;
  }

  /// サムネイル生成（または読み出し）を要求。存在すれば即座に通知。
  void requestThumbnail(
    String filePath,
    int width, {
    int? height,
    bool highQuality = false,
    int priority = ThumbnailPriority.normal,
  }) {
    final key = makeKey(filePath, width, height, highQuality);
    // 既にメモリにある
    final cached = _memoryCache[key];
    if (cached != null) {
      // 念のため通知（新規購読者向け）
      notifyListeners();
      return;
    }

    // 自動スクロール中はキューに追加しない（キャッシュにないサムネイルは保留）
    if (_isAutoScrolling) {
      return;
    }

    // 既に進行中なら優先度だけ更新
    final inflight = _inFlight[key];
    if (inflight != null) {
      inflight.priority = priority;
      return;
    }

    // キューに存在すれば優先度更新
    final queued = _queued[key];
    if (queued != null) {
      queued.priority = priority;
      queued.enqueuedAt = DateTime.now();
      return;
    }

    // 新規エントリ追加
    final entry = _QueueEntry(
      key: key,
      filePath: filePath,
      width: width,
      height: height,
      highQuality: highQuality,
      priority: priority,
    );
    _queued[key] = entry;
    _pumpQueue();
  }

  /// キューから除去（未開始ならキャンセル、実行中は結果を破棄）
  void cancelOrDeprioritize(
    String filePath,
    int width, {
    int? height,
    bool highQuality = false,
    bool cancel = false,
  }) {
    final key = makeKey(filePath, width, height, highQuality);
    final q = _queued[key];
    if (q != null) {
      if (cancel) {
        q.canceled = true;
        _queued.remove(key);
      } else {
        q.priority = ThumbnailPriority.low;
      }
      return;
    }
    final f = _inFlight[key];
    if (f != null && !cancel) {
      f.priority = ThumbnailPriority.low; // 実行中は優先度だけ下げる（結果は破棄しない）
    }
  }

  /// 可視ウィンドウを更新し、可視は高優先度、前後は低優先度でプリフェッチ。
  void updateVisibleWindow({
    required Iterable<int> visibleIndices,
    required List<dynamic> items,
    required int width,
    int? height,
    bool highQuality = false,
    int prefetchRadius = 20,
  }) {
    _visibleIndices = visibleIndices.toSet();
    if (_visibleIndices.isEmpty) return;

    final minIndex = _visibleIndices.reduce((a, b) => a < b ? a : b);
    final maxIndex = _visibleIndices.reduce((a, b) => a > b ? a : b);

    // 可視アイテムを高優先度で要求
    for (final i in _visibleIndices) {
      if (i < 0 || i >= items.length) continue;
      final item = items[i];
      if (item is File) {
        requestThumbnail(
          item.path,
          width,
          height: height,
          highQuality: highQuality,
          priority: ThumbnailPriority.high,
        );
      }
    }

    // 前後を低優先度でプリフェッチ
    final startPrefetch = (minIndex - prefetchRadius).clamp(
      0,
      items.length - 1,
    );
    final endPrefetch = (maxIndex + prefetchRadius).clamp(0, items.length - 1);
    for (int i = startPrefetch; i <= endPrefetch; i++) {
      if (_visibleIndices.contains(i)) continue;
      final item = items[i];
      if (item is File) {
        requestThumbnail(
          item.path,
          width,
          height: height,
          highQuality: highQuality,
          priority: ThumbnailPriority.low,
        );
      }
    }

    // 遠方のキューはデプリオライズ or キャンセル
    final nearSet = <String>{};
    for (int i = startPrefetch; i <= endPrefetch; i++) {
      if (i < 0 || i >= items.length) continue;
      final item = items[i];
      if (item is File) {
        nearSet.add(makeKey(item.path, width, height, highQuality));
      }
    }
    // キューにあるエントリのうち、near範囲外は優先度を下げる/キャンセル
    final toCancel = <String>[];
    _queued.forEach((key, entry) {
      if (!nearSet.contains(key)) {
        // キューが肥大化しないよう、一定以上はキャンセル
        entry.priority = ThumbnailPriority.low;
        if (_queued.length > 500) {
          entry.canceled = true;
          toCancel.add(key);
        }
      }
    });
    for (final k in toCancel) {
      _queued.remove(k);
    }
  }

  Future<void> _pumpQueue() async {
    // 自動スクロール中は新しいタスクを開始しない
    if (_isAutoScrolling) {
      return;
    }

    // 並列実行は pool が制御。ここでは可能な限り起動する。
    // ただし、頻繁な呼び出しによる同時起動を抑えるため、マイクロタスクに積む。
    scheduleMicrotask(() async {
      if (_queued.isEmpty) return;

      // 優先度・滞留時間でソート（高優先度・古い順）
      // ソート処理を最適化: 高優先度のものだけを先に処理
      final highPriorityEntries = <_QueueEntry>[];
      final normalPriorityEntries = <_QueueEntry>[];
      final lowPriorityEntries = <_QueueEntry>[];

      for (final entry in _queued.values) {
        switch (entry.priority) {
          case ThumbnailPriority.high:
            highPriorityEntries.add(entry);
            break;
          case ThumbnailPriority.normal:
            normalPriorityEntries.add(entry);
            break;
          default:
            lowPriorityEntries.add(entry);
            break;
        }
      }

      // 各グループ内で時間順ソート
      highPriorityEntries.sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));
      normalPriorityEntries.sort(
        (a, b) => a.enqueuedAt.compareTo(b.enqueuedAt),
      );
      lowPriorityEntries.sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));

      final entries = [
        ...highPriorityEntries,
        ...normalPriorityEntries,
        ...lowPriorityEntries,
      ];

      for (final entry in entries) {
        if (entry.canceled) continue;
        // すでにinFlightに移っている可能性に注意
        if (_inFlight.containsKey(entry.key)) continue;
        // キューからinFlightへ移動
        _queued.remove(entry.key);
        _inFlight[entry.key] = entry;

        // 実行開始（poolが適切に制御）
        unawaited(
          _runOne(entry).whenComplete(() {
            _inFlight.remove(entry.key);
          }),
        );
      }
    });
  }

  Future<void> _runOne(_QueueEntry entry) async {
    if (entry.canceled) return;

    final key = entry.key;
    // flutter_cache_managerでディスクキャッシュ確認
    try {
      final h = entry.height?.toString() ?? 'auto';
      final quality = entry.highQuality ? 'hq' : 'std';
      final cacheKey =
          'thumb_${entry.filePath.hashCode}_w${entry.width}_h${h}_$quality';

      if (!entry.canceled) {
        final cachedFile = await _cacheManager.getFileFromCache(cacheKey);
        if (cachedFile != null) {
          final file = cachedFile.file;
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty) {
              _memoryCache[key] = bytes;
              _notifyKeyCompleted(key, bytes);
              return;
            }
          }
        }
      }

      // サムネイル生成
      if (entry.canceled) return;
      final bytes = await thumbnailPool.withResource(() async {
        if (entry.highQuality) {
          return computeHighQualityThumbnail(
            entry.filePath,
            entry.width,
            height: entry.height,
          );
        } else {
          return computeThumbnail(
            entry.filePath,
            entry.width,
            height: entry.height,
          );
        }
      });

      if (entry.canceled) return; // 結果を破棄

      if (bytes.isNotEmpty) {
        _memoryCache[key] = bytes;
        _notifyKeyCompleted(key, bytes);
        // flutter_cache_managerでディスクへ非同期保存
        unawaited(() async {
          try {
            await _cacheManager.putFile(cacheKey, bytes, fileExtension: '.jpg');
          } catch (_) {
            // エラーは無視（キャッシュ保存失敗は致命的ではない）
          }
        }());
      } else {
        _notifyKeyCompleted(key, null);
      }
    } catch (_) {
      _notifyKeyCompleted(key, null);
    }
  }

  void _notifyKeyCompleted(String key, Uint8List? bytes) {
    final waiters = _waiters.remove(key);
    if (waiters != null) {
      for (final c in waiters) {
        if (!c.isCompleted) c.complete(bytes);
      }
    }
    notifyListeners();
  }

  /// 画面破棄時などに呼ぶと安全
  @override
  void dispose() {
    // 以後に完了するジョブの結果は破棄
    for (final e in _queued.values) {
      e.canceled = true;
    }
    _queued.clear();
    super.dispose();
  }
}
