// 例外オブジェクトをユーザー向けの文言に整形するユーティリティ。

/// 例外 [e] をユーザー表示用の文字列に整形して返す。
///
/// `Object.toString()` の結果には `Exception: ` などの実装都合のプレフィックスが
/// 付くことがあり、そのままユーザーに見せると分かりにくい。ここで既知の
/// プレフィックスを取り除き、読みやすい文言に整える。
///
/// SnackBar 等でエラー内容をユーザーに提示する際は、生の `$e` を埋め込まず
/// 本関数を通すこと。
String describeError(Object e) {
  var text = e.toString();
  // よくある実装都合のプレフィックスを除去する。
  const prefixes = ['Exception: ', 'FormatException: ', 'Error: '];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length);
      break;
    }
  }
  return text;
}
