import 'dart:async';
import 'dart:convert';
import 'dart:developer' show log;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;

import '../models/ai_model_definition.dart';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
// import 'package:onnxruntime/onnxruntime.dart' as ort;

// --- Isolate（別部署）で実行されるコード ---

// Isolateに渡すデータの設計図
class IsolateAnalyzeRequest {
  final String filePath;
  final String labelPath;
  final SendPort replyPort;
  IsolateAnalyzeRequest(this.filePath, this.labelPath, this.replyPort);
}

void _aiIsolateEntry(IsolateInitMessage initMessage) async {
  // 常にメッセージングを初期化して ready を返す（モデルなしでもハングしないように）
  final mainSendPort = initMessage.sendPort;
  final token = initMessage.token;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);

  ModelRunner? runner;

  // モデル・ラベルが指定されている場合のみロードを試行
  if (initMessage.labelFileName.isNotEmpty &&
      initMessage.modelFileName.isNotEmpty) {
    try {
      final directory = await getApplicationSupportDirectory();
      final modelPath = '${directory.path}/${initMessage.modelFileName}';
      final labelPath = '${directory.path}/${initMessage.labelFileName}';

      // ファイル存在確認
      final modelFile = File(modelPath);
      final labelFile = File(labelPath);

      log('AI Isolate: Checking file existence...');
      log('AI Isolate: Model file exists: ${await modelFile.exists()}');
      log('AI Isolate: Label file exists: ${await labelFile.exists()}');

      if (!await modelFile.exists() || !await labelFile.exists()) {
        log('AI Isolate: Required files not found, skipping model load');
        mainSendPort.send('ready'); // ファイルが無くても ready を送信
        return;
      }

      log('AI Isolate: Files verified, starting model load...');

      // ランナー選択（拡張容易なディスパッチ）
      runner = _selectRunner(initMessage.modelId, modelPath);
      await runner.load(
        modelPath,
        labelPath,
        inputSize: initMessage.inputSize,
        inputType: initMessage.inputType,
      );
      log('AI Isolate: Model loaded successfully by ${runner.runtimeType}.');
    } catch (e) {
      log('AI Isolate: Failed to load model or labels: $e');
    }
  } else {
    log('AI Isolate: No model specified, ready without loading');
  }

  mainSendPort.send('ready'); // 準備完了をメインスレッドに通知

  await for (final request in isolateReceivePort) {
    if (request is IsolateAnalyzeRequest) {
      if (runner == null) {
        request.replyPort.send({'error': 'AIモデル未ロード'});
        continue;
      }
      try {
        final result = runner.analyze(request.filePath);
        request.replyPort.send(result);
      } catch (e, stackTrace) {
        log('AI Isolate: Error during analysis: $e');
        log('AI Isolate: Stack trace: $stackTrace');
        request.replyPort.send({'error': 'AI解析エラー'});
      }
    } else if (request == 'close') {
      await runner?.dispose();
      isolateReceivePort.close();
      break;
    }
  }
  log('AI Isolate: Closed.');
}

class IsolateInitMessage {
  final SendPort sendPort;
  final RootIsolateToken token;
  final String modelId;
  final String modelFileName;
  final String labelFileName;
  final String inputType;
  final int inputSize;
  IsolateInitMessage(
    this.sendPort,
    this.token,
    this.modelId,
    this.modelFileName,
    this.labelFileName,
    this.inputType,
    this.inputSize,
  );
}

/// ランナー共通インターフェース
abstract class ModelRunner {
  Future<void> load(
    String modelPath,
    String labelPath, {
    required int inputSize,
    required String inputType,
  });
  Map<String, dynamic> analyze(String filePath);
  Future<void> dispose();
}

/// TFLiteランナー（既存処理移植）
class TfliteModelRunner implements ModelRunner {
  late Interpreter _interpreter;
  late List<String> _labels;
  late int _inputSize;

  @override
  Future<void> load(
    String modelPath,
    String labelPath, {
    required int inputSize,
    required String inputType,
  }) async {
    _inputSize = inputSize;
    _interpreter = Interpreter.fromFile(File(modelPath));
    final labelString = await File(labelPath).readAsString();
    _labels = labelString
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) {
          final parts = line.split(',');
          return parts.length > 1 ? parts[1].replaceAll('"', '').trim() : '';
        })
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  @override
  Map<String, dynamic> analyze(String filePath) {
    log("解析を開始(TFLite)：$filePath");

    // --- 前処理 ---
    final imgBundle = _preprocess(filePath, _inputSize);

    // 入力テンソル [1, H, 3, W] (NCHW)
    final inputTensor = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (_) => List.generate(3, (_) => List.generate(_inputSize, (_) => 0.0)),
      ),
    );

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = imgBundle.image.getPixel(x, y);
        final r = pixel.r / 255.0;
        final g = pixel.g / 255.0;
        final b = pixel.b / 255.0;
        // 既存モデル互換（B,G,R の順）
        inputTensor[0][y][0][x] = b;
        inputTensor[0][y][1][x] = g;
        inputTensor[0][y][2][x] = r;
      }
    }

    final output = List.generate(1, (_) => List.filled(_labels.length, 0.0));
    _interpreter.run(inputTensor, output);

    final tags = _postprocess(output[0], _labels);
    return {
      'tags': tags.isEmpty ? ['タグが見つかりませんでした'] : tags,
      'image': imgBundle.base64Image,
    };
  }

  @override
  Future<void> dispose() async {
    _interpreter.close();
  }
}

/// TFLiteランナー（NHWC, RGB, float32）
/// - 入力: [1, H, W, 3] (NHWC), ImageNet正規化
/// - 出力: モデルにより1つ or 複数（[1, num_tags]）
/// - 後処理: シグモイド適用（JSONのusageに準拠）
///
///
/// NHWC, RGB, ImageNet 正規化の TFLite ランナー
/// - 入力 dtype: float32 or float16（自動検出）
/// - 出力 dtype: float32 を最優先、なければ float16 を使用（int 系は無視）
class TfliteNhwcModelRunner implements ModelRunner {
  late Interpreter _interpreter;
  late int _inputSize;
  // ignore: unused_field
  late String _inputType;

  late List<String> _labels;
  late int _totalTagsFromJson;
  Map<String, String>? _tagToCategory;

  late TensorType _inputTfType;

  late int _outputCount;
  late List<List<int>> _outputShapes;
  late List<TensorType> _outputTypes;
  late int _chosenOutputIndex;
  late TensorType _chosenOutputType;
  // ignore: unused_field
  late int _batchSize;
  late int _numClasses;

  static const _mean = [0.485, 0.456, 0.406];
  static const _std = [0.229, 0.224, 0.225];

  InterpreterOptions _buildOptions() {
    final options = InterpreterOptions();
    options.threads = 4;
    return options;
  }

  @override
  Future<void> load(
    String modelPath,
    String labelPath, {
    required int inputSize,
    required String inputType,
  }) async {
    _inputSize = inputSize;
    _inputType = inputType;

    await _loadLabelsFromJson(labelPath);

    _interpreter = Interpreter.fromFile(
      File(modelPath),
      options: _buildOptions(),
    );

    final inTensor = _interpreter.getInputTensor(0);
    final inShape = inTensor.shape;
    if (inShape.length != 4 ||
        inShape[0] != 1 ||
        inShape[1] != _inputSize ||
        inShape[2] != _inputSize ||
        inShape[3] != 3) {
      _interpreter.resizeInputTensor(0, [1, _inputSize, _inputSize, 3]);
      _interpreter.allocateTensors();
      log('Resized input tensor to [1, $_inputSize, $_inputSize, 3]');
    }
    _inputTfType = _interpreter.getInputTensor(0).type;
    if (!(_inputTfType == TensorType.float32 ||
        _inputTfType == TensorType.float16)) {
      throw StateError(
        'Unsupported input tensor type: $_inputTfType. Expected float32 or float16.',
      );
    }
    log('Input tensor dtype: $_inputTfType');

    // 出力列挙（allocateTensors後）
    _outputShapes = [];
    _outputTypes = [];
    _outputCount = 0;
    while (true) {
      try {
        final t = _interpreter.getOutputTensor(_outputCount);
        _outputShapes.add([...t.shape]);
        _outputTypes.add(t.type);
        _outputCount++;
      } catch (_) {
        break;
      }
    }
    if (_outputCount == 0) {
      throw StateError('No output tensors found.');
    }
    log(
      'Found $_outputCount output tensors. Shapes: $_outputShapes, Types: $_outputTypes',
    );

    // 使用する出力を決める（refined系名→クラス数一致→float系の先頭）
    final expectedClasses = _totalTagsFromJson;

    int pickByNameIndex = -1;
    for (int i = 0; i < _outputCount; i++) {
      final t = _interpreter.getOutputTensor(i);
      final type = t.type;
      final lname = t.name.toLowerCase();
      if ((lname.contains('refined') || lname.contains('refine')) &&
          (type == TensorType.float32 || type == TensorType.float16)) {
        pickByNameIndex = i;
        break;
      }
    }

    int pickByShapeIndex = -1;
    for (int i = 0; i < _outputCount; i++) {
      final type = _outputTypes[i];
      if (!(type == TensorType.float32 || type == TensorType.float16)) continue;
      final shape = _outputShapes[i];
      if (shape.isEmpty) continue;
      int classes = 1;
      for (int d = 1; d < shape.length; d++) {
        classes *= shape[d];
      }
      if (classes == expectedClasses) {
        pickByShapeIndex = i;
        break;
      }
    }

    int chosen = (pickByNameIndex >= 0)
        ? pickByNameIndex
        : (pickByShapeIndex >= 0 ? pickByShapeIndex : -1);

    if (chosen < 0) {
      chosen = _outputTypes.indexWhere((t) => t == TensorType.float32);
      if (chosen < 0) {
        chosen = _outputTypes.indexWhere((t) => t == TensorType.float16);
      }
      if (chosen < 0) {
        throw StateError(
          'No float-like output found. Outputs: types=$_outputTypes shapes=$_outputShapes',
        );
      }
      log('Warning: Using first float-like output index: $chosen');
    }

    final chosenShape = _outputShapes[chosen];
    _chosenOutputIndex = chosen;
    _chosenOutputType = _outputTypes[chosen];
    _batchSize = chosenShape[0];
    _numClasses = 1;
    for (int d = 1; d < chosenShape.length; d++) {
      _numClasses *= chosenShape[d];
    }

    log(
      'Chosen output index: $_chosenOutputIndex, shape=$chosenShape, '
      'dtype=$_chosenOutputType, numClasses=$_numClasses (expected $expectedClasses)',
    );

    if (_labels.length != _numClasses) {
      log(
        'Warning: label count (${_labels.length}) != output classes ($_numClasses).',
      );
      if (_labels.length < _numClasses) {
        final missing = _numClasses - _labels.length;
        _labels.addAll(
          List.generate(missing, (i) => 'class_${_labels.length + i}'),
        );
      } else {
        _labels = _labels.sublist(0, _numClasses);
      }
    }
  }

  @override
  Map<String, dynamic> analyze(String filePath) {
    log("解析を開始(TFLite NHWC)：$filePath");

    final imgBundle = _preprocess(filePath, _inputSize);

    // 入力テンソル
    Object inputTensor;
    if (_inputTfType == TensorType.float32) {
      inputTensor = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (y) => List.generate(_inputSize, (x) {
            final p = imgBundle.image.getPixel(x, y);
            final r = (p.r / 255.0 - _mean[0]) / _std[0];
            final g = (p.g / 255.0 - _mean[1]) / _std[1];
            final b = (p.b / 255.0 - _mean[2]) / _std[2];
            return [r, g, b];
          }, growable: false),
          growable: false,
        ),
        growable: false,
      );
    } else if (_inputTfType == TensorType.float16) {
      inputTensor = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (y) => List.generate(_inputSize, (x) {
            final p = imgBundle.image.getPixel(x, y);
            final r = (p.r / 255.0 - _mean[0]) / _std[0];
            final g = (p.g / 255.0 - _mean[1]) / _std[1];
            final b = (p.b / 255.0 - _mean[2]) / _std[2];
            return [
              _float32ToHalfBits(r),
              _float32ToHalfBits(g),
              _float32ToHalfBits(b),
            ];
          }, growable: false),
          growable: false,
        ),
        growable: false,
      );
    } else {
      throw StateError('Unsupported input dtype: $_inputTfType');
    }

    // すべての出力に対してバッファを用意（型・形状に合わせる）
    final outputs = <int, Object>{};
    for (int i = 0; i < _outputCount; i++) {
      final shape = _outputShapes[i];
      if (shape.isEmpty) {
        throw StateError('Output #$i has empty shape.');
      }
      final batch = shape[0];
      int elements = 1;
      for (int d = 1; d < shape.length; d++) {
        elements *= shape[d];
      }

      final type = _outputTypes[i];
      Object buf;
      switch (type) {
        case TensorType.float32:
          buf = List.generate(
            batch,
            (_) => List.filled(elements, 0.0),
            growable: false,
          );
          break;
        case TensorType.float16:
          // half は Uint16 ビット表現で受ける
          buf = List.generate(
            batch,
            (_) => List.filled(elements, 0),
            growable: false,
          );
          break;
        case TensorType.int64:
        case TensorType.int32:
        case TensorType.uint8:
          buf = List.generate(
            batch,
            (_) => List.filled(elements, 0),
            growable: false,
          );
          break;
        case TensorType.boolean:
          buf = List.generate(
            batch,
            (_) => List.filled(elements, false),
            growable: false,
          );
          break;
        default:
          // 未対応タイプは int で受けておく（ほぼ来ない想定）
          buf = List.generate(
            batch,
            (_) => List.filled(elements, 0),
            growable: false,
          );
          log(
            'Warning: Output #$i has unsupported dtype $type. Receiving as int.',
          );
      }
      outputs[i] = buf;
    }

    // 推論（全出力を受け取る）
    _interpreter.runForMultipleInputs([inputTensor], outputs);

    // 選択出力を取り出してシグモイド
    List<double> probs;
    if (_chosenOutputType == TensorType.float32) {
      final chosen = outputs[_chosenOutputIndex] as List<List<double>>;
      final logits = chosen[0];
      probs = List<double>.generate(
        logits.length,
        (i) => _sigmoid(logits[i]),
        growable: false,
      );
    } else if (_chosenOutputType == TensorType.float16) {
      final chosen = outputs[_chosenOutputIndex] as List<List<int>>;
      final halfs = chosen[0];
      probs = List<double>.generate(
        halfs.length,
        (i) => _sigmoid(_halfBitsToFloat32(halfs[i])),
        growable: false,
      );
    } else {
      throw StateError('Unsupported chosen output dtype: $_chosenOutputType');
    }

    // --- 分類・整形: キャラクター名/特徴に分離、yearは除外、特徴は上位10件 ---
    final scored = <_ScoredLabel>[];
    for (int i = 0; i < math.min(probs.length, _labels.length); i++) {
      scored.add(_ScoredLabel(_labels[i], probs[i]));
    }

    // 閾値を超えたもの。ゼロならフォールバックで上位Nを使う
    const threshold = 0.35; // 既存の _postprocess と整合
    final passed = scored.where((e) => e.score >= threshold).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final effective = passed.isNotEmpty
        ? passed
        : (scored..sort((a, b) => b.score.compareTo(a.score)))
              .take(50)
              .toList();

    // カテゴリ判定
    bool isYear(String label) {
      if (_tagToCategory != null) {
        final cat = _tagToCategory![label];
        if (cat != null && cat.toLowerCase() == 'year') return true;
      }
      // フォールバック: 4桁の西暦っぽいものは除外
      return RegExp(r'^(19|20)\d{2}$').hasMatch(label);
    }

    bool isCharacter(String label) {
      if (_tagToCategory != null) {
        final cat = _tagToCategory![label]?.toLowerCase();
        if (cat == 'character') return true;
      }
      return false;
    }

    final character = <String>[];
    final features = <String>[];
    for (final s in effective) {
      final label = s.label;
      if (isYear(label)) continue; // year は無視
      if (isCharacter(label)) {
        character.add(label);
      } else {
        features.add(label);
      }
    }

    // 特徴は上位10件だけ
    final featureTop = features.take(10).toList(growable: false);

    // 結合（キャラを先頭にして特別扱い）
    final merged = <String>[...character, ...featureTop];
    if (merged.isEmpty) {
      merged.add('タグが見つかりませんでした');
    }

    log('Detected characters: $character');
    log('Detected features(top10): $featureTop');

    return {
      'tags': merged,
      'characterTags': character,
      'featureTags': featureTop,
      'image': imgBundle.base64Image,
    };
  }

  @override
  Future<void> dispose() async {
    _interpreter.close();
  }

  // ------------ helpers ------------

  Future<void> _loadLabelsFromJson(String jsonPath) async {
    final raw = await File(jsonPath).readAsString();
    final Map<String, dynamic> j = json.decode(raw);

    _totalTagsFromJson =
        (j['dataset_info']?['total_tags'] as num?)?.toInt() ?? -1;

    final map = j['dataset_info']?['tag_mapping']?['tag_to_category'];
    if (map is Map) {
      _tagToCategory = map.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    final idxToTag = j['dataset_info']?['tag_mapping']?['idx_to_tag'];
    if (idxToTag is Map<String, dynamic>) {
      final entries =
          idxToTag.entries
              .map((e) => MapEntry(int.parse(e.key), e.value.toString()))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      _labels = entries.map((e) => e.value).toList();
      log('Loaded ${_labels.length} labels from idx_to_tag.');
      return;
    }

    final tagToIdx = j['dataset_info']?['tag_mapping']?['tag_to_idx'];
    if (tagToIdx is Map<String, dynamic>) {
      final pairs =
          tagToIdx.entries
              .map((e) => MapEntry((e.value as num).toInt(), e.key.toString()))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      _labels = pairs.map((e) => e.value).toList();
      log('Loaded ${_labels.length} labels from tag_to_idx.');
      return;
    }

    throw StateError('Label JSON does not contain idx_to_tag nor tag_to_idx.');
  }

  _ImgBundle _preprocess(String filePath, int inputSize) {
    final bytes = File(filePath).readAsBytesSync();
    final original = img.decodeImage(bytes);
    if (original == null) {
      throw ArgumentError('Failed to decode image: $filePath');
    }

    // アスペクト比維持で長辺を inputSize に → 中央クロップで正方形 → inputSize
    final w = original.width, h = original.height;
    img.Image resized;
    if (w == h) {
      resized = img.copyResize(
        original,
        width: inputSize,
        height: inputSize,
        interpolation: img.Interpolation.linear,
      );
    } else {
      final scale = (w > h) ? inputSize / h : inputSize / w;
      final tw = (w * scale).round();
      final th = (h * scale).round();
      final tmp = img.copyResize(
        original,
        width: tw,
        height: th,
        interpolation: img.Interpolation.linear,
      );
      final left = ((tw - inputSize) / 2).floor().clamp(0, tw - inputSize);
      final top = ((th - inputSize) / 2).floor().clamp(0, th - inputSize);
      resized = img.copyCrop(
        tmp,
        x: left,
        y: top,
        width: inputSize,
        height: inputSize,
      );
    }

    final pngBytes = img.encodePng(resized);
    final b64 = base64Encode(pngBytes);
    return _ImgBundle(
      image: resized,
      base64Image: 'data:image/png;base64,$b64',
    );
  }

  /*
  List<String> _postprocess(
    List<double> probs,
    List<String> labels, {
    double threshold = 0.5,
    int topK = 20,
  }) {
    final N = math.min(probs.length, labels.length);

    final passed = <_ScoredLabel>[];
    for (int i = 0; i < N; i++) {
      final p = probs[i];
      if (p >= threshold) {
        passed.add(_ScoredLabel(labels[i], p));
      }
    }

    if (passed.isNotEmpty) {
      passed.sort((a, b) => b.score.compareTo(a.score));
      return passed.map((e) => e.label).toList(growable: false);
    }

    final all = List<_ScoredLabel>.generate(
      N,
      (i) => _ScoredLabel(labels[i], probs[i]),
      growable: false,
    )..sort((a, b) => b.score.compareTo(a.score));

    final k = math.min(topK, all.length);
    return all.take(k).map((e) => e.label).toList(growable: false);
  }
  */

  double _sigmoid(double x) {
    if (x >= 0) {
      final z = math.exp(-x);
      return 1.0 / (1.0 + z);
    } else {
      final z = math.exp(x);
      return z / (1.0 + z);
    }
  }

  int _float32ToHalfBits(double val) {
    final bd = ByteData(4);
    bd.setFloat32(0, val, Endian.little);
    final x = bd.getUint32(0, Endian.little);

    final sign = ((x >> 31) & 0x1);
    int exp = ((x >> 23) & 0xff);
    int mant = x & 0x7fffff;

    int signH = sign << 15;

    if (exp == 255) {
      if (mant != 0) return signH | 0x7e00; // qNaN
      return signH | 0x7c00; // Inf
    }

    int expH = exp - 127 + 15;

    if (expH >= 0x1f) {
      return signH | 0x7c00; // Inf
    } else if (expH <= 0) {
      if (expH < -10) return signH; // -> 0
      mant |= 0x00800000;
      int shift = 1 - expH;
      int mantH = mant >> (shift + 13);
      int round = (mant >> (shift + 12)) & 0x1;
      mantH += round;
      return signH | mantH;
    } else {
      int mantH = mant >> 13;
      int round = (mant >> 12) & 0x1;
      mantH += round;
      if ((mantH & 0x0400) != 0) {
        mantH &= 0x03ff;
        expH += 1;
        if (expH >= 0x1f) {
          return signH | 0x7c00;
        }
      }
      return signH | (expH << 10) | mantH;
    }
  }

  double _halfBitsToFloat32(int h) {
    final sign = (h >> 15) & 0x1;
    int exp = (h >> 10) & 0x1f;
    int mant = h & 0x3ff;

    int signF = sign << 31;
    int expF, mantF;

    if (exp == 0) {
      if (mant == 0) {
        expF = 0;
        mantF = 0;
      } else {
        int e = -1;
        int m = mant;
        while ((m & 0x400) == 0) {
          m <<= 1;
          e -= 1;
        }
        m &= 0x3ff;
        expF = (e + 1 + 127 - 15) << 23;
        mantF = m << 13;
      }
    } else if (exp == 0x1f) {
      expF = 0xff << 23;
      mantF = mant << 13;
    } else {
      expF = (exp + 127 - 15) << 23;
      mantF = mant << 13;
    }

    final bits = signF | expF | mantF;
    final bd = ByteData(4);
    bd.setUint32(0, bits, Endian.little);
    return bd.getFloat32(0, Endian.little).toDouble();
  }
}

class _ImgBundle {
  final img.Image image;
  final String base64Image;
  _ImgBundle({required this.image, required this.base64Image});
}

class _ScoredLabel {
  final String label;
  final double score;
  _ScoredLabel(this.label, this.score);
}

/*
/// ONNXランナー（[1,3,512,512] 対応、NCHW、ImageNet正規化）
class OnnxModelRunner implements ModelRunner {
  late ort.OrtSession _session;
  late List<String> _labels;
  late int _inputSize;
  late String _inputName;

  @override
  Future<void> load(
    String modelPath,
    String labelPath, {
    required int inputSize,
    required String inputType,
  }) async {
    _inputSize = inputSize;

    // セッション作成
    final options = ort.OrtSessionOptions();
    _session = ort.OrtSession.fromFile(File(modelPath), options);

    // 入力名（最初の入力）
    final inputNames = _session.inputNames;
    _inputName = inputNames.isNotEmpty ? inputNames.first : 'input';

    // ラベル（JSON形式: dataset_info.tag_mapping.tag_to_idx）
    final jsonStr = await File(labelPath).readAsString();
    final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
    final mapping =
        (jsonMap['dataset_info']?['tag_mapping']?['tag_to_idx']
            as Map<String, dynamic>);
    final size = mapping.length;
    final labels = List<String>.filled(size, '', growable: false);
    mapping.forEach((k, v) {
      final idx = (v as num).toInt();
      if (idx >= 0 && idx < size) labels[idx] = k;
    });
    _labels = labels;
  }

  @override
  Map<String, dynamic> analyze(String filePath) {
    log("解析を開始(ONNX)：$filePath");

    final imgBundle = _preprocess(filePath, _inputSize, normalize: true);

    // NCHWのFloat32List
    final H = _inputSize, W = _inputSize;
    final data = Float32List(1 * 3 * H * W);
    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        final p = imgBundle.image.getPixel(x, y);
        final r = p.r / 255.0;
        final g = p.g / 255.0;
        final b = p.b / 255.0;
        // ImageNet正規化（RGB）
        final rn = (r - 0.485) / 0.229;
        final gn = (g - 0.456) / 0.224;
        final bn = (b - 0.406) / 0.225;
        final base = y * W + x;
        data[0 * H * W + base] = rn; // R
        data[1 * H * W + base] = gn; // G
        data[2 * H * W + base] = bn; // B
      }
    }

    final inputTensor = ort.OrtValueTensor.createTensorWithDataList(data, [
      1,
      3,
      H,
      W,
    ]);

    final outputs = _session.run(ort.OrtRunOptions(), {
      _inputName: inputTensor,
    });
    // 最初の出力を利用
    final first = outputs.first as ort.OrtValueTensor;
    final dynamic raw = first.value; // expect Float32List
    final scores = raw is Float32List
        ? raw
        : Float32List.fromList(List<double>.from(raw as List));

    final tags = _postprocess(scores, _labels);
    return {
      'tags': tags.isEmpty ? ['タグが見つかりませんでした'] : tags,
      'image': imgBundle.base64Image,
    };
  }

  @override
  Future<void> dispose() async {}
}
*/

/// ランナー選択（ID/拡張子でディスパッチ可能）。
ModelRunner _selectRunner(String modelId, String modelPath) {
  final id = modelId.toLowerCase();
  // IDでのディスパッチ（今後ここに追加していく）
  const onnxIds = {
    'camie-tagger-v2',
    'camie-tagger-v2_float32',
    'camie-tagger-v2_float16',
  };
  // 今tfliteしか実装していないのでアプリのサイズを抑えるためにコメントアウト
  if (onnxIds.contains(id) || modelPath.toLowerCase().endsWith('.onnx')) {
    log('ONNXモデルを検出しましたが、ONNXランナーは未実装です。');
    return TfliteModelRunner();
    // return OnnxModelRunner();
  }
  const camieIds = {
    "camie-tagger-v2_float16_tflite",
    "camie-tagger-v2_simplified_float16_tflite",
  };
  if (camieIds.contains(id) || modelPath.toLowerCase().endsWith('.tflite')) {
    return TfliteNhwcModelRunner();
  }
  // 既定はTFLite
  return TfliteModelRunner();
}

class _PreprocessedImage {
  final img.Image image;
  final String base64Image; // デバッグ表示用
  _PreprocessedImage(this.image, this.base64Image);
}

_PreprocessedImage _preprocess(String filePath, int inputSize) {
  final imageFile = File(filePath);
  final imageBytes = imageFile.readAsBytesSync();
  img.Image? image = img.decodeImage(imageBytes);
  if (image == null) throw Exception('Failed to decode');

  // アスペクト比維持でリサイズ
  img.Image resizedImage;
  if (image.width > image.height) {
    resizedImage = img.copyResize(image, width: inputSize);
  } else {
    resizedImage = img.copyResize(image, height: inputSize);
  }

  // パディング（背景は黒）
  final paddedImage = img.Image(
    width: inputSize,
    height: inputSize,
    numChannels: 3,
  );
  img.fill(paddedImage, color: img.ColorRgb8(0, 0, 0));

  final offsetX = (inputSize - resizedImage.width) ~/ 2;
  final offsetY = (inputSize - resizedImage.height) ~/ 2;

  final validImage = img.compositeImage(
    paddedImage,
    resizedImage,
    dstX: offsetX,
    dstY: offsetY,
  );

  final pngBytes = img.encodePng(validImage);
  final base64Image = base64Encode(pngBytes);
  return _PreprocessedImage(validImage, base64Image);
}

List<String> _postprocess(
  List<double> scores,
  List<String> labels, {
  double threshold = 0.35,
}) {
  final result = <String>[];
  final len = scores.length < labels.length ? scores.length : labels.length;
  for (var i = 0; i < len; i++) {
    final s = scores[i];
    if (s > threshold) result.add(labels[i].replaceAll('_', ' '));
  }
  return result;
}

// --- メインスレッドで実行されるコード ---

class AiService {
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;

  Isolate? _isolate;
  String? _loadedModelId;
  SendPort? _isolateSendPort;
  ReceivePort? _mainReceivePort;
  // final AiModelDefinition modelDefinition;
  // final Completer<void> _isolateReadyCompleter = Completer<void>();
  Completer<void>? _isolateReadyCompleter;

  AiService._internal();

  /*
  AiService({required this.modelDefinition}) {
    _initIsolate();
  }
  */
  Future<void> switchModel(AiModelDefinition modelDef) async {
    // 既存のIsolateがあれば、まず安全に終了させる
    dispose();

    // Isolateの準備が完了したことを通知するための新しいCompleterを用意
    _isolateReadyCompleter = Completer<void>();

    _mainReceivePort = ReceivePort();
    final token = RootIsolateToken.instance;
    if (token == null) {
      log('Could not get RootIsolateToken');
      return;
    }

    _isolate = await Isolate.spawn(
      _aiIsolateEntry,
      IsolateInitMessage(
        _mainReceivePort!.sendPort,
        token,
        modelDef.id,
        modelDef.modelFileName,
        modelDef.labelFileName,
        modelDef.inputType,
        modelDef.inputSize,
      ),
    );

    _mainReceivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message == 'ready') {
        _isolateReadyCompleter?.complete();
        log(
          'AI Service: Isolate connection established for ${modelDef.displayName}.',
        );
      }
    });
  }

  Future<void> ensureModelLoaded(AiModelDefinition modelDef) async {
    // 既に正しいモデルがロード済みなら、何もしない
    if (_loadedModelId == modelDef.id && _isolate != null) {
      log('Correct model is already loaded.');
      return;
    }

    log('Switching model to: ${modelDef.displayName}');

    // ファイルの存在と整合性を再確認
    final directory = await getApplicationSupportDirectory();
    final modelPath = '${directory.path}/${modelDef.modelFileName}';
    final labelPath = '${directory.path}/${modelDef.labelFileName}';

    final modelFile = File(modelPath);
    final labelFile = File(labelPath);

    if (!await modelFile.exists() || !await labelFile.exists()) {
      log(
        'Model or label files not found. Model: ${await modelFile.exists()}, Label: ${await labelFile.exists()}',
      );
      throw Exception('モデルファイルまたはラベルファイルが見つかりません。');
    }

    log('Model files confirmed to exist. Starting model loading...');

    // 既存のIsolateがあれば、まず安全に終了させる
    dispose();

    _isolateReadyCompleter = Completer<void>();
    _mainReceivePort = ReceivePort();
    final token = RootIsolateToken.instance;
    if (token == null) {
      log('Could not get RootIsolateToken');
      return;
    }

    _isolate = await Isolate.spawn(
      _aiIsolateEntry,
      IsolateInitMessage(
        _mainReceivePort!.sendPort,
        token,
        modelDef.id,
        modelDef.modelFileName,
        modelDef.labelFileName,
        modelDef.inputType,
        modelDef.inputSize,
      ),
    );

    _mainReceivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message == 'ready') {
        _loadedModelId = modelDef.id; // ★★★ ロードが完了したモデルIDを記録
        _isolateReadyCompleter?.complete();
        log(
          'AI Service: Isolate connection established for ${modelDef.displayName}.',
        );
      }
    });

    // Isolateの準備が完了するまで待つ
    await _isolateReadyCompleter?.future;
  }

  // ★★★ 解析結果を格納するカスタムクラス ★★★
  Future<Map<String, dynamic>> analyzeImage(File imageFile) async {
    if (_isolateReadyCompleter == null ||
        !_isolateReadyCompleter!.isCompleted) {
      log('AI Service: Waiting for model to be loaded...');
      await _isolateReadyCompleter?.future;
    }
    // await _isolateReadyCompleter.future;
    if (_isolateSendPort == null) return {'error': 'AIサービス未準備'};

    final completer = Completer<Map<String, dynamic>>();
    final tempReceivePort = ReceivePort();

    tempReceivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        completer.complete(message);
      }
      tempReceivePort.close();
    });

    _isolateSendPort!.send(
      IsolateAnalyzeRequest(imageFile.path, "", tempReceivePort.sendPort),
    );

    return completer.future;
  }

  /// タグがNSFWかどうかを判定する
  bool isNsfw(String label) {
    // rating系タグでrating_general以外はNSFW
    if (label.startsWith('rating_') && label != 'rating_general') {
      return true;
    }
    return false;
  }

  void dispose() {
    /*
    _isolateSendPort?.send('close');
    _mainReceivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    log('AI Service: Disposed.');
    */
    _isolateSendPort?.send('close');
    _mainReceivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    log('AI Service: Disposed.');
  }
}
