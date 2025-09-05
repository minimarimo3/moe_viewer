// lib/services/ai_model_definitions.dart

// 各モデルの仕様を定義するクラス
class AiModelDefinition {
  final String id; // 内部的な識別子
  final String displayName; // UIに表示する名前
  final String modelFileName; // ダウンロード後のファイル名
  // GitHubから簡単に確認できるんでSHA256を使おうと思ったけど、
  //  キャリア乗り換え時無料配布スマホだと計算に数分かかるのでMD5に変更
  //  早くスマホ変えたい
  final String modelFileHash; // モデルファイルのMD5ハッシュ値
  final String labelFileName; // ラベルファイル名
  final String labelFileHash; // ラベルファイルのMD5ハッシュ値
  final String modelDownloadUrl; // ダウンロード元のURL (今はダミー)
  final String labelDownloadUrl; // ラベルファイルのダウンロード元URL
  final String displaySize; // UIに表示するサイズ (例: "350MB")
  final String inputType; // "int8" or "float32"
  final int inputSize; // 入力画像のサイズ

  const AiModelDefinition({
    required this.id,
    required this.displayName,
    required this.modelFileName,
    required this.modelFileHash,
    required this.labelFileName,
    required this.labelFileHash,
    required this.modelDownloadUrl,
    required this.labelDownloadUrl,
    required this.displaySize,
    required this.inputType,
    this.inputSize = 448,
  });
}

// 利用可能なAIモデルのリスト
final List<AiModelDefinition> availableModels = [
  const AiModelDefinition(
    id: 'none',
    displayName: 'AIを使用しない',
    modelFileName: '',
    modelDownloadUrl: '',
    modelFileHash: '',
    labelFileName: '',
    labelDownloadUrl: '',
    labelFileHash: '',
    displaySize: "",
    inputType: '',
  ),
  const AiModelDefinition(
    id: "camie-tagger-v2_simplified_float32_tflite",
    displayName: "camie-tagger-v2_simplified_float32(tflite)",
    modelFileName: "camie-tagger-v2_simplified_float32.tflite",
    modelFileHash: "ca35db24b93d7260e05b69180ce1e104",
    modelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2_simplified_float32.tflite",
    labelFileName: "camie-tagger-v2-metadata.json",
    labelFileHash: "fa3b5bae245de0316a9f910534230291",
    labelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2-metadata.json",
    displaySize: "780MB",
    inputType: "float16",
    inputSize: 512,
  ),
  const AiModelDefinition(
    id: "camie-tagger-v2_simplified_float16_tflite",
    displayName: "camie-tagger-v2_simplified_float16(tflite)",
    modelFileName: "camie-tagger-v2_simplified_float16.tflite",
    modelFileHash: "f80080d4403805cb896b22b649b52edd",
    modelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2_simplified_float16.tflite",
    labelFileName: "camie-tagger-v2-metadata.json",
    labelFileHash: "fa3b5bae245de0316a9f910534230291",
    labelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2-metadata.json",
    displaySize: "380MB",
    inputType: "float16",
    inputSize: 512,
  ),
];
