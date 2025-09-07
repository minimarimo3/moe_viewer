import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferencesのシングルトンヘルパー
/// 複数の呼び出しで同じインスタンスを再利用してパフォーマンスを向上
class SharedPreferencesHelper {
  static SharedPreferences? _instance;

  /// SharedPreferencesインスタンスを取得
  /// 初回のみ実際にインスタンスを作成し、以降はキャッシュしたものを返す
  static Future<SharedPreferences> get instance async {
    _instance ??= await SharedPreferences.getInstance();
    return _instance!;
  }

  /// テスト用にインスタンスをリセット
  static void resetInstance() {
    _instance = null;
  }
}
