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
    id: "camie-tagger_integer_quant",
    displayName: "Camie Tagger (最速・省電力型)",
    modelFileName: "camie-tagger_integer_quant.tflite",
    modelFileHash:
        "7b23b66422f5af01a3a48296c34189810fa936c7f2d673d238a1c708a967a5dd",
    modelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger_integer_quant.tflite",
    labelFileName: "camie-tagger_labels.csv",
    labelFileHash:
        "d1aad7975cb31a25a237f489a7036b38af6e584da5e5ecd2597f1bbf33bf616d",
    labelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/val_dataset.csv",
    displaySize: "220MB",
    inputType: "int8",
  ),
  const AiModelDefinition(
    id: "camie-tagger-v2",
    displayName: "camie-tagger-v2",
    modelFileName: "camie-tagger-v2.onnx",
    modelFileHash:
        "ab0aaf253e3d546090001bec9bebc776c354ab6800f442ab9167af87b4a953ac",
    modelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2.onnx",
    labelFileName: "camie-tagger_labels.csv",
    labelFileHash:
        "de9f962eb0fd86b7e30d0af4e8c7990205200d70e955d8ecae60f87d14eae66b",
    labelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2-metadata.json",
    displaySize: "750MB",
    inputType: "int8",
  ),
  const AiModelDefinition(
    id: "camie-tagger-v2_float32",
    displayName: "camie-tagger-v2_float32",
    modelFileName: "camie-tagger-v2_float32.onnx",
    modelFileHash:
        "3a6a3a3929035c8a9a8d11b7257f1a64",
    modelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2_float32.tflite",
    labelFileName: "camie-tagger_labels.csv",
    labelFileHash:
        "fa3b5bae245de0316a9f910534230291",
    labelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2-metadata.json",
    displaySize: "750MB",
    inputType: "int8",
  ),
    const AiModelDefinition(
    id: "camie-tagger-v2_float16",
    displayName: "camie-tagger-v2_float16",
    modelFileName: "camie-tagger-v2_float16.onnx",
    modelFileHash:
      "98b3f0be9607a04e5186b068b37a0822",
    modelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2_float16.tflite",
    labelFileName: "camie-tagger_labels.csv",
    labelFileHash:
        "fa3b5bae245de0316a9f910534230291",
    labelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/camie-tagger-v2-metadata.json",
    displaySize: "750MB",
    inputType: "int8",
  ),
];
