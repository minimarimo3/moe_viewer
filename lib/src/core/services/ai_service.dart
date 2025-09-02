import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import '../models/ai_model_definition.dart';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

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

  Interpreter? interpreter;
  List<String>? labels;

  // モデル・ラベルが指定されている場合のみロードを試行
  if (initMessage.labelFileName.isNotEmpty &&
      initMessage.modelFileName.isNotEmpty) {
    try {
      final directory = await getApplicationSupportDirectory();
      final modelPath = '${directory.path}/${initMessage.modelFileName}';
      final labelPath = '${directory.path}/${initMessage.labelFileName}';

      interpreter = Interpreter.fromFile(File(modelPath));
      final labelString = await File(labelPath).readAsString();
      labels = labelString
          .split('\n')
          .where((line) => line.isNotEmpty)
          .map((line) {
            final parts = line.split(',');
            return parts.length > 1 ? parts[1].replaceAll('"', '').trim() : '';
          })
          .where((tag) => tag.isNotEmpty)
          .toList();
      log('AI Isolate: Model and labels loaded successfully.');
    } catch (e) {
      log('AI Isolate: Failed to load model or labels: $e');
    }
  }

  mainSendPort.send('ready'); // 準備完了をメインスレッドに通知

  await for (final request in isolateReceivePort) {
    if (request is IsolateAnalyzeRequest) {
      if (interpreter == null || labels == null) {
        request.replyPort.send({'error': 'AIモデル未ロード'});
        continue;
      }
      try {
        final result = _analyze(interpreter, labels, request.filePath);
        request.replyPort.send(result);
      } catch (e) {
        log('AI Isolate: Error during analysis: $e');
        request.replyPort.send({'error': 'AI解析エラー'});
      }
    } else if (request == 'close') {
      interpreter?.close();
      isolateReceivePort.close();
      break;
    }
  }
  log('AI Isolate: Closed.');
}

class IsolateInitMessage {
  final SendPort sendPort;
  final RootIsolateToken token;
  final String modelFileName;
  final String labelFileName;
  final String inputType;
  IsolateInitMessage(
    this.sendPort,
    this.token,
    this.modelFileName,
    this.labelFileName,
    this.inputType,
  );
}

/// これはwdとかだとちゃんと動くデータ
Map<String, dynamic> _analyze(
  Interpreter interpreter,
  List<String> labels,
  String filePath,
) {
  log("解析を開始：$filePath");
  const int inputSize = 448;

  // --- 前処理 ---
  final imageFile = File(filePath);
  final imageBytes = imageFile.readAsBytesSync();
  img.Image? image = img.decodeImage(imageBytes);
  if (image == null) throw Exception('Failed to decode');

  // アスペクト比を保ったままリサイズ
  img.Image resizedImage;
  if (image.width > image.height) {
    resizedImage = img.copyResize(image, width: inputSize);
  } else {
    resizedImage = img.copyResize(image, height: inputSize);
  }

  // --- 正規化 (ImageNetのmean/stdを使用) ---
  final mean = [0.485, 0.456, 0.406];
  final std = [0.229, 0.224, 0.225];

  // 正方形のキャンバスを作成し、中央に配置（パディング）
  final paddedImage = img.Image(
    width: inputSize,
    height: inputSize,
    numChannels: 3,
  );
  // img.fill(paddedImage, color: img.ColorRgb8(255, 255, 255));
  final backgroundColorR = (255 - mean[0]) / std[0];
  final backgroundColorG = (255 - mean[1]) / std[1];
  final backgroundColorB = (255 - mean[2]) / std[2];

  img.fill(
    paddedImage,
    color: img.ColorFloat32.rgb(
      backgroundColorR,
      backgroundColorG,
      backgroundColorB,
    ),
  );

  final offsetX = (inputSize - resizedImage.width) ~/ 2;
  final offsetY = (inputSize - resizedImage.height) ~/ 2;

  var validImage = img.compositeImage(
    paddedImage,
    resizedImage,
    dstX: offsetX,
    dstY: offsetY,
  );

  // 入力テンソル [1, 448, 3, 448] (NCHW)
  final inputTensor = List.generate(
    1,
    (_) => List.generate(
      inputSize,
      (_) => List.generate(3, (_) => List.generate(inputSize, (_) => 0.0)),
    ),
  );

  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      // final pixel = paddedImage.getPixel(x, y);
      final pixel = validImage.getPixel(x, y);

      final r = pixel.r / 255.0;
      final g = pixel.g / 255.0;
      final b = pixel.b / 255.0;

      // RGB の順に格納、正規化
      // inputTensor[0][y][0][x] = (r - mean[0]) / std[0];
      // inputTensor[0][y][1][x] = (g - mean[1]) / std[1];
      // inputTensor[0][y][2][x] = (b - mean[2]) / std[2];
      inputTensor[0][y][0][x] = b;
      inputTensor[0][y][1][x] = g;
      inputTensor[0][y][2][x] = r;
    }
  }

  // --- 推論 ---
  // 出力テンソル [1, num_labels]
  final output = List.generate(1, (_) => List.filled(labels.length, 0.0));
  interpreter.run(inputTensor, output);

  // --- 結果解析 ---
  const double confidenceThreshold = 0.35;
  List<String> recognizedTags = [];
  for (var i = 0; i < labels.length; i++) {
    if (output[0][i] > confidenceThreshold) {
      recognizedTags.add(labels[i].replaceAll('_', ' '));
    }
  }
  log("解析完了：${recognizedTags.join(', ')}");

  // --- デバッグ用画像返却 ---
  final pngBytes = img.encodePng(validImage);
  final base64Image = base64Encode(pngBytes);

  return {
    'tags': recognizedTags.isEmpty ? ['タグが見つかりませんでした'] : recognizedTags,
    'image': base64Image,
  };
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
        modelDef.modelFileName,
        modelDef.labelFileName,
        modelDef.inputType,
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
        modelDef.modelFileName,
        modelDef.labelFileName,
        modelDef.inputType,
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
