# moe_viewer

## これは何

スマホにある二次元画像を見るためのアプリ

今はAndroid版のみサポートしていますが、そのうちiOSもテストします。

## 何ができるの（予定）

+ 任意ディレクトリの読み込み
+ シャッフル
+ 横スライド、縦スライドでイラスト閲覧
+ PixivからダウンロードしたファイルならPixivへジャンプ可能
+ AIによるタグ付け＆検索
+ 重複画像削除
+ タグによる分類
+ 画像をまとめたフォルダー作成
+ ファイルの転送

## ビルド

```sh
flutter build apk --release
# adbでスマホと接続できてるなら
flutter install android
```

## ライセンス

アプリで使用可能な[camie-tagger-v2](https://huggingface.co/Camais03/camie-tagger-v2)がGPL3.0なのでそれを継承してGPL3.0となっています。

## その他

### リリースに添付したcamie-tagger-v2のtflite生成方法

onnx2tfで普通に変換すると

```txt
I/tflite  ( 6269): Initialized TensorFlow Lite runtime.
E/tflite  ( 6269): Select TensorFlow op(s), included in the given model, is(are) not supported by this interpreter. Make sure you apply/link the Flex delegate before inference. For the Android, it can be resolved by adding "org.tensorflow:tensorflow-lite-select-tf-ops" dependency. See instructions: https://www.tensorflow.org/lite/guide/ops_select
E/tflite  ( 6269): Node number 213 (FlexErf) failed to prepare.
```

というエラーが出ます。
エラーメッセージに従って`/android/app/build.gradle.kts`にdependenciesを追加すれば動くっぽいのですが、今回のプロジェクトではエラーが消えなかったのでSelect TF Ops不使用版を生成するようにしています。
上のエラーの消し方が分かる方がいましたら教えていただきたいです。

```sh
# https://github.com/PINTO0309/onnx2tf
docker run --rm -it -v `pwd`:/workdir -w /workdir docker.io/pinto0309/onnx2tf:1.28.2
onnx2tf -i camie-tagger-v2_simplified.onnx -o camie_tf_fp16_builtin -b 1 -ois "input:1,3,512,512" -rtpo Erf Gelu -eatfp16
```
