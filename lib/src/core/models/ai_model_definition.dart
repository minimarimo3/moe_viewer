// lib/services/ai_model_definitions.dart

// 各モデルの仕様を定義するクラス
class AiModelDefinition {
  final String id; // 内部的な識別子
  final String displayName; // UIに表示する名前
  final String modelFileName; // ダウンロード後のファイル名
  final String modelFileHash; // モデルファイルのSHA256ハッシュ値
  final String labelFileName; // ラベルファイル名
  final String labelFileHash; // ラベルファイルのSHA256ハッシュ値
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
    id: "nazo",
    displayName: "nazo",
    modelFileName: "converted_model.tflite",
    modelFileHash:
        "e0d9df9981ec3a4b0cbf593b2ef6b9ba1116d35c2fcd38df82f820cb4af8d0e1",
    modelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/converted_model.tflite",
    labelFileName: "camie-tagger_labels.csv",
    labelFileHash:
        "d1aad7975cb31a25a237f489a7036b38af6e584da5e5ecd2597f1bbf33bf616d",
    labelDownloadUrl:
        "https://github.com/minimarimo3/moe_viewer/releases/download/v0.0.0/val_dataset.csv",
    displaySize: "850MB",
    inputType: "int8",
  ),
];
